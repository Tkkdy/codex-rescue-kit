Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:KitRoot = $PSScriptRoot
. (Join-Path $PSScriptRoot 'Private\Common.ps1')
. (Join-Path $PSScriptRoot 'Private\Adapters.ps1')
. (Join-Path $PSScriptRoot 'Modules\Diagnose.ps1')
. (Join-Path $PSScriptRoot 'Modules\Quarantine.ps1')
. (Join-Path $PSScriptRoot 'Modules\Verify.ps1')
. (Join-Path $PSScriptRoot 'Modules\Backup.ps1')
. (Join-Path $PSScriptRoot 'Modules\StopWriter.ps1')
. (Join-Path $PSScriptRoot 'Modules\RestoreAssets.ps1')
. (Join-Path $PSScriptRoot 'Modules\SandboxGuide.ps1')
. (Join-Path $PSScriptRoot 'Modules\Repair.ps1')
Export-ModuleMember -Function New-RescueContext,Invoke-RescueDiagnose,New-QuarantinePlan,Invoke-QuarantinePlan,Undo-Quarantine,New-VerificationSession,Invoke-ToolProbe,Complete-Verification,Test-BackupManifest,Get-RescueExitCode,New-RepairPlan,Invoke-Repair,Undo-Repair,New-SandboxGuide,Get-AssetRecoveryCandidates
