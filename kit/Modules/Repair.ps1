# Multi-writer plans keep every child plan/hash in the approved parent.
function Get-RepairStartupPlans($Plan) {
    if($Plan.PSObject.Properties['startup_plans']){return @($Plan.startup_plans)}
    if($Plan.quarantine_plan){$q=Read-RescueJson $Plan.quarantine_plan;return @([pscustomobject]@{path=$Plan.quarantine_plan;hash=$Plan.quarantine_hash;id=$q.id;writer=$Plan.writer;writer_hash=$Plan.writer_hash})}
    return @()
}
function Get-RepairWriters($Plan) {
    if($Plan.PSObject.Properties['writers']){return @($Plan.writers)}
    if($Plan.writer){return @([pscustomobject]@{path=$Plan.writer;sha256=$Plan.writer_hash})}
    return @()
}
function Assert-RepairStartupUndo($Context,$Plan,$History) {
    foreach($q in @(Get-RepairStartupPlans $Plan)){
        if((Get-ShaFile (Assert-PlainPath $q.path -MustExist)) -ne $q.hash){throw 'QUARANTINE_PLAN_DRIFT'}
        $child=Read-RescueJson $q.path
        $tx=Join-Path $Context.output ('transaction-'+$child.id)
        $required=@($History.records|Where-Object {($_.event -in @('STARTUP_PREPARE_PENDING','STARTUP_PREPARED')) -and $_.id -eq $child.id}).Count
        # Legacy sessions could disable entries without the parent prepare marker.
        $changed=@($child.targets|Where-Object {(Get-StateHash (Get-TargetState $Context $_)) -ne $_.before_hash}).Count
        if($required -or $changed -or (Test-Path -LiteralPath $tx)){
            if(-not (Test-Path -LiteralPath $tx -PathType Container)){throw 'REQUIRED_STARTUP_TRANSACTION_MISSING'}
            Assert-QuarantineUndoReady $Context $tx $child $q.hash
        }
    }
}
function Get-RepairEffectiveFiles($Plan,$State,$History) {
    if($Plan.PSObject.Properties['capture_stopped_configuration'] -and $Plan.capture_stopped_configuration){
        $records=@($History.records|Where-Object event -eq 'STOPPED_CONFIGURATION_SNAPSHOT')
        if($records.Count -ne 1 -or -not $State.PSObject.Properties['stopped_files'] -or (Get-StateHash @($State.stopped_files)) -ne $records[0].hash){throw 'STOPPED_CONFIGURATION_BINDING_INVALID'}
        $originalNames=@($Plan.files|ForEach-Object name|Sort-Object)
        $actualNames=@($State.stopped_files|ForEach-Object name|Sort-Object)
        if(($originalNames -join '|') -cne ($actualNames -join '|')){throw 'CONFIGURATION_SCOPE_REFUSED'}
        return @($State.stopped_files)
    }
    return @($Plan.files)
}
# Versioned, per-run capabilities; a plan is data until its exact hash is approved.
function Get-RepairUtcNow {return [DateTime]::UtcNow}
function Read-RepairPlan($Context,[string]$Path,[string]$Approval,[switch]$ForUndo) {
    Assert-Context $Context -Mutation
    $p=Assert-PlainPath $Path -MustExist
    if((Split-Path -Parent $p) -ine $Context.output -or (Split-Path -Leaf $p) -notmatch '^repair-plan-[a-f0-9]{32}\.json$'){throw 'REPAIR_PLAN_SCOPE_REFUSED'}
    if($Approval -notmatch '^[a-f0-9]{64}$' -or (Get-ShaFile $p) -cne $Approval){throw 'EXPLICIT_REPAIR_HASH_APPROVAL_REQUIRED'}
    Assert-PrivateDirectory $Context $Context.output
    $plan=Read-RescueJson $p
    if($plan.schema -ne 'rescue-repair-plan-v2' -or $plan.execution_policy -notin @('rescue-explicit-run-v2','rescue-explicit-run-v3') -or $plan.target_fingerprint -ne $Context.fingerprint -or [bool]$plan.synthetic -ne [bool]$Context.fixture -or $plan.id -notmatch '^[a-f0-9]{32}$' -or (Split-Path -Leaf $p) -ne ('repair-plan-'+$plan.id+'.json')){throw 'REPAIR_PLAN_CONTEXT_MISMATCH'}
    if(-not $ForUndo -and $plan.execution_policy -ne 'rescue-explicit-run-v3'){throw 'EXECUTION_ORDER_CHANGED_REPLAN_REQUIRED'}
    if(-not $ForUndo -and (Convert-RescueUtc $plan.expires_at) -lt (Get-RepairUtcNow)){throw 'REPAIR_PLAN_EXPIRED_REPLAN_REQUIRED'}
    foreach($w in @(Get-RepairWriters $plan)){if((Get-ShaFile (Assert-Writer $w.path)) -ne $w.sha256){throw 'WRITER_DRIFT'}}
    return $plan
}
function New-RepairPlan {
    [CmdletBinding()]param($Context,[string]$WriterScript,[string[]]$WriterScripts=@(),[switch]$CaptureStoppedConfiguration,[string[]]$ConfigurationFiles=@(),[switch]$ConfirmTakeover,[int[]]$OfflineProcessIds=@(),[ValidateSet('Takeover','Tools','Assets','Login')][string]$Symptom='Takeover',[string]$RestoreManifest,[string]$RestorePayload,[string[]]$AssetPaths=@(),[switch]$ReviewedAssetSources,[string[]]$ProjectRoots=@())
    Assert-Context $Context
    if($ConfigurationFiles.Count -and -not $ConfirmTakeover){throw 'EXPLICIT_CONFIGURATION_CONFLICT_CONFIRMATION_REQUIRED'}
    if([IO.Path]::GetPathRoot($Context.home) -ine [IO.Path]::GetPathRoot($Context.output)){throw 'REPAIR_REQUIRES_SAME_VOLUME_PRIVATE_RUN'}
    $id=[guid]::NewGuid().ToString('N');$writer='';$qh='';$qp='';$processes=@();$entries=@();$startupPlans=@();$writers=@();$targetKeys=@{}
    # Sensitive plan/backup/journal never enters the shareable Diagnose report.
    if(-not (Test-Path -LiteralPath $Context.output)){$null=New-PrivateDirectory $Context $Context.output}
    Assert-PrivateDirectory $Context $Context.output
    foreach($inputWriter in @(@($WriterScripts)+@($WriterScript)|Where-Object {$_}|Select-Object -Unique)){
        $w=Assert-Writer $inputWriter
        if($Context.fixture -and -not (Test-Within $w $Context.fixture_root)){throw 'FIXTURE_ESCAPE'}
        $q=New-QuarantinePlan $Context $w;$child=Read-RescueJson $q.plan_path
        if(@($child.targets).Count){$startupPlans+=[pscustomobject]@{path=$q.plan_path;hash=$q.approval;id=$child.id;writer=$w;writer_hash=(Get-ShaFile $w)}}
        $writers+=[pscustomobject]@{path=$w;sha256=(Get-ShaFile $w)}
        foreach($t in @($child.targets)){$key=$t.kind+'|'+$t.locator;if($targetKeys.ContainsKey($key)){throw 'DUPLICATE_STARTUP_TARGET'};$targetKeys[$key]=$true;$entries+=$t}
        foreach($p in @(Get-ActiveWriters $Context $w)){
            $processId=if($Context.fixture){[int]$p.pid}else{[int]$p.ProcessId}
            if(-not @($processes|Where-Object pid -eq $processId).Count){$processes+=Get-ProcessBinding (Get-RepairProcess $Context $processId)}
        }
    }
    if($writers.Count){$writer=$writers[0].path};if($startupPlans.Count){$qp=$startupPlans[0].path;$qh=$startupPlans[0].hash}
    if($CaptureStoppedConfiguration -and -not $writers.Count){throw 'STOPPED_CAPTURE_REQUIRES_CONFIRMED_WRITER'}
    foreach($processId in $OfflineProcessIds){
        $p=Get-RepairProcess $Context $processId;if(-not $p){throw 'EXPLICIT_OFFLINE_PROCESS_MISSING'}
        if(-not @($processes|Where-Object pid -eq $processId).Count){$processes+=Get-ProcessBinding $p}
    }
    foreach($p in $processes){$null=Assert-ProcessBinding $Context $p}
    $files=@();$seen=@{}
    foreach($name in $ConfigurationFiles){
        if($name -cnotin @('config.toml','auth.json') -or $seen.ContainsKey($name)){throw 'CONFIGURATION_SCOPE_REFUSED'};$seen[$name]=$true
        $path=Assert-PlainPath (Join-Path $Context.home $name) -MustExist
        $fields=@()
        if($name -eq 'config.toml'){
            # Display field names only. No TOML rewrite and no value, URL or credential disclosure.
            foreach($line in [IO.File]::ReadAllLines($path)){if($line -match '^\s*(model_provider|forced_login_method|base_url|wire_api|requires_openai_auth)\s*='){$fields+=$Matches[1]}}
        }
        $files+=[pscustomobject]@{name=$name;before=(Get-Stamp $path);sha256=(Get-ShaFile $path);fields=@($fields|Select-Object -Unique);desired='ABSENT_ALLOW_OFFICIAL_REGENERATION';diff='WHOLE_FILE_PRIVATE_ISOLATION_BY_EXPLICIT_CHOICE_NO_VALUES_EXPORTED'}
    }
    $projects=@()
    foreach($root in $ProjectRoots){
        $project=Assert-PlainPath $root -MustExist
        if((Test-Within $Context.output $project) -or (Test-Within $project $Context.output) -or (Test-Within $Context.home $project) -or (Test-Within $project $Context.home)){throw 'PROJECT_SCOPE_OVERLAP_REFUSED'}
        if($Context.fixture -and -not (Test-Within $project $Context.fixture_root)){throw 'FIXTURE_ESCAPE'}
        $inventory=Get-BackupInventory $project
        $projects+=[pscustomobject]@{root=$project;files=@($inventory.files).Count;inventory_hash=(Get-StateHash $inventory);backup='NOT_INCLUDED_NO_REPAIR_WRITES_ALLOWED'}
    }
    $assets=@(Get-RestoreSelections $Context $RestoreManifest $RestorePayload $AssetPaths -ReviewedSources:$ReviewedAssetSources)
    $boot=if($Context.fixture){'SYNTHETIC_BOOT'}else{(Convert-RescueUtc (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime).ToString('o')}
    $plan=[ordered]@{initial_boot=$boot;schema='rescue-repair-plan-v2';execution_policy='rescue-explicit-run-v3';id=$id;created_at=[DateTime]::UtcNow.ToString('o');expires_at=[DateTime]::UtcNow.AddDays(7).ToString('o');target_fingerprint=$Context.fingerprint;synthetic=[bool]$Context.fixture;home=$Context.home;identity=$Context.identity;symptom=$Symptom;writer=$writer;writer_hash=$(if($writer){Get-ShaFile $writer}else{''});writers=$writers;startup_plans=$startupPlans;capture_stopped_configuration=[bool]$CaptureStoppedConfiguration;startup_sequence='SNAPSHOT_ALL_DISABLE_ALL_STOP_EXACT_PROCESSES_BACKUP_ISOLATE';experimental_warning='EXPERIMENTAL BETA: Real Windows Task/Run/Startup mutations and GUI/OAuth/model/tool/reboot acceptance are NOT_TESTED. Process memory cannot be undone. Verified backup and complete Undo materials remain mandatory.';unresolved_startup='NOT_ANALYZED_COMPLEX_COMMANDS_AND_UNCONFIRMED_SOURCES_REQUIRE_MANUAL_REVIEW';scope_blockers=@($projects|ForEach-Object {'EXTERNAL_PROJECT_BACKUP_NOT_VERIFIED'});unbacked_projects=@($projects|ForEach-Object root);quarantine_plan=$qp;quarantine_hash=$qh;startup_targets=$entries;processes=@($processes);files=$files;assets=$assets;protected_projects=$projects;observed_listeners=@(Get-RepairListeners $Context $processes);backup_scope='ENTIRE_EXPLICIT_HOME_INCLUDING_AUTH_HISTORY_DB_WAL_SKILLS_RULES_PLUGINS_UI_NO_EXTERNAL_PROJECTS';irreversible=@('Process memory/lifetime cannot be restored','Official login and Store changes are manual and not undone');manual_steps=@('Close all Codex clients before backup','Official login/Store UI by user','GUI A and target-tool B plus host C acceptance','Admin Sandbox only after precise ACL review');undo='Never overwrite newly generated login/config or changed assets; stop on conflict'}
    $path=Join-Path $Context.output ('repair-plan-'+$id+'.json');Write-DurableJson $path $plan
    return [pscustomobject]@{status=$(if($projects.Count){'BLOCKED'}else{'NOT_TESTED'});state=$(if($projects.Count){'PLAN_SCOPE_BLOCKED'}else{'AWAITING_EXACT_PLAN_APPROVAL'});plan_path=$path;approval=(Get-ShaFile $path);processes=@($processes|ForEach-Object {@{pid=$_.pid;force_approval=(Get-StateHash $_)}});summary=@{files=@($files|ForEach-Object {$_.name});startup_count=$entries.Count;scope_blockers=$plan.scope_blockers;unbacked_projects=$plan.unbacked_projects;unresolved_startup=$plan.unresolved_startup;asset_count=$assets.Count;backup=$plan.backup_scope;experimental_warning=$plan.experimental_warning;manual=$plan.manual_steps};exit_code=3}
}
function Assert-RepairCapability($Context,[string]$Operation) {
    if(-not $Context.PSObject.Properties['repair_capability']){throw 'VERSIONED_REPAIR_CAPABILITY_REQUIRED'}
    $c=$Context.repair_capability
    $p=Read-RepairPlan $Context $c.path $c.approval -ForUndo:($Operation -eq 'Undo')
    $run=Join-Path $Context.output ('repair-'+$p.id)
    $state=Read-RescueJson (Join-Path $run 'state.json')
    $history=Get-JournalRecords (Join-Path $run 'journal.jsonl')
    if($history.count -lt 1 -or $history.records[0].plan_hash -ne $c.approval -or $state.plan_hash -ne $c.approval){throw 'REPAIR_SESSION_BINDING_INVALID'}
    if($Operation -eq 'Quarantine'){
        if($state.phase -ne 'PLANNED'){throw 'REPAIR_PHASE_INVALID'}
    }elseif($state.backup){$null=Assert-RepairBackup $Context $p $state}
    elseif(@($history.records|Where-Object event -eq 'FILE_PENDING').Count){throw 'SAME_RUN_VERIFIED_BACKUP_REQUIRED'}
    return $p
}
function Write-RepairState([string]$Run,$State) {Write-DurableJson (Join-Path $Run 'state.json') $State -Replace}
function Get-RepairResult($State,[string]$Run,[string]$Code='') {
    return [pscustomobject]@{status=$(if($State.phase -eq 'UNDONE'){'PASS'}elseif($State.phase -eq 'UNDO_PARTIAL_CONFLICT'){'PARTIAL'}else{'NOT_TESTED'});state=$(if($State.phase -eq 'UNDONE'){'ROLLBACK_AVAILABLE'}elseif($State.phase -eq 'OBSERVED'){'PARTIAL_RECOVERY'}else{'BLOCKED'});phase=$State.phase;code=$Code;run=$Run;backup=$State.backup;verification=$State.verification;undo='AVAILABLE_WITH_DRIFT_CHECKS_PROCESS_MEMORY_NOT_REVERSIBLE';synthetic=$State.synthetic;exit_code=$(if($State.phase -eq 'UNDONE'){0}else{3})}
}
function Invoke-RepairFiles($Context,$Plan,[string]$Run,[string]$Journal,[int]$FixtureInterruptAfter=0) {
    $index=0
    foreach($file in @($Plan.files)){
        if($file.name -cnotin @('config.toml','auth.json')){throw 'CONFIGURATION_SCOPE_REFUSED'}
        $src=Assert-PlainPath (Join-Path $Context.home $file.name)
        $held=Assert-PlainPath (Join-Path $Run ('isolated-'+$file.name))
        $records=(Get-JournalRecords $Journal).records
        $pending=@($records|Where-Object {$_.event -eq 'FILE_PENDING' -and $_.name -eq $file.name})
        if(Test-Path -LiteralPath $held){
            if($pending.Count -ne 1 -or (Get-ShaFile $held) -ne $file.sha256){throw 'ISOLATION_MATERIAL_INVALID'}
            # A newly generated official file is never moved or overwritten on Resume.
            continue
        }
        if($pending.Count -gt 1){throw 'FILE_JOURNAL_AMBIGUOUS'}
        if((Get-Stamp $src) -ne $file.before){throw 'CONFIGURATION_DRIFT'}
        if(-not $pending.Count){Add-Journal $Journal @{event='FILE_PENDING';name=$file.name;before=$file.before;sha256=$file.sha256;desired='ABSENT'}}
        [IO.File]::Move($src,$held)
        $index++;if($FixtureInterruptAfter -gt 0 -and $index -eq $FixtureInterruptAfter){throw 'SYNTHETIC_FILE_INTERRUPTION'}
        if((Test-Path -LiteralPath $src) -or (Get-ShaFile $held) -ne $file.sha256){throw 'ISOLATION_POSTCONDITION_FAILED'}
        Add-Journal $Journal @{event='FILE_APPLIED';name=$file.name;after='ABSENT'}
    }
}
function Invoke-Repair {
    [CmdletBinding()]param($Context,[string]$PlanPath,[string]$ApproveRepairHash,[string[]]$ApproveForceProcess=@(),[switch]$OfficialStepComplete,[ValidateRange(60,300)][int]$StabilitySeconds=60,[string[]]$EvidencePaths=@(),[int]$FixtureInterruptAfterFile=0,[long]$FixtureAvailableBytes=-1,[int]$FixtureInterruptBackup=0,[ValidateSet('None','StopWriter','Backup')][string]$StopAfter='None',[switch]$DryRun)
    $plan=Read-RepairPlan $Context $PlanPath $ApproveRepairHash
    if($DryRun){return [pscustomobject]@{status='NOT_TESTED';state='DIAGNOSED_ONLY';code='DRY_RUN_NO_MUTATIONS';exit_code=3}}
    Write-Warning 'EXPERIMENTAL BETA: Real Windows Task/Run/Startup mutations and GUI/OAuth/model/tool/reboot acceptance are NOT_TESTED. Process memory cannot be undone. Verified backup and complete Undo materials remain mandatory.'
    if($plan.PSObject.Properties['scope_blockers'] -and @($plan.scope_blockers).Count){throw 'PROJECT_BACKUP_NOT_VERIFIED_PLAN_BLOCKED'}
    if(-not $Context.fixture -and ($FixtureInterruptAfterFile -or $FixtureAvailableBytes -ne -1 -or $FixtureInterruptBackup)){throw 'TEST_HOOK_FIXTURE_ONLY'}
    $run=Join-Path $Context.output ('repair-'+$plan.id)
    if(-not (Test-Path -LiteralPath $run)){
        $null=New-PrivateDirectory $Context $run
        Write-DurableJson (Join-Path $run 'state.json') ([ordered]@{schema='rescue-repair-state-v2';plan_hash=$ApproveRepairHash;synthetic=[bool]$Context.fixture;phase='PLANNED';backup=$null;startup_transaction='';verification=$null;stability=$null;last_error=''})
        Add-Journal (Join-Path $run 'journal.jsonl') @{event='BEGIN';plan_hash=$ApproveRepairHash;context=$Context.fingerprint;undo='DRIFT_CHECKED_NO_PROCESS_RESTART'}
    }
    $lock=[IO.FileStream]::new((Join-Path $Context.output 'repair.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $state=Read-RescueJson (Join-Path $run 'state.json');$journal=Join-Path $run 'journal.jsonl';$h=Get-JournalRecords $journal
        if($state.plan_hash -ne $ApproveRepairHash -or $h.records[0].plan_hash -ne $ApproveRepairHash){throw 'REPAIR_SESSION_BINDING_INVALID'}
        $Context|Add-Member -Force NoteProperty repair_capability ([pscustomobject]@{path=$PlanPath;approval=$ApproveRepairHash})
        if($state.phase -eq 'UNDONE'){return Get-RepairResult $state $run 'ALREADY_UNDONE'}
        if($state.phase -eq 'PLANNED'){
            # Validate the entire scope before the first startup change.
            foreach($p in $plan.processes){$null=Assert-ProcessBinding $Context $p}
            $qs=@(Get-RepairStartupPlans $plan)
            foreach($q in $qs){
                $tx=Join-Path $Context.output ('transaction-'+$q.id)
                if(-not (Test-Path -LiteralPath $tx)){
                    $null=Read-ValidatedPlan $Context $q.path $q.hash
                }else{
                    Assert-QuarantineUndoReady $Context $tx (Read-RescueJson $q.path) $q.hash
                }
            }
            # Persist all before-images before disabling even the first entry.
            foreach($q in $qs){
                $tx=Join-Path $Context.output ('transaction-'+$q.id)
                if(-not (Test-Path -LiteralPath $tx)){
                    Add-Journal $journal @{event='STARTUP_PREPARE_PENDING';id=$q.id;hash=$q.hash}
                    $prepared=Invoke-QuarantinePlan $Context $q.path $q.hash -PrepareOnly
                    if($prepared.exit_code -ne 0){throw 'STARTUP_PREPARATION_FAILED_USE_UNDO'}
                    Add-Journal $journal @{event='STARTUP_PREPARED';id=$q.id;hash=$q.hash}
                }
            }
            foreach($q in $qs){
                $child=Read-RescueJson $q.path
                if(-not @($child.targets).Count){continue}
                $tx=Join-Path $Context.output ('transaction-'+$q.id)
                $jh=Get-JournalRecords (Join-Path $tx 'journal.jsonl')
                if(-not @($jh.records|Where-Object event -eq 'COMMITTED').Count){
                    if($jh.count -ne 1){throw 'STARTUP_INTERRUPTED_USE_REPAIR_UNDO'}
                    $result=Invoke-QuarantinePlan $Context $q.path $q.hash -Prepared
                    if($result.exit_code -ne 0){throw 'STARTUP_QUARANTINE_BLOCKED_OR_INTERRUPTED'}
                }
            }
            $state.phase='STARTUP_DISABLED';Write-RepairState $run $state
        }
        if($state.phase -ne 'PLANNED'){Assert-RepairStartupUndo $Context $plan (Get-JournalRecords $journal)}
        if($state.phase -eq 'STARTUP_DISABLED'){
            foreach($target in $plan.startup_targets){if((Get-StateHash (Get-TargetState $Context $target)) -ne (Get-StateHash (Get-DesiredState $target.before))){throw 'STARTUP_ENTRY_REAPPEARED'}}
            Stop-RepairWriters $Context $plan $journal $ApproveForceProcess
            if($plan.PSObject.Properties['capture_stopped_configuration'] -and $plan.capture_stopped_configuration){
                $captured=@(foreach($file in $plan.files){
                    $copy=$file|ConvertTo-Json -Depth 8|ConvertFrom-Json
                    $src=Assert-PlainPath (Join-Path $Context.home $file.name) -MustExist
                    $copy.before=Get-Stamp $src;$copy.sha256=Get-ShaFile $src;$copy
                })
                $state|Add-Member -Force NoteProperty stopped_files $captured
                Add-Journal $journal @{event='STOPPED_CONFIGURATION_SNAPSHOT';hash=(Get-StateHash @($captured));policy='EXPLICIT_APPROVED_POST_STOP_CAPTURE_ONLY_SELECTED_NAMES'}
            }
            $state.phase='STOPPED';Write-RepairState $run $state
        }
        if($state.PSObject.Properties['stopped_files'] -or ($plan.PSObject.Properties['capture_stopped_configuration'] -and $plan.capture_stopped_configuration -and $state.phase -notin @('PLANNED','STARTUP_DISABLED'))){$plan.files=@(Get-RepairEffectiveFiles $plan $state (Get-JournalRecords $journal))}
        if($StopAfter -eq 'StopWriter'){return Get-RepairResult $state $run 'STOPPED_ONLY_BACKUP_AND_REPAIR_PENDING'}
        if($state.phase -eq 'STOPPED'){
            # Failed/partial backups are retained. Resume always creates a fresh unique snapshot.
            $state.backup=New-RepairBackup $Context $plan $run -FixtureAvailableBytes $FixtureAvailableBytes -FixtureInterruptAfter $FixtureInterruptBackup
            $state.phase='BACKED_UP';Write-RepairState $run $state
            Add-Journal $journal @{event='BACKUP_VERIFIED';manifest_hash=$state.backup.manifest_hash;restore_proof='NOT_TESTED'}
        }
        if($StopAfter -eq 'Backup'){return Get-RepairResult $state $run 'BACKUP_ONLY_REPAIR_PENDING'}
        $null=Assert-RepairBackup $Context $plan $state
        if($state.phase -eq 'BACKED_UP'){
            Assert-NoRepairProcesses $Context $plan
            $state.phase='ENTRIES_ISOLATED';Write-RepairState $run $state
        }
        if($state.phase -eq 'ENTRIES_ISOLATED'){
            Assert-NoRepairProcesses $Context $plan
            foreach($target in $plan.startup_targets){if((Get-StateHash (Get-TargetState $Context $target)) -ne (Get-StateHash (Get-DesiredState $target.before))){throw 'STARTUP_ENTRY_REAPPEARED'}}
            foreach($file in $plan.files){
                $m=Assert-RepairBackup $Context $plan $state
                if(@($m.files|Where-Object {$_.path -eq $file.name -and $_.sha256 -eq $file.sha256}).Count -ne 1){throw 'CONFIGURATION_NOT_IN_BACKUP'}
            }
            Invoke-RepairFiles $Context $plan $run $journal -FixtureInterruptAfter $FixtureInterruptAfterFile
            Restore-RepairAssets $Context $plan $run $journal
            $state.phase='AWAITING_OFFICIAL';Write-RepairState $run $state
            Write-DurableJson (Join-Path $run 'official-step.json') @{schema='rescue-manual-card-v2';run_id=$plan.id;steps=@('Open the official Codex app/CLI yourself and select ChatGPT login','Use official Store repair only if install is broken; do not uninstall with data removal','Do not paste tokens into Rescue','Close Codex clients after login for the host check, then Resume -OfficialStepComplete','GUI: read a representative old session; send a new official conversation; execute terminal commands in a NEW conversation in the ORIGINAL project','Old-session continuation is informational only, never a recovery failure by itself','Reboot manually, then repeat host stability/entry checks; missing reboot evidence stays NOT_TESTED');history='Preserved; old custom sessions and long-session 400 are not repaired by provider rewriting';undo='New config/auth will block Undo, never overwritten'}
        }
        if($state.phase -eq 'AWAITING_OFFICIAL' -and -not $OfficialStepComplete){return Get-RepairResult $state $run 'MANUAL_OFFICIAL_LOGIN_OR_STORE_STEP_REQUIRED'}
        if($state.phase -in @('AWAITING_OFFICIAL','OBSERVED') -and $OfficialStepComplete){
            Assert-NoRepairProcesses $Context $plan
            if(@(Get-RepairWriters $plan).Count){
                foreach($target in $plan.startup_targets){if((Get-StateHash (Get-TargetState $Context $target)) -ne (Get-StateHash (Get-DesiredState $target.before))){throw 'STARTUP_ENTRY_REAPPEARED'}}
            }
            $stability=Get-ConfigStability $Context $StabilitySeconds
            $state.stability=$stability;Write-RepairState $run $state
            if($stability.status -ne 'PASS'){throw 'CONFIGURATION_NOT_STABLE'}
            if(-not $state.verification){$state.verification=New-VerificationSession $Context}
            $state.phase='OBSERVED';Write-RepairState $run $state
            $bootNow=if($Context.fixture){'SYNTHETIC_BOOT'}else{(Convert-RescueUtc (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).ToString('o')}
            Write-DurableJson (Join-Path $run ('acceptance-'+[guid]::NewGuid().ToString('N')+'.json')) @{
                schema='rescue-core-acceptance-v2';run_id=$plan.id;plan_hash=$ApproveRepairHash;verification_session=$state.verification.id;synthetic=$Context.fixture;
                generated_at=[DateTime]::UtcNow.ToString('o');initial_boot=$plan.initial_boot;observed_boot=$bootNow;boot_changed=($bootNow -ne $plan.initial_boot);
                required=@(
                    @{id='history.read';status='NOT_TESTED';instruction='Manually open and read representative old conversation in official GUI; retain redacted evidence reference'},
                    @{id='assets.projects';status='NOT_TESTED';instruction='Check private backup manifest, exclusions, sessions/Skills/Rules and explicit projects; hash presence alone does not prove readability'},
                    @{id='official.new-model';status='NOT_TESTED';instruction='Complete official login personally and SEND a new official conversation; retain outcome/time'},
                    @{id='original-project.new-tool';status='NOT_TESTED';instruction='In a NEW conversation in ORIGINAL project run three independent tool commands plus controlled canary; attach actual exit codes and transcript/session origin'},
                    @{id='takeover.reboot';status='NOT_TESTED';instruction='Manually reboot, cold-start official app, Resume and repeat >=60s stability, entries and process checks; same PID/window close is insufficient'}
                );informational=@{old_session_continue='NOT_A_FAILURE_GATE_COMPATIBILITY_LIMIT_ACCEPTED'};
                conclusion='PARTIAL_RECOVERY_UNTIL_EXTERNAL_A_B_C_EVIDENCE_REVIEW';policy='This file is a checklist, never proof. User/reviewer must correlate actual GUI/tool/host transcripts; editing JSON cannot auto-promote recovery.'
            }
            $checks=@{projects=@($plan.protected_projects|ForEach-Object {@{root_fingerprint=(Get-ShaText $_.root);baseline_files=$_.files;unchanged=((Get-StateHash (Get-BackupInventory $_.root)) -eq $_.inventory_hash);backup=$_.backup;limit='HASH_OBSERVATION_ONLY_NOT_GUI_READABILITY_PROOF'}});configuration=$stability;assets=@($plan.assets|ForEach-Object {@{path_fingerprint=(Get-ShaText $_.relative);discovered=(Test-Path -LiteralPath $_.destination);load='NOT_TESTED';callable='NOT_TESTED'}});A='NOT_TESTED_MANUAL_GUI';B='NOT_TESTED_ACTUAL_TARGET_TOOL_REQUIRED';C_origin='NOT_TESTED_EXTERNAL_HOST_CORRELATION_REQUIRED';ports=@{before=@($plan.observed_listeners);after_for_original_pids=@(Get-RepairListeners $Context $plan.processes);scope='ORIGINAL_BOUND_PIDS_ONLY_NO_PORT_BASED_ATTRIBUTION'};network='NOT_TESTED';model='NOT_TESTED';history=@{visible='NOT_TESTED';open='NOT_TESTED';continue='INFORMATIONAL_ONLY_NOT_A_FAILURE_GATE'}}
            if($EvidencePaths.Count){$checks.tool_observations=Complete-Verification $Context -SessionPath $state.verification.session_path -EvidencePaths $EvidencePaths -StabilitySeconds 0}
            Write-DurableJson (Join-Path $run ('observations-'+[guid]::NewGuid().ToString('N')+'.json')) $checks
        }
        return Get-RepairResult $state $run 'OBSERVATIONS_ONLY_A_B_C_SEPARATE'
    }catch{
        if($state){$state.last_error='SAFE_STOP_REVIEW_PRIVATE_JOURNAL';Write-RepairState $run $state}
        Add-Journal (Join-Path $run 'journal.jsonl') @{event='INTERRUPTED';code='SAFE_STOP_REVIEW_PRIVATE_MATERIAL'}
        throw
    }finally{if($Context.PSObject.Properties['repair_capability']){$Context.PSObject.Properties.Remove('repair_capability')};$lock.Dispose()}
}
function Undo-Repair {
    [CmdletBinding()]param($Context,[string]$PlanPath,[string]$ApproveRepairHash,[switch]$ApproveUndo,[switch]$DryRun)
    if(-not $ApproveUndo){throw 'EXPLICIT_REPAIR_UNDO_APPROVAL_REQUIRED'}
    $plan=Read-RepairPlan $Context $PlanPath $ApproveRepairHash -ForUndo
    if($DryRun){return [pscustomobject]@{status='NOT_TESTED';state='DIAGNOSED_ONLY';code='DRY_RUN_NO_MUTATIONS';exit_code=3}}
    Write-Warning 'EXPERIMENTAL BETA: Real Windows Task/Run/Startup mutations and GUI/OAuth/model/tool/reboot acceptance are NOT_TESTED. Process memory cannot be undone. Verified backup and complete Undo materials remain mandatory.'
    $run=Join-Path $Context.output ('repair-'+$plan.id);$journal=Join-Path $run 'journal.jsonl';$undoStarted=$false
    $lock=[IO.FileStream]::new((Join-Path $Context.output 'repair.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $state=Read-RescueJson (Join-Path $run 'state.json');$history=Get-JournalRecords $journal
        if($state.plan_hash -ne $ApproveRepairHash -or $history.records[0].plan_hash -ne $ApproveRepairHash){throw 'REPAIR_SESSION_BINDING_INVALID'}
        if($state.phase -eq 'UNDONE'){return Get-RepairResult $state $run 'ALREADY_UNDONE'}
        Assert-NoRepairProcesses $Context $plan
        $Context|Add-Member -Force NoteProperty repair_capability ([pscustomobject]@{path=$PlanPath;approval=$ApproveRepairHash})
        if($state.backup){$null=Assert-RepairBackup $Context $plan $state}
        Assert-RepairStartupUndo $Context $plan $history
        if($state.PSObject.Properties['stopped_files'] -or ($plan.PSObject.Properties['capture_stopped_configuration'] -and $plan.capture_stopped_configuration -and ($state.backup -or @($history.records|Where-Object {$_.event -in @('STOPPED_CONFIGURATION_SNAPSHOT','FILE_PENDING')}).Count))){$plan.files=@(Get-RepairEffectiveFiles $plan $state $history)}
        # Preflight ALL startup and file conflicts before restoring anything.
        foreach($file in $plan.files){
            $src=Assert-PlainPath (Join-Path $Context.home $file.name);$held=Assert-PlainPath (Join-Path $run ('isolated-'+$file.name))
            if(Test-Path -LiteralPath $held){
                if((Get-ShaFile $held) -ne $file.sha256){throw 'ISOLATED_FILE_DRIFT'}
                if(Test-Path -LiteralPath $src){throw 'UNDO_NEW_CONFIGURATION_CONFLICT'}
            }elseif(@($history.records|Where-Object {$_.event -eq 'FILE_PENDING' -and $_.name -eq $file.name}).Count){
                if((Get-Stamp $src) -ne $file.before){throw 'UNDO_ORIGINAL_FILE_MISSING_OR_CHANGED'}
            }
        }
        foreach($a in $plan.assets){
            $null=Assert-PlainPath $a.destination
            if(Test-Path -LiteralPath $a.destination){
                if(-not @($history.records|Where-Object {$_.event -eq 'ASSET_PENDING' -and $_.relative -eq $a.relative}).Count -or (Get-ShaFile $a.destination) -ne $a.sha256){throw 'UNDO_ASSET_CONFLICT'}
            }
        }
        foreach($a in $plan.assets){
            if(Test-Path -LiteralPath $a.destination){
                $held=Join-Path $run ('undo-asset-'+(Get-ShaText $a.relative))
                Add-Journal $journal @{event='ASSET_UNDO_PENDING';relative=$a.relative;desired='ABSENT_KEEP_PRIVATE_COPY'}
                $undoStarted=$true;[IO.File]::Move($a.destination,$held)
                Add-Journal $journal @{event='ASSET_UNDONE';relative=$a.relative}
            }
        }
        foreach($file in $plan.files){
            $held=Assert-PlainPath (Join-Path $run ('isolated-'+$file.name));$src=Assert-PlainPath (Join-Path $Context.home $file.name)
            if(Test-Path -LiteralPath $held){
                if(Test-Path -LiteralPath $src){throw 'UNDO_NEW_CONFIGURATION_CONFLICT'}
                Add-Journal $journal @{event='FILE_UNDO_PENDING';name=$file.name;sha256=$file.sha256}
                $undoStarted=$true;[IO.File]::Move($held,$src)
                if((Get-ShaFile $src) -ne $file.sha256){throw 'UNDO_FILE_POSTCONDITION_FAILED'}
                Add-Journal $journal @{event='FILE_UNDONE';name=$file.name}
            }
        }
        foreach($q in @(Get-RepairStartupPlans $plan)){
            $tx=Join-Path $Context.output ('transaction-'+$q.id)
            if(Test-Path -LiteralPath $tx){
                $undoStarted=$true;$u=Undo-Quarantine $Context $tx -ApproveUndo
                if($u.exit_code -ne 0){$state.phase='UNDO_PARTIAL_CONFLICT';Write-RepairState $run $state;throw 'STARTUP_UNDO_PARTIAL_CONFLICT_INSPECT_ITEM_RESULTS'}
            }
        }
        $state.phase='UNDONE';Write-RepairState $run $state
        Add-Journal $journal @{event='REPAIR_UNDONE';process_memory='NOT_REVERSIBLE';manual_login='NOT_UNDONE'}
        return Get-RepairResult $state $run 'FILES_AND_ENTRIES_RESTORED_NO_PROCESS_RESTART'
    }catch{
        if($undoStarted){$state.phase='UNDO_PARTIAL_CONFLICT';Write-RepairState $run $state;Add-Journal $journal @{event='REPAIR_UNDO_PARTIAL_CONFLICT';code='INSPECT_PRIVATE_MATERIAL'}}
        throw
    }finally{if($Context.PSObject.Properties['repair_capability']){$Context.PSObject.Properties.Remove('repair_capability')};$lock.Dispose()}
}
