# Fully fictional fixtures; no real Codex data or startup API writes.
function RepairPlan($F,[string[]]$Files=@('config.toml','auth.json')) {New-RepairPlan $F.context -WriterScript $F.writer -ConfigurationFiles $Files -ConfirmTakeover}
function RepairApply($F,$P) {Invoke-Repair $F.context -PlanPath $P.plan_path -ApproveRepairHash $P.approval}
function RepairUndo($F,$P) {Undo-Repair $F.context -PlanPath $P.plan_path -ApproveRepairHash $P.approval -ApproveUndo}
function ProtectedHash($F) {return (@('skills','rules','sessions','state_5.sqlite','AGENTS.md','project'|ForEach-Object {$p=Join-Path $F.home $_;if(Test-Path $p -PathType Container){TreeHash $p}else{(Get-FileHash $p).Hash}}) -join '|')}
Case 'v02 exact approval and legal provider consent preserve rejected fixtures' {
 $f=New-Fixture;$p=RepairPlan $f
 RejectUnchanged $f {Invoke-Repair $f.context $p.plan_path ('0'*64)} 'EXPLICIT_REPAIR_HASH_APPROVAL_REQUIRED'
 RejectUnchanged $f {New-RepairPlan $f.context -ConfigurationFiles @('config.toml')} 'EXPLICIT_CONFIGURATION_CONFLICT_CONFIRMATION_REQUIRED'
}
Case 'v02 plan redacts auth and configuration secret values' {
 $f=New-Fixture;$secret='SYNTHETIC_TOKEN_NEVER_PUBLIC';Text (Join-Path $f.home 'config.toml') ('model_provider = "'+$secret+'"');Text (Join-Path $f.home 'auth.json') $secret
 $p=RepairPlan $f;Assert (-not ([IO.File]::ReadAllText($p.plan_path)).Contains($secret))
}
Case 'v02 scope excludes Skills and DB from configuration isolation' {
 $f=New-Fixture;Throws {New-RepairPlan $f.context -ConfigurationFiles @('skills') -ConfirmTakeover} 'CONFIGURATION_SCOPE_REFUSED'
 Assert (Test-Path (Join-Path $f.home 'skills/keep.md'))
}
Case 'v02 backup isolation and Undo execute real file changes and preserve all unapproved assets' {
 $f=New-Fixture;$before=TreeHash $f.home;$protected=ProtectedHash $f;$p=RepairPlan $f;$r=RepairApply $f $p
 Assert ($r.phase -eq 'AWAITING_OFFICIAL');Assert (-not (Test-Path (Join-Path $f.home 'config.toml')))
 Assert (-not (Test-Path (Join-Path $f.home 'auth.json')));Assert ((Test-BackupManifest $r.backup.manifest $r.backup.payload).status -eq 'PASS')
 Assert ((ProtectedHash $f) -ceq $protected);$u=RepairUndo $f $p;Assert ($u.exit_code -eq 0);Assert ((TreeHash $f.home) -ceq $before)
 $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json;Assert $db.objects[0].enabled;Assert $db.objects[1].exists;Assert (Test-Path $f.link)
}
Case 'v02 new official login prevents Undo overwrite and startup reenable' {
 $f=New-Fixture;$p=RepairPlan $f;$r=RepairApply $f $p;Text (Join-Path $f.home 'auth.json') 'SYNTHETIC_NEW_OFFICIAL_LOGIN';$before=TreeHash $f.home
 Throws {RepairUndo $f $p} 'UNDO_NEW_CONFIGURATION_CONFLICT';Assert ((TreeHash $f.home) -ceq $before)
 Assert (-not (Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json).objects[0].enabled)
}
Case 'v02 file interruption after mutation resumes and Undo restores bytes' {
 $f=New-Fixture;$before=TreeHash $f.home;$p=RepairPlan $f
 Throws {Invoke-Repair $f.context $p.plan_path $p.approval -FixtureInterruptAfterFile 1} 'SYNTHETIC_FILE_INTERRUPTION'
 $r=RepairApply $f $p;Assert ($r.phase -eq 'AWAITING_OFFICIAL');RepairUndo $f $p|Out-Null;Assert ((TreeHash $f.home) -ceq $before)
}
Case 'v02 backup interruption retains partial copy and Resume creates fresh verified snapshot' {
 $f=New-Fixture;$before=TreeHash $f.home;$p=RepairPlan $f
 Throws {Invoke-Repair $f.context $p.plan_path $p.approval -FixtureInterruptBackup 1} 'BACKUP_INTERRUPTED';Assert ((TreeHash $f.home) -ceq $before)
 $r=RepairApply $f $p;Assert ($r.backup.status -eq 'PASS');Assert (@(Get-ChildItem $r.run -Directory -Filter 'backup-*').Count -eq 2)
}
Case 'v02 disk full retains startup Undo and refuses configuration changes' {
 $f=New-Fixture;$before=TreeHash $f.home;$objects=[IO.File]::ReadAllText((Join-Path $f.root 'objects.json'));$p=RepairPlan $f
 Throws {Invoke-Repair $f.context $p.plan_path $p.approval -FixtureAvailableBytes 0} 'BACKUP_SPACE_INSUFFICIENT'
 Assert ((TreeHash $f.home) -ceq $before);Assert (-not (Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json).objects[0].enabled);RepairUndo $f $p|Out-Null;Assert ([IO.File]::ReadAllText((Join-Path $f.root 'objects.json')) -ceq $objects)
}
Case 'v02 corrupt manifest blocks Resume and Undo without file changes' {
 $f=New-Fixture;$p=RepairPlan $f;$r=RepairApply $f $p;Text $r.backup.manifest '{}';$before=TreeHash $f.home
 Throws {RepairApply $f $p} 'BACKUP_MANIFEST_DRIFT';Throws {RepairUndo $f $p} 'BACKUP_MANIFEST_DRIFT';Assert ((TreeHash $f.home) -ceq $before)
}
Case 'v02 copied payload corruption blocks configuration isolation' {
 $f=New-Fixture;$p=RepairPlan $f;$r=Invoke-Repair $f.context $p.plan_path $p.approval -StopAfter Backup
 Text (Join-Path $r.backup.payload 'config.toml') 'SYNTHETIC_CORRUPTION';$before=TreeHash $f.home
 Throws {RepairApply $f $p} 'BACKUP_CONTENT_INVALID';Assert ((TreeHash $f.home) -ceq $before)
}
Case 'v02 writer and configuration drift stop execution' {
 $f=New-Fixture;$p=RepairPlan $f;Text $f.writer '# changed fictional writer';RejectUnchanged $f {RepairApply $f $p} 'WRITER_DRIFT'
 $f=New-Fixture;$p=RepairPlan $f;Text (Join-Path $f.home 'config.toml') 'SYNTHETIC_EDIT_AFTER_PLAN'
 Throws {RepairApply $f $p} 'CONFIGURATION_NOT_IN_BACKUP';Assert ([IO.File]::ReadAllText((Join-Path $f.home 'config.toml')) -ceq 'SYNTHETIC_EDIT_AFTER_PLAN')
}
Case 'v02 live direct module calls require versioned capability' {
 $ctx=[pscustomobject]@{fixture=$false}
 Throws {Invoke-QuarantinePlan $ctx 'absent'} 'VERSIONED_REPAIR_CAPABILITY_REQUIRED';Throws {Undo-Quarantine $ctx 'absent' -ApproveUndo} 'VERSIONED_REPAIR_CAPABILITY_REQUIRED'
}
Case 'v02 PID reuse and extra force approval prevent unrelated termination' {
 $f=New-Fixture;$facts=$f.context.facts;$facts.processes=@([ordered]@{pid=987655;created='2026-01-01T00:00:00Z';owner='synthetic-user';executable=$f.writer;executable_hash='a';command_hash='a';parent=0;writer=$f.writer});Json (Join-Path $f.root 'facts.json') $facts
 $p=RepairPlan $f;Throws {RepairApply $f $p} ('FORCE_PROCESS_APPROVAL_REQUIRED:'+$p.processes[0].force_approval)
 $facts.processes[0].created='2026-01-02T00:00:00Z';Json (Join-Path $f.root 'facts.json') $facts
 Throws {Invoke-Repair $f.context $p.plan_path $p.approval -ApproveForceProcess @($p.processes[0].force_approval)} 'PROCESS_IDENTITY_DRIFT'
 Assert ((Get-Content (Join-Path $f.root 'facts.json') -Raw|ConvertFrom-Json).processes.Count -eq 1)
}
Case 'v02 Skills restored by selected file only and Undo preserves unrelated assets' {
 $f=New-Fixture;$before=TreeHash $f.home;$src=Join-Path $f.root 'authorized-old-backup';[IO.Directory]::CreateDirectory($src)|Out-Null
 Text (Join-Path $src 'skills/recovered/SKILL.md') '# Fictional local skill; no tools or network';$file=Join-Path $src 'skills/recovered/SKILL.md';$manifest=Join-Path $f.root 'old-manifest.json'
 Json $manifest @{schema='rescue-backup-v1';files=@(@{path='skills/recovered/SKILL.md';sha256=(Get-FileHash $file).Hash.ToLowerInvariant();bytes=(Get-Item $file).Length})}
 $p=New-RepairPlan $f.context -Symptom Assets -RestoreManifest $manifest -RestorePayload $src -AssetPaths @('skills/recovered/SKILL.md') -ReviewedAssetSources
 $r=RepairApply $f $p;Assert (Test-Path (Join-Path $f.home 'skills/recovered/SKILL.md'));Assert (Test-Path (Join-Path $f.home 'skills/keep.md'))
 RepairUndo $f $p|Out-Null;Assert ((TreeHash $f.home) -ceq $before)
}
Case 'v02 unreviewed Skills source remains blocked' {$f=New-Fixture;Throws {New-RepairPlan $f.context -AssetPaths @('skills/old/SKILL.md')} 'ASSET_SOURCE_REVIEW_REQUIRED'}
Case 'v02 Sandbox unsupported backend and precise rule stay read-only' {
 $f=New-Fixture;$path=Join-Path $f.home 'sandbox-bin';[IO.Directory]::CreateDirectory($path)|Out-Null
 $f.context.facts.sandbox|Add-Member -Force NoteProperty owner 'synthetic-old-owner';$f.context.facts.sandbox|Add-Member -Force NoteProperty sddl 'SYNTHETIC_DACL'
 $before=(Get-Acl $path).Sddl;$g=New-SandboxGuide $f.context $path -Backend mxc -ErrorCode helper_sandbox_lock_failed
 Assert (-not $g.automatic_acl_change);Assert (-not $g.precise_rule_matched)
 $rule=Join-Path $f.root 'reviewed-rule.json';$hash=& $module {Get-ShaText 'SYNTHETIC_DACL'}
 Json $rule @{schema='rescue-reviewed-owner-rule-v2';backend='legacy-windows';target_relative='sandbox-bin';before_owner='synthetic-old-owner';before_sddl_sha256=$hash;desired_owner='synthetic-user';change='OWNER_ONLY_KEEP_DACL'}
 $g=New-SandboxGuide $f.context $path -Backend legacy-windows -ErrorCode helper_sandbox_lock_failed -ReviewedRulePath $rule
 Assert $g.precise_rule_matched;Assert (-not $g.automatic_acl_change);Assert ((Get-Acl $path).Sddl -ceq $before)
}
Case 'v02 native fictional daemon stop backup isolation Resume 60s and Undo' {
 $f=New-Fixture;$protected=ProtectedHash $f
 Text $f.writer ('$p=Join-Path $PSScriptRoot ''profile/.codex/config.toml'';while($true){[IO.File]::WriteAllText($p,''model_provider = "fictional"'');Start-Sleep -Milliseconds 100}')
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path;$psi.Arguments='-NoProfile -File "'+$f.writer+'"';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $child=New-Object Diagnostics.Process;$child.StartInfo=$psi
 try {
  $null=$child.Start();Start-Sleep -Seconds 2;$facts=$f.context.facts;$facts.processes=@(@{pid=$child.Id;writer=$f.writer;native=$true});Json (Join-Path $f.root 'facts.json') $facts
  $p=New-RepairPlan $f.context -WriterScript $f.writer -CaptureStoppedConfiguration -ConfigurationFiles @('config.toml','auth.json') -ConfirmTakeover
  $r=Invoke-Repair $f.context $p.plan_path $p.approval -ApproveForceProcess @($p.processes[0].force_approval) -StopAfter StopWriter
  Assert ($r.phase -eq 'STOPPED');Assert ($child.WaitForExit(1000))
  # The exact plan explicitly approved the post-stop snapshot; keep startup Undo in the same run.
  $initial=TreeHash $f.home;$r=RepairApply $f $p;Assert ($r.phase -eq 'AWAITING_OFFICIAL')
  $r=Invoke-Repair $f.context $p.plan_path $p.approval -OfficialStepComplete -StabilitySeconds 60
  Assert ($r.phase -eq 'OBSERVED');Assert ($r.state -eq 'PARTIAL_RECOVERY');Assert ((ProtectedHash $f) -ceq $protected)
  RepairUndo $f $p|Out-Null;Assert ((TreeHash $f.home) -ceq $initial)
  Json (Join-Path $ResultDirectory 'synthetic-loop.json') @{schema='rescue-synthetic-loop-v2';synthetic=$true;native_fictional_daemon_stopped=$true;backup_hash_verified=$true;configuration_and_auth_isolated=$true;official_step='SIMULATED_CARD_NO_REAL_LOGIN';stability_seconds=60;unchanged_protected_assets=$true;undo_original_bytes=$true;GUI_A='NOT_TESTED';tool_B='NOT_TESTED';real_windows_startup_APIs='NOT_TESTED'}
 }finally{if(-not $child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()}
}

Case 'v02 project evidence covers explicit external scope without modifying Git or files' {
 $f=New-Fixture;$project=Join-Path $f.root 'project';Text (Join-Path $project 'tracked.txt') 'SYNTHETIC_PROJECT';Text (Join-Path $project '.git/HEAD') 'SYNTHETIC_GIT_METADATA'
 $before=TreeHash $project;$p=New-RepairPlan $f.context -ProjectRoots @($project)
 Throws {RepairApply $f $p} 'PROJECT_BACKUP_NOT_VERIFIED_PLAN_BLOCKED';Assert ((TreeHash $project) -ceq $before)
 $plan=Get-Content $p.plan_path -Raw|ConvertFrom-Json;Assert ($plan.protected_projects[0].files -eq 2)
}
Case 'v02 damaged Journal rejects Resume and preserves user assets' {
 $f=New-Fixture;$p=RepairPlan $f;$r=RepairApply $f $p;Text (Join-Path $r.run 'journal.jsonl') '{}';$before=TreeHash $f.home
 Throws {RepairApply $f $p} 'JOURNAL_CORRUPT';Assert ((TreeHash $f.home) -ceq $before)
}
Case 'v02 backup with source changed during copy refuses consistency claim' {
 $f=New-Fixture;$p=RepairPlan $f
 & $module {param($f,$p)
  $original=${function:Get-BackupInventory};$script:inventoryCalls=0
  try {
   $script:originalInventory=$original
   function script:Get-BackupInventory([string]$Root) {
    $script:inventoryCalls++
    if($script:inventoryCalls -eq 2){[IO.File]::WriteAllText((Join-Path $Root 'config.toml'),'SYNTHETIC_CONCURRENT_WRITE')}
    & $script:originalInventory $Root
   }
   $caught=$null;try {Invoke-Repair $f.context $p.plan_path $p.approval|Out-Null}catch{$caught=$_.Exception.Message}
   if($caught -ne 'BACKUP_SOURCE_CHANGED'){throw 'SOURCE_CHANGED_WAS_NOT_BLOCKED'}
  }finally{Set-Item Function:script:Get-BackupInventory $original}
 } $f $p
 Assert (Test-Path (Join-Path $f.home 'auth.json'))
 Assert (-not (Test-Path $f.link));RepairUndo $f $p|Out-Null;Assert (Test-Path $f.link)
}
Case 'v02 private backup directory ACL is created only on new synthetic target' {
 $f=New-Fixture;$target=Join-Path $f.root 'private-new-directory'
 & $module {param($target)
  $ctx=[pscustomobject]@{fixture=$false;identity=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
  $null=New-PrivateDirectory $ctx $target
  Assert-PrivateDirectory $ctx $target
 } $target
 Assert (Test-Path $target)
}

Case 'v02 repair DryRun is strictly mutation free even with exact approval' {
 $f=New-Fixture;$p=RepairPlan $f;$before=TreeHash $f.root
 $r=Invoke-Repair $f.context $p.plan_path $p.approval -DryRun
 Assert ($r.code -eq 'DRY_RUN_NO_MUTATIONS');Assert ((TreeHash $f.root) -ceq $before)
}

function Invoke-V02Entry([string]$Arguments) {
 $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path;$psi.Arguments=$Arguments;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $p=New-Object Diagnostics.Process;$p.StartInfo=$psi
 try{$null=$p.Start();$a=$p.StandardOutput.ReadToEndAsync();$b=$p.StandardError.ReadToEndAsync();if(-not $p.WaitForExit(30000)){$p.Kill();throw 'ENTRY_TIMEOUT'};return @{exit=$p.ExitCode;stdout=$a.GetAwaiter().GetResult();stderr=$b.GetAwaiter().GetResult()}}finally{$p.Dispose()}
}
Case 'v02 entry live gate precedes module IO and approved Repair Undo DryRun change nothing' {
 $f=New-Fixture;$copy=Join-Path $f.root 'entry-without-module.ps1';[IO.File]::WriteAllBytes($copy,[IO.File]::ReadAllBytes((Join-Path $repo 'kit/Rescue.ps1')))
 $v=Invoke-V02Entry ('-NoProfile -File "'+$copy+'" -Mode Quarantine');Assert ($v.exit -eq 3);Assert (($v.stdout|ConvertFrom-Json).code -eq 'VERSIONED_REPAIR_CAPABILITY_REQUIRED')
 $p=RepairPlan $f;$before=TreeHash $f.root
 foreach($mode in @('Resume','Undo')){
  $args='-NoProfile -File "'+(Join-Path $repo 'kit/Rescue.ps1')+'" -Mode '+$mode+' -FixtureRoot "'+$f.root+'" -CodexHome "'+$f.home+'" -OutputDirectory "'+$f.output+'" -PlanPath "'+$p.plan_path+'" -ApproveRepairHash '+$p.approval+' -DryRun -ApproveUndo -Channel C'
  $v=Invoke-V02Entry $args;Assert ($v.exit -eq 3) 'ENTRY_DRYRUN_EXIT';Assert (($v.stdout|ConvertFrom-Json).code -eq 'DRY_RUN_NO_MUTATIONS')
 }
 Assert ((TreeHash $f.root) -ceq $before)
}

Case 'v02 review expired forward blocks but original Undo remains available with conflicts protected' {
 foreach($conflict in @($false,$true)){
  $f=New-Fixture;$before=TreeHash $f.home;$p=RepairPlan $f;$r=RepairApply $f $p
  if($conflict){Text (Join-Path $f.home 'auth.json') 'SYNTHETIC_NEW_OFFICIAL_LOGIN'}
  & $module {param($f,$p,$conflict)
   $original=${function:Get-RepairUtcNow}
   try {
    function Get-RepairUtcNow {return [DateTime]::UtcNow.AddDays(8)}
    $caught='';try{Invoke-Repair $f.context $p.plan_path $p.approval|Out-Null}catch{$caught=$_.Exception.Message}
    if($caught -ne 'REPAIR_PLAN_EXPIRED_REPLAN_REQUIRED'){throw 'EXPIRED_FORWARD_NOT_REFUSED'}
    # Verify nested live Undo capability uses the same expired-plan rule without touching any live adapter.
    $f.context|Add-Member -Force NoteProperty repair_capability ([pscustomobject]@{path=$p.plan_path;approval=$p.approval})
    $null=Assert-RepairCapability $f.context 'Undo';$f.context.PSObject.Properties.Remove('repair_capability')
    if($conflict){
     $caught='';try{Undo-Repair $f.context $p.plan_path $p.approval -ApproveUndo|Out-Null}catch{$caught=$_.Exception.Message}
     if($caught -ne 'UNDO_NEW_CONFIGURATION_CONFLICT'){throw 'EXPIRED_UNDO_LOST_CONFLICT_GUARD'}
    }else{$u=Undo-Repair $f.context $p.plan_path $p.approval -ApproveUndo;if($u.exit_code -ne 0){throw 'EXPIRED_UNDO_FAILED'}}
   }finally{Set-Item Function:Get-RepairUtcNow $original}
  } $f $p $conflict
  if($conflict){Assert ([IO.File]::ReadAllText((Join-Path $f.home 'auth.json')) -ceq 'SYNTHETIC_NEW_OFFICIAL_LOGIN')}else{Assert ((TreeHash $f.home) -ceq $before)}
 }
}
Case 'v02 review Sandbox existing output ACL is enforced without changing existing permissions' {
 $f=New-Fixture;$target=Join-Path $f.home 'synthetic-sandbox';[IO.Directory]::CreateDirectory($target)|Out-Null
 # Use the real new-directory ACL code only on test-created paths; never a user directory.
 $ctx=New-RescueContext -CodexHome $f.home -OutputDirectory (Join-Path $f.root 'new-private-output')
 $g=New-SandboxGuide $ctx $target -Backend unknown -ErrorCode helper_sandbox_lock_failed
 Assert (Test-Path $g.private_snapshot)
 $g2=New-SandboxGuide $ctx $target -Backend unknown -ErrorCode helper_sandbox_lock_failed
 Assert (Test-Path $g2.private_snapshot)
 $unprotected=Join-Path $f.root 'existing-inherited-output';[IO.Directory]::CreateDirectory($unprotected)|Out-Null
 $before=(Get-Acl $unprotected).Sddl
 $ctx.output=$unprotected
 Throws {New-SandboxGuide $ctx $target -Backend unknown -ErrorCode helper_sandbox_lock_failed} 'PRIVATE_OUTPUT_ACL_REQUIRED_USE_NEW_OUTPUT'
 Assert ((Get-Acl $unprotected).Sddl -ceq $before)
 Assert (@(Get-ChildItem -LiteralPath $unprotected -Force).Count -eq 0)
}
