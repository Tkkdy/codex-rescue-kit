#requires -Version 5.1
[CmdletBinding()]param([Parameter(Mandatory)][string]$GitExecutable)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$baseline='6a39c247cc4f64e9d1cc14bbf33d02ecd3cedd4b'
function ReadEvidence([string]$Name){[IO.File]::ReadAllText((Join-Path $repo ('evidence/'+$Name)))|ConvertFrom-Json}
function HashFile([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function CheckPath([string]$Path){
    if($Path -notmatch '^(kit/|tests/|tools/|rescue\.cmd$)' -or $Path -match '\.\.|:|^/|\\'){throw 'SOURCE_EVIDENCE_PATH_INVALID'}
}
$baselineHashes=@{}
function BaselineHash([string]$Path){
    CheckPath $Path
    if($baselineHashes.ContainsKey($Path)){return $baselineHashes[$Path]}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$GitExecutable;$info.WorkingDirectory=$repo
    $info.Arguments='cat-file blob "'+$baseline+':'+$Path+'"'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $null=$p.Start();$err=$p.StandardError.ReadToEndAsync()
        # Hash bytes directly. Do not use a text reader for Git source bytes.
        $hash=([BitConverter]::ToString($sha.ComputeHash($p.StandardOutput.BaseStream))).Replace('-','').ToLowerInvariant()
        $p.WaitForExit();$null=$err.GetAwaiter().GetResult()
        if($p.ExitCode -ne 0){throw 'BASELINE_GIT_OBJECT_UNAVAILABLE'}
        $baselineHashes[$Path]=$hash;return $hash
    }finally{$sha.Dispose();$p.Dispose()}
}
$actual=@(Get-ChildItem -LiteralPath (Join-Path $repo 'kit'),(Join-Path $repo 'tests'),(Join-Path $repo 'tools') -Recurse -File)
$actual+=Get-Item -LiteralPath (Join-Path $repo 'rescue.cmd')
$current=@{}
foreach($f in $actual){$path=$f.FullName.Substring($repo.Length+1).Replace('\','/');$current[$path]=HashFile $f.FullName}
$manifest=ReadEvidence 'current-source-manifest.json'
if(@($manifest.files).Count -ne $current.Count){throw 'CURRENT_SOURCE_COUNT_MISMATCH'}
$seen=@{}
foreach($item in $manifest.files){
    CheckPath $item.path
    if($seen.ContainsKey($item.path) -or -not $current.ContainsKey($item.path) -or $current[$item.path] -ne $item.sha256){throw 'CURRENT_SOURCE_CHANGED'}
    $seen[$item.path]=$true
}
$patch=ReadEvidence 'patch-validation.json'
if($patch.baseline_commit -ne $baseline -or $patch.scope -ne 'TARGETED_F09_F10_BASELINE_REUSED' -or $patch.public_release -ne $false){throw 'PATCH_SCOPE_INVALID'}
$old=ReadEvidence 'source-manifest.json'
$oldMap=@{}
foreach($item in $old.files){
    CheckPath $item.path
    if($oldMap.ContainsKey($item.path) -or (BaselineHash $item.path) -ne $item.sha256){throw 'BASELINE_SOURCE_MISMATCH'}
    $oldMap[$item.path]=$item.sha256
    if(-not $current.ContainsKey($item.path)){throw 'BASELINE_SOURCE_REMOVED_REVIEW_REQUIRED'}
}
$expectedChanged=@($current.Keys|Where-Object {-not $oldMap.ContainsKey($_) -or $current[$_] -ne $oldMap[$_]})
$changed=@{}
foreach($item in $patch.changed_source){
    CheckPath $item.path
    if($changed.ContainsKey($item.path) -or $item.path -notin $expectedChanged -or $current[$item.path] -ne $item.sha256){throw 'PATCH_CHANGE_MISMATCH'}
    if($oldMap.ContainsKey($item.path)){if($item.before_sha256 -ne $oldMap[$item.path]){throw 'PATCH_BASELINE_MISMATCH'}}
    elseif($item.before_sha256 -ne 'NEW_FILE'){throw 'PATCH_NEW_SOURCE_MISMATCH'}
    $changed[$item.path]=$true
}
if($changed.Count -ne $expectedChanged.Count){throw 'PATCH_UNDECLARED_SOURCE_CHANGE'}
foreach($label in @('ps51','pwsh')){
    $result=ReadEvidence ($label+'-results.json')
    if(-not $result.synthetic_only -or $result.failed -ne 0 -or $result.passed -ne 62){throw 'BASELINE_TESTS_INCOMPLETE'}
    $window=ReadEvidence ($label+'-window-results.json')
    if($window.status -ne 'PASS' -or $window.elapsed_seconds -lt 60 -or $window.overall_verification_exit -ne 3){throw 'BASELINE_WINDOW_INCOMPLETE'}
    foreach($kind in @('baseline','patch')){
        $prefix=$label+$(if($kind -eq 'patch'){'-patch'}else{''})
        $commands=ReadEvidence ($prefix+'-commands.json')
        $names=@('regression','entry','window','static')
        $sourceMap=$oldMap
        if($kind -eq 'patch'){$names=@('regression','encoding','static');$sourceMap=$current}
        if(-not $commands.synthetic_only -or @($commands.records).Count -ne $names.Count){throw 'CAPTURE_RECORD_COUNT'}
        $recordNames=@{}
        foreach($record in $commands.records){
            if($record.name -notin $names -or $recordNames.ContainsKey($record.name) -or $record.exit_code -ne 0 -or
                $record.capture -ne 'RUNTIME_CAPTURED_TEXT_REENCODED_UTF8_SAVED_WITHOUT_MANUAL_EDIT'){throw 'CAPTURE_RECORD_INVALID'}
            $recordNames[$record.name]=$true
            foreach($suffix in @('stdout','stderr')){
                if((HashFile (Join-Path $repo ('evidence/'+$prefix+'-'+$record.name+'.'+$suffix+'.log'))) -ne $record.($suffix+'_sha256')){throw 'CAPTURE_HASH_MISMATCH'}
            }
        }
        if(@($commands.tested_source).Count -ne $sourceMap.Count){throw 'CAPTURE_SOURCE_COUNT'}
        $seen=@{}
        foreach($item in $commands.tested_source){
            CheckPath $item.path
            if($seen.ContainsKey($item.path) -or -not $sourceMap.ContainsKey($item.path) -or $sourceMap[$item.path] -ne $item.sha256){throw 'CAPTURE_SOURCE_MISMATCH'}
            $seen[$item.path]=$true
        }
    }
    $result=ReadEvidence ($label+'-patch-results.json')
    if(-not $result.synthetic_only -or $result.failed -ne 0 -or $result.passed -ne 8 -or
        $result.execution_scope -ne 'TARGETED_ONLY_NOT_FULL_REGRESSION' -or $result.case_filter -ne 'task*' -or
        @($result.cases).Count -ne 8 -or @($result.cases|Where-Object status -ne 'PASS').Count){throw 'PATCH_TESTS_INCOMPLETE'}
    $encoding=ReadEvidence ($label+'-patch-encoding-results.json')
    if($encoding.status -ne 'PASS' -or -not $encoding.non_ascii_stdout_stderr_preserved -or
        -not $encoding.invalid_utf8_replaced -or -not $encoding.saved_text_hash_differs_from_known_pipe_fixture){throw 'ENCODING_EVIDENCE_INCOMPLETE'}
    if((ReadEvidence ($label+'-patch-static-results.json')).status -ne 'PASS'){throw 'PATCH_STATIC_INCOMPLETE'}
}
foreach($name in @('entry-results.json','window-results.json','static-results.json','skill-results.json')){
    if((ReadEvidence $name).status -ne 'PASS'){throw 'BASELINE_SMOKE_OR_SKILL_INCOMPLETE'}
}
[pscustomobject]@{status='PASS';scope=$patch.scope;baseline_commit=$baseline;baseline_tests_per_engine=62;targeted_tests_per_engine=8;current_source_files=$current.Count;changed_source_files=$changed.Count;real_windows_mutation='NOT_TESTED';public_release=$false}|ConvertTo-Json
