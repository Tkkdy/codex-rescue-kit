#requires -Version 5.1
param([string]$ResultDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $ResultDirectory){$ResultDirectory=Join-Path $repo ('out/smoke-'+[guid]::NewGuid().ToString('N'))}
$root=[IO.Path]::GetFullPath($ResultDirectory);$homePath=Join-Path $root 'profile\.codex';$output=Join-Path $root 'out'
[IO.Directory]::CreateDirectory($homePath)|Out-Null
function Json($Path,$Value){[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))}
Json (Join-Path $root 'fixture.json') @{schema='rescue-synthetic-v1'}
Json (Join-Path $root 'facts.json') @{installs=@();environment=@();tasks=@();processes=@();sandbox=@{error=$false;protected=$false}}
Json (Join-Path $root 'objects.json') @{objects=@()}
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
$info.Arguments='/d /c ""'+(Join-Path $repo 'rescue.cmd')+'" -FixtureRoot "'+$root+'" -CodexHome "'+$homePath+'" -OutputDirectory "'+$output+'" -StabilitySeconds 0"'
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
# Child-only pollution: parent and user environment remain unchanged.
$info.EnvironmentVariables['PATH']='';$info.EnvironmentVariables['PATHEXT']='.CPL'
$info.EnvironmentVariables['APPDATA']=Join-Path $root 'fake-appdata';$info.EnvironmentVariables['CODEX_HOME']=Join-Path $root 'wrong-home'
$p=New-Object Diagnostics.Process;$p.StartInfo=$info
try{
    $null=$p.Start();$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(30000)){$p.Kill();throw 'ENTRY_TIMEOUT'}
    $null=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()
    if($p.ExitCode -ne 3){throw 'ENTRY_DID_NOT_PROPAGATE_PARTIAL_EXIT'}
    $r=[IO.File]::ReadAllText((Join-Path $output 'report.json'))|ConvertFrom-Json
    if($r.schema -ne 'rescue-report-v1' -or -not $r.synthetic){throw 'ENTRY_REPORT_INVALID'}
    Json (Join-Path $root 'smoke-results.json') @{schema='rescue-entry-smoke-v1';synthetic_only=$true;status='PASS';exit_code_observed=$p.ExitCode;child_environment_polluted=$true}
    Write-Host 'PASS rescue.cmd default Diagnose, absolute Windows PowerShell, polluted child environment, real exit 3'
}finally{$p.Dispose()}