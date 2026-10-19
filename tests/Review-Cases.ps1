# Dot-sourced only by Run-Tests.ps1; all mutations use generated fixtures.
Case 'F06 exact refusal helper rejects unrelated exceptions' {
    Throws {Throws {throw 'UNRELATED_FAILURE'} 'EXPECTED_GUARD'} 'WRONG_REJECTION_CODE'
    Throws {Throws {} 'EXPECTED_GUARD'} 'EXPECTED_REJECTION'
}
Case 'F01 fixed writable Run factory and mock mutation preserve type and conflicts' {
    & $module {
        $factory=(Get-Command Open-RunKeyForWrite).ScriptBlock.ToString()
        if(-not $factory.Contains("OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run',"+'$true)')){throw 'WRITABLE_FACTORY_REQUIRED'}
        $script:reviewKey=[pscustomobject]@{values=@{Guard='original';''='default';Unrelated='keep'};closed=0;flushed=0;types=@{}}
        $script:reviewKey | Add-Member ScriptMethod GetValueNames {return [string[]]@($this.values.Keys)}
        $script:reviewKey | Add-Member ScriptMethod GetValueKind {param($name) return [Microsoft.Win32.RegistryValueKind]::String}
        $script:reviewKey | Add-Member ScriptMethod GetValue {param($name,$fallback,$options) return $this.values[$name]}
        $script:reviewKey | Add-Member ScriptMethod DeleteValue {param($name,$missing) $this.values.Remove($name)}
        $script:reviewKey | Add-Member ScriptMethod SetValue {param($name,$value,$kind) $this.values[$name]=$value;$this.types[$name]=$kind.ToString()}
        $script:reviewKey | Add-Member ScriptMethod Flush {$this.flushed++}
        $script:reviewKey | Add-Member ScriptMethod Close {$this.closed++}
        function Open-RunKeyForWrite {return $script:reviewKey}
        $target=[pscustomobject]@{locator='Guard';before=[pscustomobject]@{value='original'}}
        Set-RunValueState $target ([pscustomobject]@{exists=$false})
        if($script:reviewKey.values.ContainsKey('Guard')){throw 'RUN_NOT_REMOVED'}
        Set-RunValueState $target ([pscustomobject]@{exists=$true;value='original';definition='String'})
        if($script:reviewKey.values.Guard -cne 'original' -or $script:reviewKey.types.Guard -ne 'String'){throw 'RUN_NOT_RESTORED'}
        try{Set-RunValueState $target ([pscustomobject]@{exists=$true;value='overwrite';definition='String'});throw 'CONFLICT_ACCEPTED'}
        catch{if($_.Exception.Message -ne 'UNDO_CONFLICT'){throw}}
        $target.before.value='drift'
        try{Set-RunValueState $target ([pscustomobject]@{exists=$false});throw 'DRIFT_ACCEPTED'}
        catch{if($_.Exception.Message -ne 'OBJECT_DRIFT'){throw}}
        if($script:reviewKey.values.Guard -cne 'original' -or $script:reviewKey.values[''] -ne 'default' -or $script:reviewKey.values.Unrelated -ne 'keep' -or $script:reviewKey.closed -ne 4 -or $script:reviewKey.flushed -ne 2){throw 'RUN_SIDE_EFFECT'}
    }
}
Case 'F02 writer content drift refuses all Undo items without changes' {
    $f=New-Fixture;$p=Plan $f;$r=Apply $f $p;Assert ($r.status -eq 'PASS')
    Text $f.writer '# changed synthetic code'
    $before=TreeHash $f.root;$u=Undo-Quarantine $f.context -Transaction $r.transaction -ApproveUndo
    Assert ($u.exit_code -eq 2);Assert ($u.checks.Count -eq 3)
    Assert (@($u.checks|Where-Object code -eq 'UNDO_WRITER_DRIFT_REVIEW_REQUIRED').Count -eq 3)
    Assert ((TreeHash $f.root) -ceq $before);Assert (-not (Test-Path $f.link))
}
Case 'F02 missing writer refuses Undo and preserves held and Journal' {
    $f=New-Fixture;$p=Plan $f;$r=Apply $f $p
    [IO.File]::Move($f.writer,($f.writer+'.moved'))
    $before=TreeHash $f.root;$u=Undo-Quarantine $f.context -Transaction $r.transaction -ApproveUndo
    Assert (@($u.checks|Where-Object code -eq 'UNDO_WRITER_DRIFT_REVIEW_REQUIRED').Count -eq 3)
    Assert ((TreeHash $f.root) -ceq $before)
}
Case 'F02 writer parent reparse refuses Undo without traversing to execute' {
    $f=New-Fixture;$dir=Join-Path $f.root 'writer';$f.writer=Join-Path $dir 'fake.ps1';Text $f.writer '# synthetic'
    $db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json
    foreach($o in $db.objects){$o.writer=$f.writer};Json (Join-Path $f.root 'objects.json') $db
    $p=Plan $f;$r=Apply $f $p
    [IO.Directory]::Move($dir,($dir+'-held'))
    $null=New-Item -ItemType Junction -Path $dir -Target ($dir+'-held')
    $journal=Join-Path $r.transaction 'journal.jsonl';$before=(Get-FileHash $journal).Hash
    $objects=(Get-FileHash (Join-Path $f.root 'objects.json')).Hash
    $u=Undo-Quarantine $f.context -Transaction $r.transaction -ApproveUndo
    Assert (@($u.checks|Where-Object code -eq 'UNDO_WRITER_DRIFT_REVIEW_REQUIRED').Count -eq 3)
    Assert ((Get-FileHash $journal).Hash -eq $before)
    Assert ((Get-FileHash (Join-Path $f.root 'objects.json')).Hash -eq $objects)
    Assert (Test-Path (Join-Path $r.transaction 'held-2.lnk'));Assert (-not (Test-Path $f.link))
}
Case 'F03 actual exclusive config lock preserves Diagnose and Verify reports' {
    $f=New-Fixture;$path=Join-Path $f.home 'config.toml'
    $lock=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $r=Invoke-RescueDiagnose $f.context -StabilitySeconds 1
        Assert (Test-Path (Join-Path $f.output 'report.json'))
        Assert (@($r.checks|Where-Object {$_.id -eq 'config.stability' -and $_.status -eq 'BLOCKED'}).Count -eq 1)
        Assert (@($r.checks|Where-Object id -eq 'assets.inventory').Count -eq 1)
        $s=New-VerificationSession $f.context
        $v=Complete-Verification $f.context -SessionPath $s.session_path -StabilitySeconds 1
        Assert (@($v.checks|Where-Object {$_.id -eq 'config.session' -and $_.status -eq 'BLOCKED'}).Count -eq 1)
        Assert (@(Get-ChildItem (Split-Path $s.session_path) -Filter 'verification-*.json').Count -eq 1)
        Assert (-not ((Get-Content (Join-Path $f.output 'report.json') -Raw).Contains($f.root)))
    } finally {$lock.Dispose()}
    $v=Complete-Verification $f.context -SessionPath $s.session_path -StabilitySeconds 0
    Assert (@($v.checks|Where-Object {$_.id -eq 'config.session' -and $_.status -eq 'BLOCKED'}).Count -eq 1)
}
Case 'F03 transient sampling exception never becomes stable PASS' {
    $f=New-Fixture
    $r=& $module {
        param($ctx)
        $script:reviewSample=0
        function Get-Stamp {param($Path) $script:reviewSample++;if($script:reviewSample -eq 3){throw [IO.IOException]::new('synthetic read failure')};return 'unchanged'}
        Get-ConfigStability $ctx 2
    } $f.context
    Assert ($r.status -eq 'BLOCKED');Assert ($r.code -eq 'CONFIG_IO_UNAVAILABLE')
}
Case 'F04 explicit and default absent home never PASS selection' {
    foreach($explicit in @($true,$false)){
        $f=New-Fixture;$f.context.home=Join-Path $f.root 'missing-home';$f.context.explicit_home=$explicit
        $r=Invoke-RescueDiagnose $f.context -StabilitySeconds 0
        Assert (@($r.checks|Where-Object {$_.id -eq 'home.selection' -and $_.status -eq 'BLOCKED' -and $_.code -eq 'SELECTED_HOME_ABSENT'}).Count -eq 1)
    }
}
Case 'F04 existing home requires runtime correlation even with explicit path' {
    $f=New-Fixture;$r=Invoke-RescueDiagnose $f.context -StabilitySeconds 0
    Assert (@($r.checks|Where-Object {$_.id -eq 'home.selection' -and $_.status -eq 'NOT_TESTED'}).Count -eq 1)
    Assert (@($r.checks|Where-Object {$_.id -eq 'home.input' -and $_.status -eq 'PASS'}).Count -eq 1)
}
Case 'F05 valid manifest over 2MB is accepted within independent bounds' {
    $f=New-Fixture;$payload=Join-Path $f.root 'payload';Text (Join-Path $payload 'a.txt') 'AAAA'
    $m=Join-Path $f.root 'backup.json'
    Json $m @{schema='rescue-backup-v1';files=@(@{path='a.txt';bytes=4;sha256=(Get-FileHash (Join-Path $payload 'a.txt')).Hash})}
    # Legal whitespace tests the bound without generating thousands of dummy files.
    [IO.File]::AppendAllText($m,(' '* (2MB+1)))
    Assert ((Get-Item $m).Length -gt 2MB)
    Assert ((Test-BackupManifest $m $payload).status -eq 'PASS')
}
Case 'F05 unreadable payload is BLOCKED while actual mismatch is FAIL' {
    $f=New-Fixture;$payload=Join-Path $f.root 'payload';$file=Join-Path $payload 'a.txt';Text $file 'AAAA'
    $m=Join-Path $f.root 'backup.json'
    Json $m @{schema='rescue-backup-v1';files=@(@{path='a.txt';bytes=4;sha256=(Get-FileHash $file).Hash})}
    $lock=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$r=Test-BackupManifest $m $payload;Assert ($r.status -eq 'BLOCKED');Assert ($r.code -eq 'PAYLOAD_VERIFICATION_UNAVAILABLE')}finally{$lock.Dispose()}
    Text $file 'BBBB';$r=Test-BackupManifest $m $payload
    Assert ($r.status -eq 'FAIL');Assert ($r.code -eq 'CONTENT_MISMATCH')
}
Case 'F05 unsupported manifest size is BLOCKED before parsing' {
    $f=New-Fixture;$m=Join-Path $f.root 'large.json'
    $file=[IO.FileStream]::new($m,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
    try{$file.SetLength(32MB+1)}finally{$file.Dispose()}
    $r=Test-BackupManifest $m $f.home
    Assert ($r.status -eq 'BLOCKED');Assert ($r.code -eq 'MANIFEST_SIZE_UNSUPPORTED')
}
Case 'F07 unnamed or unsupported Run names never enter a plan' {
    $f=New-Fixture;$db=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json
    foreach($name in @('',' ',('x'*201),('bad'+[char]10+'name'),'bad\name')){
        $db.objects+=@{kind='run';locator=$name;writer=$f.writer;exists=$true;enabled=$false;value='synthetic';definition='String'}
    }
    Json (Join-Path $f.root 'objects.json') $db
    $before=(Get-FileHash (Join-Path $f.root 'objects.json')).Hash;$p=Plan $f;Assert ($p.target_count -eq 3)
    $state=& $module {param($ctx) try{Get-TargetState $ctx ([pscustomobject]@{kind='run';locator=''})}catch{return $_.Exception.Message}} $f.context
    Assert ($state -eq 'INVALID_RUN_NAME')
    $r=Apply $f $p;Assert ($r.status -eq 'PASS')
    $after=Get-Content (Join-Path $f.root 'objects.json') -Raw|ConvertFrom-Json
    Assert (@($after.objects|Where-Object {$_.kind -eq 'run' -and $_.exists}).Count -eq 5)
    $u=Undo-Quarantine $f.context -Transaction $r.transaction -ApproveUndo;Assert ($u.status -eq 'PASS')
    Assert ((Get-FileHash (Join-Path $f.root 'objects.json')).Hash -eq $before)
}
Case 'F08 same-process B and C declarations never attest either origin or GUI' {
    $f=New-Fixture;$s=New-VerificationSession $f.context
    $b=Invoke-ToolProbe $f.context -SessionPath $s.session_path -Channel B -CanaryMode WorkspaceWrite
    $c=Invoke-ToolProbe $f.context -SessionPath $s.session_path -Channel C -CanaryMode WorkspaceWrite
    $r=Complete-Verification $f.context -SessionPath $s.session_path -EvidencePaths @($b.evidence_path,$c.evidence_path) -StabilitySeconds 1
    Assert ($r.exit_code -eq 3)
    Assert (@($r.checks|Where-Object {$_.id -in @('B.origin','C.origin','A.gui') -and $_.status -eq 'NOT_TESTED'}).Count -eq 3)
    Assert (@($r.checks|Where-Object {$_.id -in @('B.calls','C.calls') -and $_.status -eq 'PASS'}).Count -eq 2)
}
