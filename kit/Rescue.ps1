#requires -Version 5.1
[CmdletBinding()]param(
    [ValidateSet('Diagnose','Plan','Quarantine','Undo','Verify','ToolProbe','CheckBackup','Repair','Resume','Backup','StopWriter','RestoreAssets','AssetCandidates','SandboxGuide')][string]$Mode='Diagnose',
    [string]$CodexHome,[string]$OutputDirectory,[string]$FixtureRoot,
    [ValidateSet('UNATTESTED','B','C')][string]$Channel='UNATTESTED',
    [ValidateRange(0,300)][int]$StabilitySeconds=60,
    [string]$WriterScript,[string[]]$WriterScripts=@(),[switch]$CaptureStoppedConfiguration,[string]$PlanPath,[string]$ApprovePlanHash,
    [switch]$DryRun,[string]$Transaction,[switch]$ApproveUndo,
    [string]$SessionPath,[string[]]$EvidencePaths=@(),
    [ValidateSet('None','WorkspaceWrite','ReadOnly','BoundaryDenied')][string]$CanaryMode='None',
    [string]$BackupManifest,[string]$PayloadRoot,
    [string[]]$ConfigurationFiles=@(),[switch]$ConfirmTakeover,[int[]]$OfflineProcessIds=@(),
    [ValidateSet('Takeover','Tools','Assets','Login')][string]$Symptom='Takeover',
    [string]$ApproveRepairHash,[string[]]$ApproveForceProcess=@(),[switch]$OfficialStepComplete,
    [string]$RestoreManifest,[string]$RestorePayload,[string[]]$AssetPaths=@(),[switch]$ReviewedAssetSources,
    [string]$SandboxTarget,[ValidateSet('legacy-windows','mxc','unknown')][string]$SandboxBackend='unknown',
    [string]$SandboxErrorCode,[string]$ReviewedRulePath,[switch]$Interactive,[string[]]$ProjectRoots=@())
