# Confined synthetic review fixtures. No host startup API mutations.
Case 'patch F11 multi writer startup rollback without a Home backup' {
 $f=New-Fixture;$second=Join-Path $f.root 'second.ps1';Text $second '# SYNTHETIC second writer'
 $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json
 $db.objects+=@{kind='task';locator='\Synthetic\Second';writer=$second;exists=$true;enabled=$true;value='';definition='SYNTHETIC_SECOND_TASK'};Json (Join-Path $f.root 'objects.json') $db
 $before=TreeHash $f.home;$p=New-RepairPlan $f.context -WriterScripts @($second,$f.writer) -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover
 $plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json;Assert ($plan.writers.Count -eq 2);Assert ($plan.startup_plans.Count -eq 2)
 Throws {Invoke-Repair $f.context $p.plan_path $p.approval -FixtureAvailableBytes 0} 'BACKUP_SPACE_INSUFFICIENT'
 Assert ((TreeHash $f.home) -ceq $before);Assert (-not (Test-Path $f.link))
 $run=Join-Path $f.output ('repair-'+$plan.id);$state=Get-Content (Join-Path $run 'state.json') -Raw|ConvertFrom-Json
 Assert (-not $state.backup);Assert ($state.phase -eq 'STOPPED')
 & $module {param($f,$plan,$run)
  $h=Get-JournalRecords (Join-Path $run 'journal.jsonl')
  if(@($h.records|Where-Object event -eq 'STARTUP_PREPARED').Count -ne 2){throw 'MISSING_STARTUP_SNAPSHOTS'}
  foreach($q in $plan.startup_plans){Assert-QuarantineUndoReady $f.context (Join-Path $f.output ('transaction-'+$q.id)) (Read-RescueJson $q.path) $q.hash}
 } $f $plan $run
 Assert ((RepairUndo $f $p).exit_code -eq 0);Assert ((TreeHash $f.home) -ceq $before);Assert (Test-Path $f.link)
 $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json;Assert $db.objects[0].enabled;Assert $db.objects[1].exists;Assert $db.objects[3].enabled
 Assert ((RepairUndo $f $p).exit_code -eq 0)
}
Case 'patch F12 missing or corrupt startup material blocks before file Undo' {
 foreach($fault in @('directory','undo','journal','shortcut')){
  $f=New-Fixture;$p=RepairPlan $f;$r=RepairApply $f $p;$plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json;$tx=Join-Path $f.output ('transaction-'+$plan.startup_plans[0].id)
  switch($fault){
   directory {[IO.Directory]::Move($tx,($tx+'-retained'))}
   undo {Text (Join-Path $tx 'undo.json') '{}'}
   journal {Text (Join-Path $tx 'journal.jsonl') '{}'}
   shortcut {$held=Get-ChildItem $tx -Filter 'held-*.lnk'|Select-Object -First 1;[IO.File]::Move($held.FullName,($held.FullName+'.retained'))}
  }
  $before=TreeHash $f.home;$heldConfig=Join-Path $r.run 'isolated-config.toml';$heldHash=(Get-FileHash $heldConfig).Hash
  $caught='';try{RepairUndo $f $p|Out-Null}catch{$caught=$_.Exception.Message}
  Assert ($caught -ne '') 'UNDO_MUST_REFUSE';Assert ((TreeHash $f.home) -ceq $before);Assert ((Get-FileHash $heldConfig).Hash -ceq $heldHash)
  $state=Get-Content (Join-Path $r.run 'state.json') -Raw|ConvertFrom-Json;Assert ($state.phase -ne 'UNDONE')
  Json (Join-Path $r.run 'expected-refusal.json') @{synthetic=$true;fault=$fault;code=$caught;no_file_undo=$true;not_marked_undone=$true}
 }
}
Case 'patch F12 startup conflict preflight and repeated Undo' {
 $f=New-Fixture;$before=TreeHash $f.home;$p=RepairPlan $f;$r=RepairApply $f $p
 $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json;$db.objects[1].value='SYNTHETIC_NEW_VALUE';$db.objects[1].exists=$true;Json (Join-Path $f.root 'objects.json') $db
 Throws {RepairUndo $f $p} 'STARTUP_UNDO_CONFLICT';Assert (-not (Test-Path (Join-Path $f.home 'config.toml')))
 $db.objects[1].value='';$db.objects[1].exists=$false;Json (Join-Path $f.root 'objects.json') $db
 Assert ((RepairUndo $f $p).exit_code -eq 0);Assert ((RepairUndo $f $p).exit_code -eq 0);Assert ((TreeHash $f.home) -ceq $before)
}
Case 'patch scope projects blocked and unknown startup sources unverified' {
 $f=New-Fixture;$project=Join-Path $f.root 'external-project';Text (Join-Path $project 'user.txt') 'SYNTHETIC_PROJECT'
 $p=New-RepairPlan $f.context -WriterScripts @($f.writer) -ProjectRoots @($project);$plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json
 Assert ($p.status -eq 'BLOCKED');Assert ($p.state -eq 'PLAN_SCOPE_BLOCKED');Assert ($plan.scope_blockers[0] -eq 'EXTERNAL_PROJECT_BACKUP_NOT_VERIFIED');Assert ($plan.unbacked_projects[0] -eq $project);Assert ($plan.unresolved_startup -like 'NOT_ANALYZED*')
 RejectUnchanged $f {RepairApply $f $p} 'PROJECT_BACKUP_NOT_VERIFIED_PLAN_BLOCKED'
}
Case 'patch F11 native reviver reproduces takeover and completes synthetic recovery' {
 $f=New-Fixture;$reviver=Join-Path $f.root 'reviver.ps1';$engine=(Get-Process -Id $PID).Path
 Text $f.writer @'
$ErrorActionPreference='Stop'
while($true){[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'profile/.codex/config.toml'),'SYNTHETIC_TAKEOVER');Start-Sleep -Seconds 2}
'@
 Text $reviver @'
