#requires -Version 5.1
[CmdletBinding()]param([Parameter(Mandatory)][string]$EnginePath,[Parameter(Mandatory)][ValidateSet('ps51','pwsh')][string]$Label,[Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$RunId,[switch]$PatchOnly)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repo
$runRelative='out/'+$RunId+'-'+$Label
$local=Join-Path $repo $runRelative
if(Test-Path -LiteralPath $local){throw 'NEW_RUN_DIRECTORY_REQUIRED'}
[IO.Directory]::CreateDirectory($local)|Out-Null
$evidencePrefix=$Label+$(if($PatchOnly){'-patch'}else{''})
$records=New-Object Collections.Generic.List[object]
$source=@(Get-ChildItem -LiteralPath (Join-Path $repo 'kit'),(Join-Path $repo 'tests'),(Join-Path $repo 'tools') -Recurse -File)
$source+=Get-Item -LiteralPath (Join-Path $repo 'rescue.cmd')
$sourceManifest=@($source|Sort-Object FullName|ForEach-Object {@{path=$_.FullName.Substring($repo.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
function SaveJson($Path,$Data){[IO.File]::WriteAllText($Path,($Data|ConvertTo-Json -Depth 25).Replace([string][char]13,''),[Text.UTF8Encoding]::new($false))}
function Capture([string]$Name,[string]$Script,[string]$Arguments){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$EnginePath;$info.WorkingDirectory=$repo
    $info.Arguments='-NoLogo -NoProfile -NonInteractive -File "'+$Script+'" '+$Arguments
    $info.EnvironmentVariables['PSModulePath']=Join-Path (Split-Path -Parent $EnginePath) 'Modules'
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false);$info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    $start=[DateTime]::UtcNow;$timer=[Diagnostics.Stopwatch]::StartNew()
    try {
        $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(900000)){$p.Kill();$p.WaitForExit();throw 'REGRESSION_DRIVER_TIMEOUT'}
        $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult();$code=$p.ExitCode
        $timer.Stop()
        # Capture decoded text and re-encode to UTF-8; this is not a raw byte-stream capture. Share only captures without personal paths or common secret patterns.
        [IO.File]::WriteAllText((Join-Path $local ($Name+'.stdout.log')),$out,[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $local ($Name+'.stderr.log')),$err,[Text.UTF8Encoding]::new($false))
        if(($out+$err) -match '(?i)C:[\\/]Users[\\/]|sk-[a-zA-Z0-9_-]{20,}|-----BEGIN .*PRIVATE KEY-----'){throw 'CAPTURE_REQUIRES_PRIVATE_REVIEW'}
        foreach($suffix in @('stdout','stderr')){
            Copy-Item -LiteralPath (Join-Path $local ($Name+'.'+$suffix+'.log')) -Destination (Join-Path $repo ('evidence/'+$evidencePrefix+'-'+$Name+'.'+$suffix+'.log'))
        }
        $records.Add(@{name=$Name;executable=[IO.Path]::GetFileName($EnginePath);executable_sha256=(Get-FileHash -LiteralPath $EnginePath -Algorithm SHA256).Hash.ToLowerInvariant();arguments=$info.Arguments;working_directory='<REPOSITORY_ROOT>';started_at=$start.ToString('o');ended_at=[DateTime]::UtcNow.ToString('o');elapsed_seconds=[math]::Round($timer.Elapsed.TotalSeconds,2);exit_code=$code;capture='RUNTIME_CAPTURED_TEXT_REENCODED_UTF8_SAVED_WITHOUT_MANUAL_EDIT';stdout_decoder=$p.StandardOutput.CurrentEncoding.WebName;stderr_decoder=$p.StandardError.CurrentEncoding.WebName;saved_encoding='UTF-8_NO_BOM';decoding_policy='UTF8_REPLACEMENT_FALLBACK_INVALID_BYTES_MAY_CHANGE';child_environment=@{PSModulePath='<ENGINE_HOME>/Modules';scope='CHILD_PROCESS_ONLY'};stdout_sha256=(Get-FileHash (Join-Path $local ($Name+'.stdout.log'))).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash (Join-Path $local ($Name+'.stderr.log'))).Hash.ToLowerInvariant()})
        Write-Host ($Label+' '+$Name+' exit='+$code)
        SaveJson (Join-Path $repo ('evidence/'+$evidencePrefix+'-commands.json')) @{schema='rescue-command-capture-v1';provenance='Machine-captured process arguments, times, exits and StreamReader-decoded stdout/stderr text re-encoded to UTF-8. Saved files are not manually edited; they are not raw pipe bytes. Executable directory and working directory are represented by filename/hash and repository placeholder; not a reconstructed transcript.';synthetic_only=$true;records=@($records.ToArray());tested_source=$sourceManifest}
        if($code -ne 0){throw 'REGRESSION_CHILD_FAILED'}
        return $out
    } finally {$p.Dispose()}
}
if($PatchOnly){
    $null=Capture 'regression' 'tests/Run-Tests.ps1' ('-ResultDirectory "'+$runRelative+'/cases" -CaseFilter "task*"')
    Copy-Item -LiteralPath (Join-Path $local 'cases/results.json') -Destination (Join-Path $repo ('evidence/'+$evidencePrefix+'-results.json'))
    $null=Capture 'encoding' 'tests/EncodingChild.ps1' ''
    $actual=[IO.File]::ReadAllText((Join-Path $local 'encoding.stdout.log'))
    $expected='中文|é|'+[char]0xfffd+'|end'
    $errorText=[IO.File]::ReadAllText((Join-Path $local 'encoding.stderr.log'))
    $expectedError='err|café|中文'
    if($actual -cne $expected -or $errorText -cne $expectedError){throw 'TEXT_REENCODING_BOUNDARY_WRONG'}
    $rawPrefix=[Text.Encoding]::UTF8.GetBytes('中文|é|');$rawSuffix=[Text.Encoding]::UTF8.GetBytes('|end')
    $raw=New-Object byte[] ($rawPrefix.Length+1+$rawSuffix.Length)
    [Array]::Copy($rawPrefix,0,$raw,0,$rawPrefix.Length);$raw[$rawPrefix.Length]=255
    [Array]::Copy($rawSuffix,0,$raw,$rawPrefix.Length+1,$rawSuffix.Length)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$rawHash=([BitConverter]::ToString($sha.ComputeHash($raw))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    if((Get-FileHash (Join-Path $local 'encoding.stdout.log')).Hash.ToLowerInvariant() -eq $rawHash){throw 'DECODED_CAPTURE_MISREPRESENTED_AS_BYTES'}
    SaveJson (Join-Path $repo ('evidence/'+$evidencePrefix+'-encoding-results.json')) @{schema='rescue-text-encoding-check-v1';status='PASS';synthetic_only=$true;non_ascii_stdout_stderr_preserved=$true;invalid_utf8_replaced=$true;saved_text_hash_differs_from_known_pipe_fixture=$true;capture='RUNTIME_CAPTURED_TEXT_REENCODED_UTF8_SAVED_WITHOUT_MANUAL_EDIT'}
}else{
    $null=Capture 'regression' 'tests/Run-Tests.ps1' ('-ResultDirectory "'+$runRelative+'/cases"')
    Copy-Item -LiteralPath (Join-Path $local 'cases/results.json') -Destination (Join-Path $repo ('evidence/'+$Label+'-results.json'))
    $null=Capture 'entry' 'tests/Smoke-Entry.ps1' ('-ResultDirectory "'+$runRelative+'/entry"')
    Copy-Item -LiteralPath (Join-Path $local 'entry/smoke-results.json') -Destination (Join-Path $repo ('evidence/'+$Label+'-entry-results.json'))
    $null=Capture 'window' 'tests/Window-Smoke.ps1' ('-ResultDirectory "'+$runRelative+'/window"')
    Copy-Item -LiteralPath (Join-Path $local 'window/window-results.json') -Destination (Join-Path $repo ('evidence/'+$Label+'-window-results.json'))
}
$static=Capture 'static' 'tools/Test-Source.ps1' ''
SaveJson (Join-Path $repo ('evidence/'+$evidencePrefix+'-static-results.json')) ($static|ConvertFrom-Json)
foreach($item in $sourceManifest){if((Get-FileHash (Join-Path $repo $item.path)).Hash.ToLowerInvariant() -ne $item.sha256){throw 'SOURCE_CHANGED_DURING_REGRESSION'}}
Write-Host ($Label+' checks complete; scope='+$(if($PatchOnly){'TARGETED_F09_F10_BASELINE_REUSED'}else{'FULL_SYNTHETIC'}))
