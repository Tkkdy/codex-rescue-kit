# Preview gates: only synthetic files and contexts; never mutate Windows startup objects.
function Invoke-PreviewEntry($ScriptPath,[string]$Mode,[string]$FixturePath='') {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=(Get-Process -Id $PID).Path
    $info.Arguments='-NoProfile -File "'+$ScriptPath+'" -Mode '+$Mode
    if($FixturePath){$info.Arguments+=' -FixtureRoot "'+$FixturePath+'"'}
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try {
        $null=$p.Start();$outTask=$p.StandardOutput.ReadToEndAsync();$errTask=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit(30000)){$p.Kill();throw 'PREVIEW_CHILD_TIMEOUT'}
        return [pscustomobject]@{exit=$p.ExitCode;stdout=$outTask.GetAwaiter().GetResult();stderr=$errTask.GetAwaiter().GetResult()}
    } finally {$p.Dispose()}
}
foreach($mode in @('Quarantine','Undo')) {
    Case ('preview '+$mode+' entry refuses before module import') {
        $f=New-Fixture
        $isolated=Join-Path $f.root 'entry-without-module.ps1'
        [IO.File]::WriteAllBytes($isolated,[IO.File]::ReadAllBytes((Join-Path $repo 'kit/Rescue.ps1')))
        $before=TreeHash $f.root
        $p=Invoke-PreviewEntry $isolated $mode
        Assert ($p.exit -eq 3) 'PREVIEW_ENTRY_EXIT'
        $v=$p.stdout|ConvertFrom-Json
        Assert ($v.status -ceq 'BLOCKED' -and $v.code -ceq 'PREVIEW_REAL_MUTATION_DISABLED' -and $v.exit_code -eq 3) 'PREVIEW_ENTRY_JSON'
        Assert ([string]::IsNullOrWhiteSpace($p.stderr)) 'PREVIEW_ENTRY_STDERR'
        Assert ((TreeHash $f.root) -ceq $before) 'PREVIEW_ENTRY_CHANGED_FIXTURE'
    }
}
Case 'preview direct Quarantine and Undo refuse before context IO' {
    $f=New-Fixture;$before=TreeHash $f.root
    $ctx=[pscustomobject]@{fixture=$false}
    $q=Invoke-QuarantinePlan -Context $ctx -PlanPath (Join-Path $f.root 'absent-plan.json')
    $u=Undo-Quarantine -Context $ctx -Transaction (Join-Path $f.root 'absent-transaction') -ApproveUndo
    foreach($v in @($q,$u)) {
        Assert ($v.status -ceq 'BLOCKED' -and $v.code -ceq 'PREVIEW_REAL_MUTATION_DISABLED' -and $v.exit_code -eq 3) 'PREVIEW_MODULE_GATE'
    }
    Assert ((TreeHash $f.root) -ceq $before) 'PREVIEW_MODULE_CHANGED_FIXTURE'
}
Case 'preview invalid FixtureRoot cannot opt into live mutation' {
    $f=New-Fixture;$before=TreeHash $f.root
    foreach($mode in @('Quarantine','Undo')) {
        $p=Invoke-PreviewEntry (Join-Path $repo 'kit/Rescue.ps1') $mode (Join-Path $f.root 'absent-fixture')
        Assert ($p.exit -eq 4) 'INVALID_FIXTURE_ACCEPTED'
    }
    Assert ((TreeHash $f.root) -ceq $before) 'INVALID_FIXTURE_CHANGED_DATA'
}