# Standalone live Quarantine/Undo cannot bypass the approved workflow, even if module is absent.
if($Mode -in @('Quarantine','Undo') -and -not $DryRun -and -not $FixtureRoot -and -not $ApproveRepairHash) {
    [pscustomobject]@{status='BLOCKED';code='VERSIONED_REPAIR_CAPABILITY_REQUIRED';exit_code=3}|ConvertTo-Json -Compress
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
        'Undo' {if($ApproveRepairHash){$result=Undo-Repair $context -PlanPath $PlanPath -ApproveRepairHash $ApproveRepairHash -ApproveUndo:$ApproveUndo -DryRun:$DryRun}else{$result=Undo-Quarantine $context -Transaction $Transaction -ApproveUndo:$ApproveUndo -DryRun:$DryRun}}
        'Verify' {if($SessionPath){$result=Complete-Verification $context -SessionPath $SessionPath -EvidencePaths $EvidencePaths -StabilitySeconds $StabilitySeconds}else{$result=New-VerificationSession $context}}
        'ToolProbe' {if($Channel -notin @('B','C')){throw 'DECLARE_ACTUAL_CHANNEL'};$result=Invoke-ToolProbe $context -SessionPath $SessionPath -Channel $Channel -CanaryMode $CanaryMode}
        {$_ -in @('Repair','Resume','Backup','StopWriter','RestoreAssets')} {
            if($Interactive -and -not $PlanPath){
                Write-Host '症状：Takeover 路由/守护接管；Tools 命令失败；Assets Skills 丢失；Login 登录异常。'
                $Symptom=Read-Host '输入症状代码（默认 Takeover）';if(-not $Symptom){$Symptom='Takeover'}
                $WriterScript=Read-Host '确证写入脚本的完整路径（无则留空）'
                $names=Read-Host '已确认冲突的文件（config.toml/auth.json，逗号分隔；无则留空）'
                if($names){$ConfigurationFiles=@($names.Split(',')|ForEach-Object {$_.Trim()});$ConfirmTakeover=((Read-Host '确认是非自愿接管而非合法第三方配置？输入 YES') -ceq 'YES')}
            }
            if(-not $PlanPath){
                $result=New-RepairPlan $context -WriterScript $WriterScript -WriterScripts $WriterScripts -CaptureStoppedConfiguration:$CaptureStoppedConfiguration -ConfigurationFiles $ConfigurationFiles -ConfirmTakeover:$ConfirmTakeover -OfflineProcessIds $OfflineProcessIds -Symptom $Symptom -RestoreManifest $RestoreManifest -RestorePayload $RestorePayload -AssetPaths $AssetPaths -ReviewedAssetSources:$ReviewedAssetSources -ProjectRoots $ProjectRoots
                Write-Host ('先审阅私有计划：'+$result.plan_path)
                Write-Host '计划含停止进程、启动入口、完整 home 备份及隔离/恢复范围。确认后以 Resume 和完整批准哈希继续。'
                if($Interactive -and -not $DryRun){
                    Write-Warning 'EXPERIMENTAL BETA: Real Windows Task/Run/Startup mutations and GUI/OAuth/model/tool/reboot acceptance are NOT_TESTED. Process memory cannot be undone. Verified backup and complete Undo materials remain mandatory.'
                    $result.summary|ConvertTo-Json -Depth 8|Write-Host
                    Write-Host ('批准哈希：'+$result.approval)
                    $typed=Read-Host '请先打开审阅完整计划；同意实施时输入完整批准哈希，否则回车退出'
                    if($typed -ceq $result.approval){
                        $PlanPath=$result.plan_path;$ApproveRepairHash=$typed
                        $force=@()
                        foreach($p in @($result.processes)){
                            Write-Host ('PID '+$p.pid+'：强停会丢失未保存内存，无法 Undo。独立批准码：'+$p.force_approval)
                            $answer=Read-Host '仅在接受该进程强停风险时输入此批准码；回车仅尝试正常关闭'
                            if($answer -ceq $p.force_approval){$force+=$answer}
                        }
                        $result=Invoke-Repair $context -PlanPath $PlanPath -ApproveRepairHash $ApproveRepairHash -ApproveForceProcess $force -StopAfter $(if($Mode -in @('Backup','StopWriter')){$Mode}else{'None'})
                    }
                }
            }else{
                if($StabilitySeconds -lt 60){throw 'REPAIR_STABILITY_MINIMUM_60_SECONDS'}
                $result=Invoke-Repair $context -PlanPath $PlanPath -ApproveRepairHash $ApproveRepairHash -ApproveForceProcess $ApproveForceProcess -OfficialStepComplete:$OfficialStepComplete -StabilitySeconds $StabilitySeconds -EvidencePaths $EvidencePaths -DryRun:$DryRun -StopAfter $(if($Mode -in @('Backup','StopWriter')){$Mode}else{'None'})
            }
        }
        'AssetCandidates' {$result=Get-AssetRecoveryCandidates $context -Manifest $RestoreManifest -Payload $RestorePayload}
        'SandboxGuide' {$result=New-SandboxGuide $context -Target $SandboxTarget -Backend $SandboxBackend -ErrorCode $SandboxErrorCode -ReviewedRulePath $ReviewedRulePath}
        'CheckBackup' {$result=Test-BackupManifest -Manifest $BackupManifest -PayloadRoot $PayloadRoot}
    }
    $result | ConvertTo-Json -Depth 30
    if($Mode -eq 'Diagnose'){Write-Host ('中文报告: '+(Join-Path $context.output 'report.zh-CN.md'))}
    if($result.PSObject.Properties['exit_code']){exit ([int]$result.exit_code)}
    if($result.PSObject.Properties['status']){exit (Get-RescueExitCode @($result))}
    exit 0
} catch {
    # Exception text can contain user paths, command lines or secret-bearing input.
    $safeCode='SAFE_STOP_REVIEW_PRIVATE_MATERIAL'
    if($_.Exception.Message -cmatch '^[A-Z][A-Z0-9_]*(?::[a-f0-9]{64})?$'){$safeCode=$_.Exception.Message}
    [pscustomobject]@{status='BLOCKED';code=$safeCode;exit_code=4}|ConvertTo-Json -Compress
    Write-Error 'Rescue stopped safely. Check paths, permissions, approved plan hash and journal integrity. Raw exception text is intentionally suppressed.' -ErrorAction Continue
    exit 4
}
