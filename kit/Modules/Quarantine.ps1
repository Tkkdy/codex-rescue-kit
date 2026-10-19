function Assert-UndoWriter($Context,$Plan) {
    try {
        $writer=Assert-Writer $Plan.writer
        if($Context.fixture -and -not (Test-Within $writer $Context.fixture_root)){throw 'FIXTURE_ESCAPE'}
        if((Get-ShaFile $writer) -ne $Plan.writer_hash){throw 'WRITER_DRIFT'}
    } catch { throw 'UNDO_WRITER_DRIFT_REVIEW_REQUIRED' }
}
function Assert-Writer([string]$Writer) {
    $p=Assert-PlainPath $Writer -MustExist
    if(-not (Test-Path -LiteralPath $p -PathType Leaf) -or [IO.Path]::GetExtension($p) -notin @('.ps1','.py','.pyw','.exe','.vbs')) { throw 'WRITER_MUST_BE_EXPLICIT_CODE_FILE' }
    return $p
}
function New-QuarantinePlan {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$WriterScript)
    Assert-Context $Context
    $writer=Assert-Writer $WriterScript
    if($Context.fixture -and -not (Test-Within $writer $Context.fixture_root)) { throw 'FIXTURE_ESCAPE' }
    $targets=@()
    foreach($candidate in @(Get-WriterCandidates $Context $writer)) {
        $target=[pscustomobject]@{kind=[string]$candidate.kind;locator=[string]$candidate.locator;writer=$writer}
        $before=Get-TargetState $Context $target
        if($target.kind -eq 'startup' -and [IO.Path]::GetPathRoot($target.locator) -ine [IO.Path]::GetPathRoot($Context.output)){throw 'STARTUP_REQUIRES_SAME_VOLUME_OUTPUT'}
        if(-not $before.exists -or ($target.kind -eq 'task' -and -not $before.enabled)) { continue }
        if($target.kind -eq 'run' -and -not $Context.fixture -and -not (Get-WriterMatch $before.value $writer)) { throw 'WRITER_ASSOCIATION_DRIFT' }
        $targets += [pscustomobject]@{kind=$target.kind;locator=$target.locator;before=$before;before_hash=(Get-StateHash $before)}
    }
    $plan=[ordered]@{schema='rescue-plan-v1';id=[guid]::NewGuid().ToString('N');created_at=[DateTime]::UtcNow.ToString('o');target_fingerprint=$Context.fingerprint;synthetic=[bool]$Context.fixture;writer=$writer;writer_hash=(Get-ShaFile $writer);targets=@($targets);warning='Disable confirmed startup writers only. Running process memory is not reversible; no process is terminated.'}
    $p=Join-Path $Context.output ('plan-'+$plan.id+'.json')
    Write-DurableJson $p $plan
    return [pscustomobject]@{plan_path=$p;approval=(Get-ShaFile $p);target_count=$targets.Count;synthetic=$Context.fixture;preview=@($targets | ForEach-Object {@{kind=$_.kind;object_fingerprint=(Get-ShaText $_.locator)}})}
}
function Read-ValidatedPlan($Context,[string]$PlanPath,[string]$Approval) {
    Assert-Context $Context -Mutation
    $p=Assert-PlainPath $PlanPath -MustExist
    if(-not (Test-Within $p $Context.output)) { throw 'PLAN_OUTSIDE_RUN' }
    if($Approval -notmatch '^[a-fA-F0-9]{64}$' -or (Get-ShaFile $p) -ne $Approval.ToLowerInvariant()) { throw 'EXPLICIT_PLAN_HASH_APPROVAL_REQUIRED' }
    $plan=Read-RescueJson $p
    if($plan.schema -ne 'rescue-plan-v1' -or $plan.id -notmatch '^[a-f0-9]{32}$' -or $plan.target_fingerprint -ne $Context.fingerprint -or [bool]$plan.synthetic -ne [bool]$Context.fixture) { throw 'PLAN_CONTEXT_MISMATCH' }
    $writer=Assert-Writer $plan.writer
    if((Get-ShaFile $writer) -ne $plan.writer_hash) { throw 'WRITER_DRIFT' }
    if($Context.fixture -and -not (Test-Within $writer $Context.fixture_root)) { throw 'FIXTURE_ESCAPE' }
    $current=@(Get-WriterCandidates $Context $writer)
    $seen=@{}
    foreach($target in @($plan.targets)) {
        if($target.kind -notin @('task','run','startup')) { throw 'UNSUPPORTED_TARGET' }
        $key=$target.kind+'|'+$target.locator
        if($seen.ContainsKey($key)){throw 'DUPLICATE_TARGET'};$seen[$key]=$true
        $match=@($current | Where-Object {$_.kind -eq $target.kind -and $_.locator -eq $target.locator})
        if($match.Count -ne 1) { throw 'TARGET_NOT_CURRENTLY_ASSOCIATED' }
        if((Get-StateHash $target.before) -ne $target.before_hash -or (Get-StateHash (Get-TargetState $Context $target)) -ne $target.before_hash) { throw 'OBJECT_DRIFT' }
    }
    return $plan
}
function Get-JournalRecords([string]$Path) {
    $p=Assert-PlainPath $Path -MustExist
    if((Get-Item -LiteralPath $p).Length -gt 8MB) { throw 'JOURNAL_TOO_LARGE' }
    $prev='ROOT';$seq=0;$records=@()
    foreach($line in [IO.File]::ReadAllLines($p)) {
        if([string]::IsNullOrWhiteSpace($line)){throw 'JOURNAL_CORRUPT'}
        $r=$line | ConvertFrom-Json -ErrorAction Stop
        if(-not $r.PSObject.Properties['seq'] -or -not $r.PSObject.Properties['prev'] -or -not $r.PSObject.Properties['hash'] -or -not $r.PSObject.Properties['payload']){throw 'JOURNAL_CORRUPT'}
        if($r.seq -ne $seq -or $r.prev -ne $prev -or $r.hash -ne (Get-ShaText ($prev+'|'+[string]$r.payload))) { throw 'JOURNAL_CORRUPT' }
        $records+=($r.payload | ConvertFrom-Json -ErrorAction Stop);$prev=$r.hash;$seq++
    }
    return [pscustomobject]@{records=@($records);tail=$prev;count=$seq}
}
function Add-Journal([string]$Path,$Data) {
    $prev='ROOT';$seq=0
    if(Test-Path -LiteralPath $Path){$read=Get-JournalRecords $Path;$prev=$read.tail;$seq=$read.count}
    $payload=$Data | ConvertTo-Json -Depth 20 -Compress
    $envelope=[ordered]@{seq=$seq;prev=$prev;payload=$payload;hash=(Get-ShaText ($prev+'|'+$payload))}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($envelope | ConvertTo-Json -Compress)+"`n")
    $f=[IO.FileStream]::new($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Invoke-QuarantinePlan {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$PlanPath,[string]$ApprovePlanHash,[switch]$DryRun,[int]$FixtureInterruptAfter=0,[switch]$FixtureInterruptBeforeApplied,[switch]$PrepareOnly,[switch]$Prepared)
    # Pre-backup startup changes have their own durable snapshots, scoped to the approved repair.
    if(-not $DryRun -and (-not $Context.fixture -or $PrepareOnly -or $Prepared)){
        $cap=Assert-RepairCapability $Context 'Quarantine'
        if(-not @(Get-RepairStartupPlans $cap|Where-Object {$_.path -ceq $PlanPath -and $_.hash -ceq $ApprovePlanHash}).Count){throw 'REPAIR_QUARANTINE_SCOPE_MISMATCH'}
    }
    if($DryRun) {
        $p=Read-RescueJson $PlanPath
        return [pscustomobject]@{status='NOT_TESTED';code='DRY_RUN_NO_MUTATIONS';target_count=@($p.targets).Count;approval=(Get-ShaFile $PlanPath)}
    }
    if(($FixtureInterruptAfter -gt 0 -or $FixtureInterruptBeforeApplied) -and -not $Context.fixture) { throw 'TEST_HOOK_FIXTURE_ONLY' }
    $plan=Read-ValidatedPlan $Context $PlanPath $ApprovePlanHash
    if(@($plan.targets).Count -eq 0) { return [pscustomobject]@{status='N/A';code='NO_CONFIRMED_ENABLED_TARGETS';exit_code=0} }
    if(-not ($PrepareOnly -or $Prepared) -and @(Get-ActiveWriters $Context $plan.writer).Count -gt 0) { return [pscustomobject]@{status='BLOCKED';code='ACTIVE_WRITER_STOP_MANUALLY_MEMORY_NOT_REVERSIBLE';exit_code=3} }
    $run=Join-Path $Context.output ('transaction-'+$plan.id)
    if($Prepared){
        $h=Get-JournalRecords (Join-Path $run 'journal.jsonl')
        if($h.count -ne 1 -or $h.records[0].event -ne 'BEGIN' -or $h.records[0].approved_plan_hash -ne $ApprovePlanHash -or $h.records[0].context -ne $Context.fingerprint -or (Get-ShaFile (Join-Path $run 'undo.json')) -ne $h.records[0].plan_hash){throw 'PREPARED_TRANSACTION_INVALID'}
    }else{
        if(Test-Path -LiteralPath $run){throw 'TRANSACTION_ALREADY_EXISTS_USE_UNDO'}
        $null=New-PrivateDirectory $Context $run
    }
    $lockPath=Join-Path $Context.output 'mutation.lock'
    $lock=[IO.FileStream]::new($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $journal=Join-Path $run 'journal.jsonl'
    try {
        # Plan/undo snapshot durably exists before the first mutation.
        if(-not $Prepared){
            Write-DurableJson (Join-Path $run 'undo.json') $plan
            $undoHash=Get-ShaFile (Join-Path $run 'undo.json')
            Add-Journal $journal @{event='BEGIN';plan_hash=$undoHash;approved_plan_hash=$ApprovePlanHash;context=$Context.fingerprint;at=[DateTime]::UtcNow.ToString('o')}
        }
        if($PrepareOnly){return [pscustomobject]@{status='PASS';transaction=$run;exit_code=0}}
        $index=0
        foreach($target in $plan.targets) {
            $before=Get-TargetState $Context $target
            if((Get-StateHash $before) -ne $target.before_hash) { throw 'OBJECT_DRIFT' }
            if((Get-ShaFile (Assert-Writer $plan.writer)) -ne $plan.writer_hash){throw 'WRITER_DRIFT'}
            $desired=Get-DesiredState $before
            $held=Join-Path $run ('held-'+$index+'.lnk')
            Add-Journal $journal @{event='PENDING';index=$index;before_hash=$target.before_hash;after_hash=(Get-StateHash $desired)}
            Set-TargetState $Context $target $desired $held
            if($FixtureInterruptBeforeApplied){throw 'SYNTHETIC_INTERRUPTION_AFTER_MUTATION'}
            if((Get-StateHash (Get-TargetState $Context $target)) -ne (Get-StateHash $desired)) { throw 'POSTCONDITION_FAILED' }
            Add-Journal $journal @{event='APPLIED';index=$index}
            $index++
            if($FixtureInterruptAfter -eq $index){throw 'SYNTHETIC_INTERRUPTION'}
        }
        Add-Journal $journal @{event='COMMITTED';count=$index}
        return [pscustomobject]@{status='PASS';code='CONFIRMED_WRITER_ENTRIES_ISOLATED_NOT_CODEX_RECOVERY';transaction=$run;exit_code=0}
    } catch {
        # Leave recoverable pending records. Do not guess that partial changes were undone.
        if(Test-Path -LiteralPath $journal){try{Add-Journal $journal @{event='INTERRUPTED';code='INSPECT_AND_UNDO'}}catch{}}
        return [pscustomobject]@{status='FAIL';code='TRANSACTION_INTERRUPTED_USE_UNDO';transaction=$run;exit_code=2}
    } finally { $lock.Dispose() }
}
function Undo-Quarantine {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$Transaction,[switch]$ApproveUndo,[switch]$DryRun)
    # v0.2: live Undo is reachable only through the exact approved repair session.
    if(-not $DryRun -and -not $Context.fixture){$cap=Assert-RepairCapability $Context 'Undo';if(-not @(Get-RepairStartupPlans $cap|Where-Object {$Transaction -ceq (Join-Path $Context.output ('transaction-'+$_.id))}).Count){throw 'REPAIR_UNDO_SCOPE_MISMATCH'}}
    Assert-Context $Context -Mutation
    $run=Assert-PlainPath $Transaction -MustExist
    if((Split-Path -Parent $run) -ine $Context.output -or (Split-Path -Leaf $run) -notmatch '^transaction-[a-f0-9]{32}$') { throw 'TRANSACTION_SCOPE_REFUSED' }
    $journal=Join-Path $run 'journal.jsonl';$history=Get-JournalRecords $journal
    if($history.count -eq 0 -or $history.records[0].event -ne 'BEGIN' -or $history.records[0].context -ne $Context.fingerprint) { throw 'JOURNAL_CONTEXT_INVALID' }
    $undoPath=Join-Path $run 'undo.json'
    if((Get-ShaFile $undoPath) -ne $history.records[0].plan_hash) { throw 'UNDO_MATERIAL_CORRUPT' }
    $plan=Read-RescueJson $undoPath
    if($plan.schema -ne 'rescue-plan-v1' -or $plan.target_fingerprint -ne $Context.fingerprint -or [bool]$plan.synthetic -ne [bool]$Context.fixture) { throw 'UNDO_CONTEXT_INVALID' }
    # Same-user tampering is out of scope, but malformed/unassociated target data is still rejected.
    foreach($target in $plan.targets) {
        if($target.kind -notin @('task','run','startup') -or (Get-StateHash $target.before) -ne $target.before_hash) { throw 'UNDO_MATERIAL_CORRUPT' }
    }
    $pending=@($history.records | Where-Object event -eq 'PENDING')
    $checks=@()
    for($i=$pending.Count-1;$i -ge 0;$i--) {
        $entry=$pending[$i];$index=[int]$entry.index
        if($index -lt 0 -or $index -ge @($plan.targets).Count){throw 'JOURNAL_INDEX_INVALID'}
        $target=$plan.targets[$index];$desired=Get-DesiredState $target.before
        if($entry.before_hash -ne $target.before_hash -or $entry.after_hash -ne (Get-StateHash $desired)){throw 'JOURNAL_STATE_INVALID'}
        try {$actual=Get-TargetState $Context $target;$hash=Get-StateHash $actual}
        catch {$checks+=@{index=$index;status='FAIL';code='OBJECT_UNAVAILABLE'};continue}
        if($hash -eq $target.before_hash){$checks+=@{index=$index;status='PASS';code='ALREADY_ORIGINAL'};continue}
        if($hash -ne $entry.after_hash){$checks+=@{index=$index;status='FAIL';code='UNDO_CONFLICT'};continue}
        if($DryRun -or -not $ApproveUndo){$checks+=@{index=$index;status='NOT_TESTED';code='UNDO_PREVIEW_APPROVAL_REQUIRED'};continue}
        try {Assert-UndoWriter $Context $plan}
        catch {$checks+=@{index=$index;status='FAIL';code='UNDO_WRITER_DRIFT_REVIEW_REQUIRED'};continue}
        $held=Join-Path $run ('held-'+$index+'.lnk')
        if($target.kind -eq 'startup') {
            if(-not (Test-Path -LiteralPath $held -PathType Leaf) -or (Get-ShaFile (Assert-PlainPath $held -MustExist)) -ne $target.before.definition){$checks+=@{index=$index;status='FAIL';code='HELD_COPY_CHANGED_OR_MISSING'};continue}
        }
        $lock=[IO.FileStream]::new((Join-Path $Context.output 'mutation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try {
            if((Get-StateHash (Get-TargetState $Context $target)) -ne $entry.after_hash){throw 'UNDO_CONFLICT'}
            Assert-UndoWriter $Context $plan
            Add-Journal $journal @{event='UNDO_PENDING';index=$index}
            Set-TargetState $Context $target $target.before $held
            if((Get-StateHash (Get-TargetState $Context $target)) -ne $target.before_hash){throw 'UNDO_POSTCONDITION_FAILED'}
            Add-Journal $journal @{event='UNDONE';index=$index}
            $checks+=@{index=$index;status='PASS';code='RESTORED_ORIGINAL'}
        } catch {$checks+=@{index=$index;status='FAIL';code=$(if($_.Exception.Message -eq 'UNDO_WRITER_DRIFT_REVIEW_REQUIRED'){'UNDO_WRITER_DRIFT_REVIEW_REQUIRED'}else{'UNDO_FAILED_INSPECT_JOURNAL'})}}
        finally {$lock.Dispose()}
    }
    $exit=Get-RescueExitCode $checks
    return [pscustomobject]@{status=$(if($exit -eq 0){'PASS'}elseif($exit -eq 3){'NOT_TESTED'}else{'FAIL'});code='UNDO_ITEM_RESULTS_ONLY_NO_PROCESS_RESTART';checks=@($checks);exit_code=$exit}
}
function Assert-QuarantineUndoReady($Context,[string]$Transaction,$ApprovedPlan,[string]$ApprovedHash) {
    $run=Assert-PlainPath $Transaction -MustExist
    if((Split-Path -Parent $run) -ine $Context.output -or (Split-Path -Leaf $run) -cne ('transaction-'+$ApprovedPlan.id)){throw 'TRANSACTION_SCOPE_REFUSED'}
    Assert-PrivateDirectory $Context $run
    $h=Get-JournalRecords (Join-Path $run 'journal.jsonl')
    $u=Join-Path $run 'undo.json'
    if($h.count -lt 1 -or $h.records[0].event -ne 'BEGIN' -or $h.records[0].context -ne $Context.fingerprint -or $h.records[0].approved_plan_hash -ne $ApprovedHash -or (Get-ShaFile $u) -ne $h.records[0].plan_hash){throw 'STARTUP_TRANSACTION_BINDING_INVALID'}
    $snapshot=Read-RescueJson $u
    if((Get-StateHash $snapshot) -ne (Get-StateHash $ApprovedPlan)){throw 'UNDO_MATERIAL_CORRUPT'}
    Assert-UndoWriter $Context $snapshot
    $pending=@($h.records|Where-Object event -eq 'PENDING');$seen=@{}
    foreach($entry in $pending){
        $i=[int]$entry.index
        if($i -lt 0 -or $i -ge @($snapshot.targets).Count -or $seen.ContainsKey($i)){throw 'JOURNAL_INDEX_INVALID'}
        $seen[$i]=$true;$t=$snapshot.targets[$i];$desired=Get-DesiredState $t.before
        if($entry.before_hash -ne $t.before_hash -or $entry.after_hash -ne (Get-StateHash $desired)){throw 'JOURNAL_STATE_INVALID'}
    }
    for($i=0;$i -lt @($snapshot.targets).Count;$i++){
        $t=$snapshot.targets[$i];$actual=Get-StateHash (Get-TargetState $Context $t)
        if($actual -eq $t.before_hash){continue}
        if(-not $seen.ContainsKey($i) -or $actual -ne (Get-StateHash (Get-DesiredState $t.before))){throw 'STARTUP_UNDO_CONFLICT'}
        if($t.kind -eq 'startup'){
            $held=Assert-PlainPath (Join-Path $run ('held-'+$i+'.lnk')) -MustExist
            if((Get-ShaFile $held) -ne $t.before.definition){throw 'HELD_COPY_CHANGED_OR_MISSING'}
        }
    }
}
