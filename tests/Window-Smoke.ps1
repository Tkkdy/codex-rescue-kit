#requires -Version 5.1
param([string]$ResultDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $ResultDirectory){$ResultDirectory=Join-Path $repo ('out/window-'+[guid]::NewGuid().ToString('N'))}
Import-Module (Join-Path $repo 'kit\Rescue.Core.psm1') -Force -DisableNameChecking
$root=[IO.Path]::GetFullPath($ResultDirectory);$homePath=Join-Path $root 'profile\.codex'
[IO.Directory]::CreateDirectory($homePath)|Out-Null
function Json($p,$v){[IO.File]::WriteAllText($p,($v|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
Json (Join-Path $root 'fixture.json') @{schema='rescue-synthetic-v1'}
Json (Join-Path $root 'facts.json') @{installs=@();environment=@();tasks=@();processes=@();sandbox=@{error=$false;protected=$false}}
[IO.File]::WriteAllText((Join-Path $homePath 'config.toml'),'# synthetic stable config',[Text.UTF8Encoding]::new($false))
$c=New-RescueContext -CodexHome $homePath -OutputDirectory (Join-Path $root 'out') -FixtureRoot $root;$c.channel='C'
$s=New-VerificationSession $c
$p=Invoke-ToolProbe $c -SessionPath $s.session_path -Channel C -CanaryMode WorkspaceWrite
if($p.exit_code -ne 0){throw 'NATIVE_PROBE_FAILED'}
$watch=[Diagnostics.Stopwatch]::StartNew()
$r=Complete-Verification $c -SessionPath $s.session_path -EvidencePaths @($p.evidence_path) -StabilitySeconds 60
$watch.Stop()
$stable=@($r.checks|Where-Object id -eq 'config.stability')[0]
if($stable.status -ne 'PASS' -or $stable.data.seconds -ne 60 -or $watch.Elapsed.TotalSeconds -lt 60 -or $r.exit_code -ne 3){throw 'WINDOW_OR_CHANNEL_RESULT_INVALID'}
Json (Join-Path $root 'window-results.json') @{schema='rescue-window-smoke-v1';synthetic_only=$true;status='PASS';requested_seconds=60;elapsed_seconds=[math]::Round($watch.Elapsed.TotalSeconds,2);native_probe_count=$p.calls.Count;host_canary=$p.canary.status;overall_verification_exit=$r.exit_code;manual_origin_and_gui='NOT_TESTED'}
Write-Host 'PASS real 60-second window, native C probes, canary cleanup, A/B remain NOT_TESTED'