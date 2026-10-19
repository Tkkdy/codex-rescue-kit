#requires -Version 5.1
[CmdletBinding()]param([string]$GitExecutable='git.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$m=Get-Content -LiteralPath (Join-Path $repo 'evidence/v02/source-bindings.json') -Raw|ConvertFrom-Json
if($m.schema -ne 'rescue-v02-evidence-bindings-v1'){throw 'EVIDENCE_SCHEMA_INVALID'}
foreach($f in $m.files){
 if($f.path -notmatch '^(kit/|tests/|tools/|skills/|rescue\.cmd$|evidence/v02/)' -or $f.path -match '\.\.|:|^/|\\'){throw 'EVIDENCE_PATH_INVALID'}
 $p=Join-Path $repo $f.path
 if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.sha256){throw 'SOURCE_OR_EVIDENCE_DRIFT'}
}
foreach($name in @('pwsh-targeted-results.json','ps51-targeted-results.json','pwsh-gpt-patch-results.json','ps51-gpt-patch-results.json','pwsh-gpt-flow-composed-results.json','ps51-gpt-flow-composed-results.json')){
 $r=Get-Content -LiteralPath (Join-Path $repo ('evidence/v02/'+$name)) -Raw|ConvertFrom-Json
 if($r.failed -ne 0 -or $r.passed -lt 1){throw 'TARGETED_CHECKS_NOT_PASSING'}
}
[pscustomobject]@{status='PASS';state='REAL_REPAIR_REVIEW_READY';files=@($m.files).Count;limit='Source/evidence hash association, not live Windows/GUI acceptance'}|ConvertTo-Json
