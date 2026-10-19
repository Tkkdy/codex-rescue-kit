function Get-RepairProcess($Context,[int]$ProcessId) {
    if($ProcessId -le 0){throw 'INVALID_PID'}
    if($Context.fixture){
        $facts=Read-RescueJson (Join-Path $Context.fixture_root 'facts.json')
        $entry=@($facts.processes|Where-Object {$_.pid -eq $ProcessId})|Select-Object -First 1
        if($entry -and $entry.PSObject.Properties['native'] -and $entry.native){
            $w=Assert-Writer $entry.writer
            if(-not (Test-Within $w $Context.fixture_root)){throw 'FIXTURE_ESCAPE'}
            $native=Get-NativeRepairProcess $ProcessId
            if(-not $native){return $null}
            if(-not (Get-WriterMatch $native.command $w)){throw 'FIXTURE_PROCESS_NOT_EXACT_WRITER'}
            # Synthetic owner label is used only after validating the real owner SID.
            if($native.owner -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'OTHER_USER_PROCESS_REFUSED'}
            $native.owner=$Context.identity
            return $native
        }
        return $entry
    }
    return Get-NativeRepairProcess $ProcessId
}
function Get-NativeRepairProcess([int]$ProcessId) {
    $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+$ProcessId) -ErrorAction Stop
    if(-not $p){return $null}
    $owner=Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction Stop
    if($owner.ReturnValue -ne 0 -or -not $p.CommandLine -or -not $p.ExecutablePath){throw 'PROCESS_IDENTITY_UNAVAILABLE'}
    $handleProcess=Get-Process -Id $ProcessId -ErrorAction Stop
    try {
        $null=$handleProcess.Handle
        $created=$handleProcess.StartTime.ToUniversalTime()
        # CIM's microsecond timestamp truncates the native handle's 100ns clock.
        # Bind the full native timestamp and retain exact comparison at the stop operation.
        if([Math]::Abs($created.Ticks-(Convert-RescueUtc $p.CreationDate).Ticks) -gt 10){throw 'PROCESS_IDENTITY_DRIFT'}
    }finally{$handleProcess.Dispose()}
    return [pscustomobject][ordered]@{pid=[int]$p.ProcessId;created=$created.ToString('o');owner=[string]$owner.Sid;executable=(Assert-PlainPath $p.ExecutablePath -MustExist);executable_hash=(Get-ShaFile $p.ExecutablePath);command_hash=(Get-ShaText $p.CommandLine);parent=[int]$p.ParentProcessId;command=[string]$p.CommandLine}
}
function Get-ProcessBinding($P) {
    return [pscustomobject][ordered]@{pid=[int]$P.pid;created=(Convert-RescueUtc $P.created).ToString('o');owner=[string]$P.owner;executable=[string]$P.executable;executable_hash=[string]$P.executable_hash;command_hash=[string]$P.command_hash;parent=[int]$P.parent}
}
function Assert-ProcessBinding($Context,$Expected) {
    $actual=Get-RepairProcess $Context $Expected.pid
    if(-not $actual){return $null}
    if((Get-StateHash (Get-ProcessBinding $actual)) -ne (Get-StateHash (Get-ProcessBinding $Expected))){throw 'PROCESS_IDENTITY_DRIFT'}
    if($Expected.owner -ne $Context.identity){throw 'OTHER_USER_PROCESS_REFUSED'}
    if(-not $Context.fixture){
        $ancestor=$PID;$seen=@{}
        while($ancestor -gt 0 -and -not $seen.ContainsKey($ancestor)){
            if($ancestor -eq $Expected.pid){throw 'SELF_OR_ANCESTOR_PROCESS_REFUSED'}
            $seen[$ancestor]=$true
            $a=Get-CimInstance Win32_Process -Filter ('ProcessId='+$ancestor) -ErrorAction Stop
            if(-not $a){break};$ancestor=[int]$a.ParentProcessId
        }
    }
    return $actual
}
function Stop-RepairWriters($Context,$Plan,[string]$Journal,[string[]]$ApproveForceProcess=@()) {
    foreach($expected in @($Plan.processes)){
        $actual=Assert-ProcessBinding $Context $expected
        if(-not $actual){continue}
        $token=Get-StateHash (Get-ProcessBinding $expected)
        Add-Journal $Journal @{event='PROCESS_STOP_PENDING';binding=$expected;undo='NOT_REVERSIBLE_MEMORY_AND_PROCESS_LIFETIME'}
        $nativeFixture=$false
        if($Context.fixture){$f=Read-RescueJson (Join-Path $Context.fixture_root 'facts.json');$e=@($f.processes|Where-Object pid -eq $expected.pid);$nativeFixture=($e.Count -eq 1 -and $e[0].PSObject.Properties['native'] -and $e[0].native)}
        if($Context.fixture -and -not $nativeFixture){
            if($token -notin $ApproveForceProcess){throw ('FORCE_PROCESS_APPROVAL_REQUIRED:'+ $token)}
            $f=Join-Path $Context.fixture_root 'facts.json';$facts=Read-RescueJson $f
            $facts.processes=@($facts.processes|Where-Object {$_.pid -ne $expected.pid});Write-DurableJson $f $facts -Replace
            $Context.facts=$facts
        } else {
            # Bind an OS process handle before stopping; verify start time to prevent PID reuse.
            $proc=Get-Process -Id $expected.pid -ErrorAction Stop
            try{
                $null=$proc.Handle
                if($proc.StartTime.ToUniversalTime().Ticks -ne (Convert-RescueUtc $expected.created).Ticks){throw 'PROCESS_IDENTITY_DRIFT'}
                $null=Assert-ProcessBinding $Context $expected
                $closed=$proc.CloseMainWindow()
                $exited=$false;if($closed){$exited=$proc.WaitForExit(5000)}else{$proc.Refresh();$exited=$proc.HasExited}
                if(-not $exited){
                    if($token -notin $ApproveForceProcess){throw ('FORCE_PROCESS_APPROVAL_REQUIRED:'+ $token)}
                    $null=Assert-ProcessBinding $Context $expected
                    $proc.Kill();if(-not $proc.WaitForExit(5000)){throw 'PROCESS_EXIT_TIMEOUT'}
                }
            }finally{$proc.Dispose()}
        }
        if($nativeFixture){$f=Join-Path $Context.fixture_root 'facts.json';$facts=Read-RescueJson $f;$facts.processes=@($facts.processes|Where-Object pid -ne $expected.pid);Write-DurableJson $f $facts -Replace;$Context.facts=$facts}
        Add-Journal $Journal @{event='PROCESS_STOP_OBSERVED';binding_hash=$token;undo='NOT_REVERSIBLE_NO_RESTART'}
    }
    Assert-NoRepairProcesses $Context $Plan
}

function Get-RepairListeners($Context,$Processes) {
    if($Context.fixture){return @()}
    $ids=@($Processes|ForEach-Object {[int]$_.pid})
    if(-not $ids.Count){return @()}
    return @(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object {$_.OwningProcess -in $ids}|ForEach-Object {[pscustomobject]@{pid=[int]$_.OwningProcess;port=[int]$_.LocalPort;address_hash=(Get-ShaText $_.LocalAddress)}})
}