$ErrorActionPreference='Stop'
$pidFile=Join-Path $PSScriptRoot 'writer-pid.txt'
while($true){
 try{
  $db=Get-Content (Join-Path $PSScriptRoot 'objects.json') -Raw|ConvertFrom-Json
  if($db.objects[0].enabled){
   $alive=$false
   if(Test-Path $pidFile){$childId=[int][IO.File]::ReadAllText($pidFile);$alive=$null -ne (Get-Process -Id $childId -ErrorAction SilentlyContinue)}
   if(-not $alive){
    $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=(Get-Process -Id $PID).Path;$si.Arguments='-NoProfile -File "'+(Join-Path $PSScriptRoot 'fake-writer.ps1')+'"';$si.UseShellExecute=$false;$si.CreateNoWindow=$true
    $p=[Diagnostics.Process]::Start($si);[IO.File]::WriteAllText($pidFile,[string]$p.Id);$p.Dispose()
   }
  }
 }catch{}
 Start-Sleep -Milliseconds 200
}
'@
 $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json;$db.objects[0].writer=$reviver;Json (Join-Path $f.root 'objects.json') $db
 $watch=$null;$writerChild=$null;$first=$null
 try{
  $si=New-Object Diagnostics.ProcessStartInfo;$si.FileName=$engine;$si.Arguments='-NoProfile -File "'+$reviver+'"';$si.UseShellExecute=$false;$si.CreateNoWindow=$true
  $watch=[Diagnostics.Process]::Start($si);$pidFile=Join-Path $f.root 'writer-pid.txt'
  $deadline=[DateTime]::UtcNow.AddSeconds(15);while(-not (Test-Path $pidFile)){if([DateTime]::UtcNow -gt $deadline){throw 'CHILD_START_TIMEOUT'};Start-Sleep -Milliseconds 200}
  $first=[Diagnostics.Process]::GetProcessById([int][IO.File]::ReadAllText($pidFile));$first.Kill();Assert ($first.WaitForExit(5000));$firstExit=$first.ExitCode
  $deadline=[DateTime]::UtcNow.AddSeconds(15)
  do{Start-Sleep -Milliseconds 200;$newId=[int][IO.File]::ReadAllText($pidFile);if([DateTime]::UtcNow -gt $deadline){throw 'REVIVAL_NOT_REPRODUCED'}}while($newId -eq $first.Id)
  $writerChild=[Diagnostics.Process]::GetProcessById($newId);Start-Sleep -Seconds 3
  $facts=$f.context.facts;$facts.processes=@(@{pid=$watch.Id;writer=$reviver;native=$true},@{pid=$writerChild.Id;writer=$f.writer;native=$true});Json (Join-Path $f.root 'facts.json') $facts
  $p=New-RepairPlan $f.context -WriterScripts @($reviver,$f.writer) -CaptureStoppedConfiguration -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover
  Assert ($p.processes.Count -eq 2);$protected=ProtectedHash $f
  $r=Invoke-Repair $f.context $p.plan_path $p.approval -ApproveForceProcess @($p.processes|ForEach-Object force_approval)
  Assert ($r.phase -eq 'AWAITING_OFFICIAL');Assert ($watch.WaitForExit(1000));Assert ($writerChild.WaitForExit(1000))
  Assert ((Test-BackupManifest $r.backup.manifest $r.backup.payload).status -eq 'PASS');Assert (-not (Test-Path (Join-Path $f.home 'config.toml')))
  $r=Invoke-Repair $f.context $p.plan_path $p.approval -OfficialStepComplete -StabilitySeconds 60
  Assert ($r.phase -eq 'OBSERVED');Assert ($r.state -eq 'PARTIAL_RECOVERY');Assert ((ProtectedHash $f) -ceq $protected)
  $configHash=(Get-FileHash (Join-Path $r.backup.payload 'config.toml')).Hash
  Assert ((RepairUndo $f $p).exit_code -eq 0);Assert ((Get-FileHash (Join-Path $f.home 'config.toml')).Hash -ceq $configHash);Assert (Test-Path $f.link)
  Json (Join-Path $ResultDirectory 'revival-loop.json') @{synthetic=$true;revival_reproduced=$true;first_exit=$firstExit;reviver_exit=$watch.ExitCode;writer_exit=$writerChild.ExitCode;repair_phase='OBSERVED';repair_exit=$r.exit_code;backup_verified=$true;stability_seconds=60;undo_exit=0;protected_assets_unchanged=$true;GUI='NOT_TESTED';real_startup_APIs='NOT_TESTED';reboot='NOT_TESTED'}
 }finally{foreach($proc in @($watch,$writerChild,$first)){if($proc){try{if(-not $proc.HasExited){$proc.Kill();$null=$proc.WaitForExit(5000)}}finally{$proc.Dispose()}}}}
}

