# Only synthetic files and local function mocks; never call real Task Scheduler.
function Test-TaskAdapterScenario($Fixture,[string]$State,[bool]$Enabled,[string]$Scenario) {
    & $module {
        param($ctx,$writer,$state,$enabled,$scenario)
        $script:taskConfigured=$enabled;$script:taskDynamic=$state;$script:taskWrites=0;$script:taskJournal=$null
        $script:originalTaskReader=(Get-Command Get-TargetState).ScriptBlock
        function Get-ScheduledTask {
            param($TaskPath,$TaskName,$ErrorAction)
            [pscustomobject]@{State=$script:taskDynamic;Settings=[pscustomobject]@{Enabled=$script:taskConfigured}}
        }
        function Export-ScheduledTask {
            param($TaskPath,$TaskName,$ErrorAction)
            '<Task><Settings><Enabled>'+([string]$script:taskConfigured).ToLowerInvariant()+'</Enabled></Settings><Triggers><Trigger><Enabled>true</Enabled></Trigger></Triggers><Actions><Exec><Command>synthetic</Command></Exec></Actions></Task>'
        }
        function Get-WriterCandidates {param($Context,$Writer) [pscustomobject]@{kind='task';locator='\Synthetic\Guard';writer=$Writer}}
        function Get-TargetState {
            param($Context,$Target)
            if(-not $Context.fixture -or $Target.kind -ne 'task'){throw 'TEST_SCOPE_VIOLATION'}
            $read=$Context.PSObject.Copy();$read.fixture=$false
            & $script:originalTaskReader $read $Target
        }
        function Set-TargetState {
            param($Context,$Target,$State,$HeldPath)
            if(-not $Context.fixture -or $Target.kind -ne 'task'){throw 'TEST_SCOPE_VIOLATION'}
            $records=(Get-JournalRecords $script:taskJournal).records
            if($records[-1].event -notin @('PENDING','UNDO_PENDING') -or
                -not (Test-Path (Join-Path (Split-Path $script:taskJournal) 'undo.json'))){throw 'MUTATION_BEFORE_UNDO_AND_JOURNAL'}
            $script:taskConfigured=[bool]$State.enabled;$script:taskWrites++
        }
        $plan=New-QuarantinePlan $ctx -WriterScript $writer
        $data=Read-RescueJson $plan.plan_path
        if($scenario -eq 'disabled'){
            if($plan.target_count -ne 0 -or $script:taskWrites -ne 0 -or $script:taskConfigured){throw 'DISABLED_RUNNING_SELECTED'}
            return
        }
        if($plan.target_count -ne 1){throw 'ENABLED_TASK_NOT_SELECTED'}
        if($scenario -eq 'active'){
            $ctx.facts.processes=@(@{writer=$writer;pid=987654})
            $result=Invoke-QuarantinePlan $ctx -PlanPath $plan.plan_path -ApprovePlanHash $plan.approval
            if($result.status -ne 'BLOCKED' -or $script:taskWrites -ne 0 -or -not $script:taskConfigured){throw 'ACTIVE_WRITER_GUARD_BYPASSED'}
            return
        }
        $script:taskJournal=Join-Path $ctx.output ('transaction-'+$data.id+'\journal.jsonl')
        $result=Invoke-QuarantinePlan $ctx -PlanPath $plan.plan_path -ApprovePlanHash $plan.approval -FixtureInterruptBeforeApplied:($scenario -eq 'interrupt')
        if($script:taskConfigured -or $script:taskDynamic -ne $state){throw 'CONFIG_DISABLE_OR_DYNAMIC_STATE_WRONG'}
        if($scenario -eq 'interrupt'){
            if($result.status -ne 'FAIL' -or @((Get-JournalRecords $script:taskJournal).records|Where-Object event -eq 'APPLIED').Count){throw 'INTERRUPTION_NOT_REPRODUCED'}
        }elseif($result.status -ne 'PASS'){throw 'RUNNING_TASK_POSTCONDITION_FALSE_FAIL'}
        $undo=Undo-Quarantine $ctx -Transaction $result.transaction -ApproveUndo
        if($undo.status -ne 'PASS' -or -not $script:taskConfigured -or $script:taskWrites -ne 2 -or
            @($undo.checks|Where-Object code -eq 'RESTORED_ORIGINAL').Count -ne 1){throw 'UNDO_FALSE_ALREADY_ORIGINAL'}
        $records=(Get-JournalRecords $script:taskJournal).records
        if(@($records|Where-Object event -eq 'UNDONE').Count -ne 1){throw 'UNDO_NOT_JOURNALED'}
        $repeat=Undo-Quarantine $ctx -Transaction $result.transaction -ApproveUndo
        if($repeat.status -ne 'PASS' -or $script:taskWrites -ne 2){throw 'IDEMPOTENT_UNDO_CHANGED_CONFIG'}
    } $Fixture.context $Fixture.writer $State $Enabled $Scenario
}
Case 'task F09 dynamic State never determines configured enable bit' {
    $f=New-Fixture
    & $module {
        param($ctx)
        $read=$ctx.PSObject.Copy();$read.fixture=$false
        function Get-ScheduledTask {param($TaskPath,$TaskName,$ErrorAction) [pscustomobject]@{State=$script:dynamic;Settings=[pscustomobject]@{Enabled=$script:configured}}}
        function Export-ScheduledTask {param($TaskPath,$TaskName,$ErrorAction) '<Task><Settings><Enabled>'+([string]$script:configured).ToLowerInvariant()+'</Enabled></Settings></Task>'}
        foreach($dynamic in @('Running','Queued','Ready','Disabled')){
            foreach($enabled in @($true,$false)){
                $script:dynamic=$dynamic;$script:configured=$enabled
                $result=Get-TargetState $read ([pscustomobject]@{kind='task';locator='\Synthetic\Guard'})
                if($result.enabled -ne $enabled){throw 'DYNAMIC_STATE_USED_AS_CONFIG'}
            }
        }
    } $f.context
}
Case 'task F09 missing or nonboolean Settings cannot fall back to State' {
    $f=New-Fixture
    & $module {
        param($ctx)
        $read=$ctx.PSObject.Copy();$read.fixture=$false
        function Get-ScheduledTask {param($TaskPath,$TaskName,$ErrorAction) $script:invalidTask}
        function Export-ScheduledTask {param($TaskPath,$TaskName,$ErrorAction) throw 'XML_SHOULD_NOT_BE_READ'}
        foreach($invalid in @([pscustomobject]@{State='Ready'},[pscustomobject]@{State='Running';Settings=[pscustomobject]@{Enabled='false'}})){
            $script:invalidTask=$invalid;$rejected=$false
            try{$null=Get-TargetState $read ([pscustomobject]@{kind='task';locator='\Synthetic\Guard'})}
            catch{if($_.Exception.Message -ne 'TASK_ENABLED_UNAVAILABLE'){throw};$rejected=$true}
            if(-not $rejected){throw 'MISSING_CONFIG_GUESSED'}
        }
    } $f.context
}
Case 'task F09 Running config disable and Undo restore configuration' {
    $f=New-Fixture;$before=TreeHash $f.home
    Test-TaskAdapterScenario $f 'Running' $true 'cycle'
    Assert ((TreeHash $f.home) -ceq $before)
}
Case 'task F09 Queued config disable and Undo restore configuration' {
    $f=New-Fixture;$before=TreeHash $f.home
    Test-TaskAdapterScenario $f 'Queued' $true 'cycle'
    Assert ((TreeHash $f.home) -ceq $before)
}
Case 'task F09 disabled Running or Queued task is excluded from Plan' {
    foreach($state in @('Running','Queued')){$f=New-Fixture;Test-TaskAdapterScenario $f $state $false 'disabled'}
}
Case 'task F09 interruption after disable before APPLIED remains recoverable' {
    $f=New-Fixture;Test-TaskAdapterScenario $f 'Running' $true 'interrupt'
}
Case 'task F09 active writer guard still blocks despite mocked running instance' {
    $f=New-Fixture;Test-TaskAdapterScenario $f 'Running' $true 'active'
}
