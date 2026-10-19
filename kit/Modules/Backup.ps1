function Assert-PrivateDirectory($Context,[string]$Path) {
    $p=Assert-PlainPath $Path -MustExist
    if($Context.fixture){return}
    $acl=Get-Acl -LiteralPath $p
    foreach($ace in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($ace.AccessControlType -eq 'Allow' -and $ace.IdentityReference.Value -notin @($Context.identity,'S-1-5-18')){throw 'PRIVATE_OUTPUT_ACL_REQUIRED_USE_NEW_OUTPUT'}
    }
    if(-not $acl.AreAccessRulesProtected){throw 'PRIVATE_OUTPUT_ACL_REQUIRED_USE_NEW_OUTPUT'}
}
# Private backup primitives. No secret contents are returned to the caller.
function New-PrivateDirectory($Context,[string]$Path) {
    $p=Assert-PlainPath $Path
    if(Test-Path -LiteralPath $p){throw 'DESTINATION_ALREADY_EXISTS'}
    if(-not $Context.fixture){
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        foreach($sid in @($Context.identity,'S-1-5-18')) {
            $rule=New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
            $acl.AddAccessRule($rule)
        }
        # Create atomically with protected ACL, before placing secrets in this directory.
        $di=New-Object IO.DirectoryInfo($p)
        if($PSVersionTable.PSVersion.Major -ge 7){[IO.FileSystemAclExtensions]::Create($di,$acl)}else{$di.Create($acl)}
    } else {[IO.Directory]::CreateDirectory($p)|Out-Null}
    Assert-PrivateDirectory $Context $p
    return $p
}
function Get-BackupInventory([string]$Root) {
    $rootPath=Assert-PlainPath $Root -MustExist
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($rootPath)
    $files=@();$dirs=@('')
    while($queue.Count){
        foreach($i in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force -ErrorAction Stop)){
            $p=Assert-PlainPath $i.FullName -MustExist
            $rel=$p.Substring($rootPath.Length+1)
            if($i.PSIsContainer){$dirs+= $rel;$queue.Enqueue($p)}else{
                $files+= [pscustomobject]@{path=$rel;bytes=[long]$i.Length;mtime=$i.LastWriteTimeUtc.Ticks;sha256=(Get-ShaFile $p)}
            }
        }
    }
    return [pscustomobject]@{files=@($files|Sort-Object path);directories=@($dirs|Sort-Object)}
}
function Assert-NoRepairProcesses($Context,$Plan) {
    foreach($p in @($Plan.processes)) {if(Get-RepairProcess $Context $p.pid){throw 'OFFLINE_PROCESS_STILL_PRESENT'}}
    foreach($w in @(Get-RepairWriters $Plan)){if(@(Get-ActiveWriters $Context $w.path).Count){throw 'ACTIVE_WRITER_PRESENT'}}
    if(-not $Context.fixture){
        # Conservative blockers only; no process is killed by its name.
        if(@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$_.Name -match '^(?i:codex|chatgpt)(\.exe)?$'}).Count){throw 'CLOSE_CODEX_AND_REPLAN_EXACT_PROCESS_SCOPE'}
    }
}
function New-RepairBackup {
    [CmdletBinding()]param($Context,$Plan,[string]$Run,[long]$FixtureAvailableBytes=-1,[int]$FixtureInterruptAfter=0)
    Assert-Context $Context -Mutation
    if(-not $Context.fixture -and ($FixtureAvailableBytes -ne -1 -or $FixtureInterruptAfter)){throw 'TEST_HOOK_FIXTURE_ONLY'}
    Assert-NoRepairProcesses $Context $Plan
    $inv=Get-BackupInventory $Context.home
    [long]$required=1MB;foreach($f in $inv.files){$required+=$f.bytes}
    $disk=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($Run))
    if($disk.DriveType -ne [IO.DriveType]::Fixed -or $disk.DriveFormat -ne 'NTFS'){throw 'LOCAL_FIXED_NTFS_BACKUP_REQUIRED'}
    $free=if($Context.fixture -and $FixtureAvailableBytes -ge 0){$FixtureAvailableBytes}else{$disk.AvailableFreeSpace}
    if($free -lt $required){throw 'BACKUP_SPACE_INSUFFICIENT'}
    $dest=New-PrivateDirectory $Context (Join-Path $Run ('backup-'+[guid]::NewGuid().ToString('N')))
    $payload=New-PrivateDirectory $Context (Join-Path $dest 'payload')
    $count=0
    foreach($dir in $inv.directories){if($dir){[IO.Directory]::CreateDirectory((Join-Path $payload $dir))|Out-Null}}
    foreach($f in $inv.files){
        $src=Assert-PlainPath (Join-Path $Context.home $f.path) -MustExist
        $target=Assert-PlainPath (Join-Path $payload $f.path)
        $stream=[IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            $copy=[IO.File]::Open($target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$stream.CopyTo($copy);$copy.Flush($true)}finally{$copy.Dispose()}
        } finally {$stream.Dispose()}
        if((Get-ShaFile $target) -ne $f.sha256){throw 'BACKUP_COPY_INCONSISTENT'}
        $count++;if($FixtureInterruptAfter -and $count -ge $FixtureInterruptAfter){throw 'BACKUP_INTERRUPTED'}
    }
    Assert-NoRepairProcesses $Context $Plan
    if((Get-StateHash (Get-BackupInventory $Context.home)) -ne (Get-StateHash $inv)){throw 'BACKUP_SOURCE_CHANGED'}
    $manifest=Join-Path $dest 'manifest.json'
    Write-DurableJson $manifest ([ordered]@{schema='rescue-backup-v1';run_id=$Plan.id;target_fingerprint=$Context.fingerprint;synthetic=[bool]$Context.fixture;files=@($inv.files);directories=$inv.directories;omissions=@();consistency='NO_KNOWN_WRITERS_AND_SOURCE_HASH_RECHECK_NOT_RESTORE_PROOF';external_projects='NOT_INCLUDED_UNLESS_INSIDE_EXPLICIT_HOME';created_at=[DateTime]::UtcNow.ToString('o')})
    $check=Test-BackupManifest $manifest $payload
    if($check.status -ne 'PASS'){throw 'BACKUP_VERIFICATION_FAILED'}
    return [pscustomobject]@{manifest=$manifest;manifest_hash=(Get-ShaFile $manifest);payload=$payload;files=$count;status='PASS';restore_proof='NOT_TESTED'}
}
function Assert-RepairBackup($Context,$Plan,$State) {
    if(-not $State.backup){throw 'SAME_RUN_VERIFIED_BACKUP_REQUIRED'}
    $b=$State.backup
    $null=Assert-PlainPath $b.manifest -MustExist
    if(-not (Test-Within $b.manifest (Join-Path $Context.output ('repair-'+$Plan.id)))){throw 'BACKUP_OUTSIDE_RUN'}
    if((Get-ShaFile $b.manifest) -ne $b.manifest_hash){throw 'BACKUP_MANIFEST_DRIFT'}
    $m=Read-BoundedManifestText $b.manifest|ConvertFrom-Json
    if($m.run_id -ne $Plan.id -or $m.target_fingerprint -ne $Context.fingerprint){throw 'BACKUP_RUN_MISMATCH'}
    if((Test-BackupManifest $b.manifest $b.payload).status -ne 'PASS'){throw 'BACKUP_CONTENT_INVALID'}
    return $m
}
