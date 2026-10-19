#requires -Version 5.1
[CmdletBinding()]param(
    [ValidateSet('Diagnose','Plan','Quarantine','Undo','Verify','ToolProbe','CheckBackup')][string]$Mode='Diagnose',
    [string]$CodexHome,[string]$OutputDirectory,[string]$FixtureRoot,
    [ValidateSet('UNATTESTED','B','C')][string]$Channel='UNATTESTED',
    [ValidateRange(0,300)][int]$StabilitySeconds=60,
    [string]$WriterScript,[string]$PlanPath,[string]$ApprovePlanHash,
    [switch]$DryRun,[string]$Transaction,[switch]$ApproveUndo,
    [string]$SessionPath,[string[]]$EvidencePaths=@(),
    [ValidateSet('None','WorkspaceWrite','ReadOnly','BoundaryDenied')][string]$CanaryMode='None',
    [string]$BackupManifest,[string]$PayloadRoot)
# Public preview safety: live Quarantine/Undo are deliberately unavailable.
# A synthetic FixtureRoot must pass New-RescueContext validation below.
if($Mode -in @('Quarantine','Undo') -and -not $DryRun -and [string]::IsNullOrWhiteSpace($FixtureRoot)) {
    [pscustomobject]@{status='BLOCKED';code='PREVIEW_REAL_MUTATION_DISABLED';exit_code=3} | ConvertTo-Json -Compress
    exit 3
}
$ErrorActionPreference='Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'Rescue.Core.psm1') -Force -DisableNameChecking
    $context=New-RescueContext -CodexHome $CodexHome -OutputDirectory $OutputDirectory -FixtureRoot $FixtureRoot
    $context.channel=$Channel
    switch($Mode) {
        'Diagnose' {$result=Invoke-RescueDiagnose $context -StabilitySeconds $StabilitySeconds}
        'Plan' {$result=New-QuarantinePlan $context -WriterScript $WriterScript}
        'Quarantine' {$result=Invoke-QuarantinePlan $context -PlanPath $PlanPath -ApprovePlanHash $ApprovePlanHash -DryRun:$DryRun}
        'Undo' {$result=Undo-Quarantine $context -Transaction $Transaction -ApproveUndo:$ApproveUndo -DryRun:$DryRun}
        'Verify' {if($SessionPath){$result=Complete-Verification $context -SessionPath $SessionPath -EvidencePaths $EvidencePaths -StabilitySeconds $StabilitySeconds}else{$result=New-VerificationSession $context}}
        'ToolProbe' {if($Channel -notin @('B','C')){throw 'DECLARE_ACTUAL_CHANNEL'};$result=Invoke-ToolProbe $context -SessionPath $SessionPath -Channel $Channel -CanaryMode $CanaryMode}
        'CheckBackup' {$result=Test-BackupManifest -Manifest $BackupManifest -PayloadRoot $PayloadRoot}
    }
    $result | ConvertTo-Json -Depth 30
    if($Mode -eq 'Diagnose'){Write-Host ('中文报告: '+(Join-Path $context.output 'report.zh-CN.md'))}
    if($result.PSObject.Properties['exit_code']){exit ([int]$result.exit_code)}
    if($result.PSObject.Properties['status']){exit (Get-RescueExitCode @($result))}
    exit 0
} catch {
    # Exception text can contain user paths, command lines or secret-bearing input.
    Write-Error 'Rescue stopped safely. Check paths, permissions, approved plan hash and journal integrity. Raw exception text is intentionally suppressed.' -ErrorAction Continue
    exit 4
}