Case 'patch approved execution order and stopped configuration binding cannot be bypassed' {
 $f=New-Fixture;$p=RepairPlan $f;$plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json
 $plan.execution_policy='rescue-explicit-run-v2';Json $p.plan_path $plan;$hash=(Get-FileHash $p.plan_path).Hash.ToLowerInvariant()
 RejectUnchanged $f {Invoke-Repair $f.context $p.plan_path $hash} 'EXECUTION_ORDER_CHANGED_REPLAN_REQUIRED'
 $f=New-Fixture;$p=New-RepairPlan $f.context -WriterScript $f.writer -CaptureStoppedConfiguration -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover
 $r=RepairApply $f $p;$statePath=Join-Path $r.run 'state.json';$state=Get-Content $statePath -Raw|ConvertFrom-Json
 $state.PSObject.Properties.Remove('stopped_files');Json $statePath $state;$before=TreeHash $f.home
 Throws {RepairUndo $f $p} 'STOPPED_CONFIGURATION_BINDING_INVALID';Assert ((TreeHash $f.home) -ceq $before)
 Throws {RepairApply $f $p} 'STOPPED_CONFIGURATION_BINDING_INVALID'
}

Case 'patch retry startup-only partial Undo never requires an uncreated configuration snapshot' {
 $f=New-Fixture;$before=TreeHash $f.home;$p=New-RepairPlan $f.context -WriterScript $f.writer -CaptureStoppedConfiguration -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover
 & $module {param($f,$p)
  $originalStop=${function:Stop-RepairWriters};$originalUndo=${function:Undo-Quarantine}
  try{
   function Stop-RepairWriters {throw 'SYNTHETIC_STOP_INTERRUPTION'}
   $caught='';try{Invoke-Repair $f.context $p.plan_path $p.approval|Out-Null}catch{$caught=$_.Exception.Message}
   if($caught -ne 'SYNTHETIC_STOP_INTERRUPTION'){throw 'WRONG_STOP_BOUNDARY'}
   function Undo-Quarantine {return [pscustomobject]@{exit_code=2}}
   $caught='';try{Undo-Repair $f.context $p.plan_path $p.approval -ApproveUndo|Out-Null}catch{$caught=$_.Exception.Message}
   if($caught -ne 'STARTUP_UNDO_PARTIAL_CONFLICT_INSPECT_ITEM_RESULTS'){throw 'PARTIAL_UNDO_NOT_RECORDED'}
   Set-Item Function:Undo-Quarantine $originalUndo
   $u=Undo-Repair $f.context $p.plan_path $p.approval -ApproveUndo
   if($u.exit_code -ne 0){throw 'STARTUP_ONLY_UNDO_RETRY_FAILED'}
  }finally{Set-Item Function:Stop-RepairWriters $originalStop;Set-Item Function:Undo-Quarantine $originalUndo}
 } $f $p
 Assert ((TreeHash $f.home) -ceq $before);Assert (Test-Path $f.link)
}

Case 'Beta default entry is Diagnose and preserves fixture user data' {
 $f=New-Fixture;$before=TreeHash $f.home;$objects=[IO.File]::ReadAllText((Join-Path $f.root 'objects.json'))
 $args='-NoProfile -File "'+(Join-Path $repo 'kit/Rescue.ps1')+'" -FixtureRoot "'+$f.root+'" -CodexHome "'+$f.home+'" -OutputDirectory "'+$f.output+'" -Channel C -StabilitySeconds 0'
 $v=Invoke-V02Entry $args;Assert ($v.stdout -match 'rescue-report-v1');Assert ($v.exit -eq 3)
 Assert ((TreeHash $f.home) -ceq $before);Assert ([IO.File]::ReadAllText((Join-Path $f.root 'objects.json')) -ceq $objects)
 Assert (@(Get-ChildItem $f.output -Filter 'repair-*').Count -eq 0)
}
Case 'Beta risk disclosure is in exact plan and executable repair remains approval scoped' {
 $f=New-Fixture;$before=TreeHash $f.home;$p=RepairPlan $f;$plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json
 Assert ($plan.experimental_warning -match 'EXPERIMENTAL BETA.*NOT_TESTED');Assert ($p.summary.experimental_warning -ceq $plan.experimental_warning)
 RejectUnchanged $f {Invoke-Repair $f.context $p.plan_path ('0'*64)} 'EXPLICIT_REPAIR_HASH_APPROVAL_REQUIRED'
 $snapshot=TreeHash $f.root;$dry=Invoke-Repair $f.context $p.plan_path $p.approval -DryRun;Assert ($dry.code -eq 'DRY_RUN_NO_MUTATIONS');Assert ((TreeHash $f.root) -ceq $snapshot)
 $r=RepairApply $f $p;Assert ($r.phase -eq 'AWAITING_OFFICIAL');Assert ((Test-BackupManifest $r.backup.manifest $r.backup.payload).status -eq 'PASS')
 Assert ((RepairUndo $f $p).exit_code -eq 0);Assert ((TreeHash $f.home) -ceq $before)
}
