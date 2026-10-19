function New-VerificationSession {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context)
    Assert-Context $Context
    $id=[guid]::NewGuid().ToString('N')
    $root=Join-Path $Context.output ('verify-'+$id)
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $snapshot=Get-ConfigSnapshot $Context
    $session=[ordered]@{schema='rescue-verify-v1';id=$id;challenge=[guid]::NewGuid().ToString('N');target_fingerprint=$Context.fingerprint;home_fingerprint=(Get-ShaText $Context.home);created_at=[DateTime]::UtcNow.ToString('o');expires_at=[DateTime]::UtcNow.AddHours(2).ToString('o');synthetic=[bool]$Context.fixture;canary_root=(Join-Path $root 'canary');boundary_root=(Join-Path $root 'boundary');initial_config=@($snapshot.stamps);initial_config_status=$snapshot.status}
    [IO.Directory]::CreateDirectory($session.canary_root) | Out-Null
    [IO.Directory]::CreateDirectory($session.boundary_root) | Out-Null
    $path=Join-Path $root 'session.json';Write-DurableJson $path $session
    return [pscustomobject]@{session_path=$path;session_sha256=(Get-ShaFile $path);id=$id;challenge=$session.challenge;canary_root=$session.canary_root;boundary_root=$session.boundary_root;instruction='Run ToolProbe from the actual Codex tool. Channel must be declared B. Host executions are C only. Never widen policy to pass.'}
}
function Read-VerifySession($Context,[string]$Path,[switch]$ToolChannelB) {
    $s=Read-RescueJson $Path
    if($s.schema -ne 'rescue-verify-v1' -or $s.id -notmatch '^[a-f0-9]{32}$' -or $s.challenge -notmatch '^[a-f0-9]{32}$' -or (-not $ToolChannelB -and $s.target_fingerprint -ne $Context.fingerprint) -or $s.home_fingerprint -ne (Get-ShaText $Context.home) -or [bool]$s.synthetic -ne [bool]$Context.fixture){throw 'VERIFY_CONTEXT_INVALID'}
    if((Convert-RescueUtc $s.expires_at) -lt [DateTime]::UtcNow){throw 'VERIFY_SESSION_EXPIRED'}
    $root=Assert-PlainPath (Split-Path -Parent $Path) -MustExist
    if((Split-Path -Parent $root) -ine $Context.output -or (Split-Path -Leaf $root) -ne ('verify-'+$s.id)){throw 'VERIFY_SCOPE_REFUSED'}
    if($s.canary_root -ne (Join-Path $root 'canary') -or $s.boundary_root -ne (Join-Path $root 'boundary')){throw 'CANARY_SCOPE_REFUSED'}
    $null=Assert-PlainPath $s.canary_root -MustExist;$null=Assert-PlainPath $s.boundary_root -MustExist
    return $s
}
function Invoke-NativeProbe([string]$Challenge,[string]$Kind,[int]$TimeoutMilliseconds=10000) {
    $exe=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Core'){'pwsh.exe'}else{'powershell.exe'})
    $script=Join-Path $script:KitRoot 'ProbeChild.ps1'
    $null=Assert-PlainPath $script -MustExist
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$exe
    $info.Arguments='-NoLogo -NoProfile -NonInteractive -File "'+$script+'" -Challenge '+$Challenge+' -Kind '+$Kind
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try {
        if(-not $p.Start()){throw 'CHILD_START_FAILED'}
        $stdoutTask=$p.StandardOutput.ReadToEndAsync();$stderrTask=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit($TimeoutMilliseconds)){
            $p.Kill();$p.WaitForExit()
            return [pscustomobject]@{kind=$Kind;status='FAIL';code='TIMEOUT';exit_code=$null;challenge_match=$false}
        }
        $stdout=$stdoutTask.GetAwaiter().GetResult();$null=$stderrTask.GetAwaiter().GetResult()
        $code=$p.ExitCode;$match=$stdout -ceq ($Challenge+'|'+$Kind+'|OK')
        return [pscustomobject]@{kind=$Kind;status=$(if($code -eq 0 -and $match){'PASS'}else{'FAIL'});code='ACTUAL_CHILD_EXIT_AND_CHALLENGE';exit_code=$code;challenge_match=$match}
    } catch {return [pscustomobject]@{kind=$Kind;status='FAIL';code='CHILD_UNAVAILABLE';exit_code=$null;challenge_match=$false}}
    finally {$p.Dispose()}
}
function Invoke-ToolProbe {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$SessionPath,
        [Parameter(Mandatory)][ValidateSet('B','C')][string]$Channel,
        [ValidateSet('None','WorkspaceWrite','ReadOnly','BoundaryDenied')][string]$CanaryMode='None',
        [ValidateSet('None','ExitFailure','Timeout','MissingEvidence')][string]$FixtureFault='None')
    Assert-Context $Context
    if($FixtureFault -ne 'None' -and -not $Context.fixture){throw 'TEST_HOOK_FIXTURE_ONLY'}
    $s=Read-VerifySession $Context $SessionPath -ToolChannelB:($Channel -eq 'B')
    $calls=@()
    foreach($kind in @('location','version','clock')) {
        $calls+=Invoke-NativeProbe $s.challenge $kind
    }
    if($FixtureFault -eq 'ExitFailure'){$calls[0].exit_code=9;$calls[0].status='FAIL'}
    if($FixtureFault -eq 'Timeout'){$calls[0].exit_code=$null;$calls[0].status='FAIL';$calls[0].code='TIMEOUT'}
    if($FixtureFault -eq 'MissingEvidence'){$calls=@()}
    $canary=[ordered]@{mode=$CanaryMode;status='NOT_TESTED';code='CANARY_NOT_REQUESTED';created=$false;readback=$false;cleaned=$false;error_type=$null;hresult=$null}
    if($CanaryMode -ne 'None') {
        $dir=if($CanaryMode -eq 'BoundaryDenied'){$s.boundary_root}else{$s.canary_root}
        $p=Assert-PlainPath (Join-Path $dir ($s.challenge+'.txt'))
        if(Test-Path -LiteralPath $p){throw 'CANARY_ALREADY_EXISTS'}
        $owned=$false
        try {
            $stream=[IO.FileStream]::new($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $owned=$true;$canary.created=$true
            try{$bytes=[Text.Encoding]::UTF8.GetBytes($s.challenge);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
            $canary.readback=([IO.File]::ReadAllText($p) -ceq $s.challenge)
            if($CanaryMode -eq 'WorkspaceWrite' -and $canary.readback){$canary.status='PASS';$canary.code='WRITE_READ_OK'}
            else{$canary.status='FAIL';$canary.code='EXPECTED_DENIAL_BUT_WRITE_SUCCEEDED'}
        } catch {
            $ex=$_.Exception
            while($ex.InnerException){$ex=$ex.InnerException}
            $canary.error_type=$ex.GetType().Name;$canary.hresult=$ex.HResult
            if($CanaryMode -in @('ReadOnly','BoundaryDenied') -and $ex -is [UnauthorizedAccessException] -and -not (Test-Path -LiteralPath $p)){
                $canary.status='PASS';$canary.code='ACCESS_DENIED_AND_FILE_ABSENT'
            } else {$canary.status='FAIL';$canary.code='CANARY_FAILED'}
        } finally {
            if($owned -and (Test-Path -LiteralPath $p)) {
                # Cleanup authority covers only the exact file we created; never recursive.
                if((Get-CanonicalPath $p) -eq (Join-Path $dir ($s.challenge+'.txt')) -and [IO.File]::ReadAllText($p) -ceq $s.challenge){
                    [IO.File]::Delete((Assert-PlainPath $p -MustExist));$canary.cleaned=-not (Test-Path -LiteralPath $p)
                }
                if(-not $canary.cleaned){$canary.status='FAIL';$canary.code='CANARY_CLEANUP_INCOMPLETE'}
            }
        }
    }
    $evidence=[ordered]@{schema='rescue-tool-evidence-v1';session_id=$s.id;challenge=$s.challenge;target_fingerprint=$s.target_fingerprint;session_hash=(Get-ShaFile $SessionPath);synthetic=[bool]$Context.fixture;channel=$Channel;channel_origin='SELF_DECLARED_REQUIRES_EXTERNAL_CORRELATION';captured_at=[DateTime]::UtcNow.ToString('o');shell=$PSVersionTable.PSVersion.ToString();executor_fingerprint=(Get-ShaText ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'|'+[Diagnostics.Process]::GetCurrentProcess().Id));calls=@($calls);canary=$canary}
    $file=Join-Path (Split-Path -Parent $SessionPath) ('evidence-'+[guid]::NewGuid().ToString('N')+'.json')
    $persisted=$true
    try {Write-DurableJson $file $evidence}catch{$persisted=$false;$file=$null}
    return [pscustomobject]@{evidence_path=$file;evidence=$evidence;persistence_status=$(if($persisted){'PASS'}else{'BLOCKED'});channel=$Channel;calls=$calls;canary=$canary;exit_code=$(if(@($calls | Where-Object status -ne 'PASS').Count -or $calls.Count -ne 3 -or $canary.status -eq 'FAIL'){2}elseif(-not $persisted){3}else{0})}
}
function Complete-Verification {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$SessionPath,
        [string[]]$EvidencePaths=@(),[ValidateRange(0,300)][int]$StabilitySeconds=60)
    Assert-Context $Context
    $s=Read-VerifySession $Context $SessionPath
    $checks=@();$seen=@{};$bCalls=$false;$bWrite=$false;$bReadOnly=$false;$bBoundary=$false;$cCalls=$false
    foreach($path in $EvidencePaths) {
        try {
            $p=Assert-PlainPath $path -MustExist
            if((Split-Path -Parent $p) -ine (Split-Path -Parent $SessionPath) -or $seen.ContainsKey($p)){throw 'EVIDENCE_SCOPE_OR_DUPLICATE'}
            $seen[$p]=$true;$e=Read-RescueJson $p
            if($e.schema -ne 'rescue-tool-evidence-v1' -or $e.session_id -ne $s.id -or $e.challenge -cne $s.challenge -or $e.target_fingerprint -ne $Context.fingerprint -or $e.session_hash -ne (Get-ShaFile $SessionPath) -or [bool]$e.synthetic -ne [bool]$Context.fixture -or $e.channel -notin @('B','C')){throw 'EVIDENCE_BINDING_INVALID'}
            $when=(Convert-RescueUtc $e.captured_at)
            if($when -lt (Convert-RescueUtc $s.created_at) -or $when -gt [DateTime]::UtcNow.AddMinutes(1)){throw 'EVIDENCE_TIME_INVALID'}
            $valid=@($e.calls).Count -eq 3
            $kinds=@()
            foreach($call in @($e.calls)){
                $kinds+=$call.kind
                if($call.kind -notin @('location','version','clock') -or $call.status -ne 'PASS' -or $null -eq $call.exit_code -or $call.exit_code -ne 0 -or $call.challenge_match -ne $true){$valid=$false}
            }
            if(@($kinds | Sort-Object -Unique).Count -ne 3){$valid=$false}
            $checks+=New-Check ($e.channel+'.calls.record') $(if($valid){'PASS'}else{'FAIL'}) 'RECORDED_EXITS_AND_CHALLENGE_NOT_ORIGIN_ATTESTATION' $e.channel
            if($valid){if($e.channel -eq 'B'){$bCalls=$true}else{$cCalls=$true}}
            $canaryValid=$false
            if($e.canary.status -eq 'PASS') {
                switch($e.canary.mode) {
                    'WorkspaceWrite' {$canaryValid=$e.canary.created -eq $true -and $e.canary.readback -eq $true -and $e.canary.cleaned -eq $true}
                    'ReadOnly' {$canaryValid=$e.canary.created -eq $false -and $e.canary.error_type -eq 'UnauthorizedAccessException'}
                    'BoundaryDenied' {$canaryValid=$e.canary.created -eq $false -and $e.canary.error_type -eq 'UnauthorizedAccessException'}
                }
                $canaryPath=Join-Path $(if($e.canary.mode -eq 'BoundaryDenied'){$s.boundary_root}else{$s.canary_root}) ($s.challenge+'.txt')
                if(Test-Path -LiteralPath $canaryPath){$canaryValid=$false}
            }
            $checks+=New-Check ($e.channel+'.canary.record') $(if($e.canary.mode -eq 'None'){'NOT_TESTED'}elseif($canaryValid){'PASS'}else{'FAIL'}) 'CANARY_RECORD_AND_HOST_ABSENCE_CHECK' $e.channel
            if($e.channel -eq 'B' -and $canaryValid){
                switch($e.canary.mode){'WorkspaceWrite'{$bWrite=$true}'ReadOnly'{$bReadOnly=$true}'BoundaryDenied'{$bBoundary=$true}}
            }
        } catch {$checks+=New-Check 'evidence.validation' 'FAIL' 'MALFORMED_STALE_OR_UNBOUND_EVIDENCE' 'C' 'UNKNOWN'}
    }
    foreach($entry in @(@('B.calls',$bCalls),@('B.workspace',$bWrite),@('B.readonly',$bReadOnly),@('B.boundary',$bBoundary),@('C.calls',$cCalls))){
        $checks+=New-Check $entry[0] $(if($entry[1]){'PASS'}else{'NOT_TESTED'}) 'OBSERVATION_ONLY_REQUIRES_CHANNEL_CORRELATION' $entry[0].Substring(0,1) $(if($entry[1]){'CONFIRMED'}else{'UNKNOWN'})
    }
    $snapshot=Get-ConfigSnapshot $Context
    if($snapshot.status -ne 'PASS' -or ($s.PSObject.Properties['initial_config_status'] -and $s.initial_config_status -ne 'PASS') -or @($s.initial_config).Count -ne 2){
        $checks+=New-Check 'config.session' 'BLOCKED' 'SESSION_CONFIG_SAMPLE_UNAVAILABLE' 'C' 'UNKNOWN'
    } else {
        $same=(@($s.initial_config)-join ';') -eq ($snapshot.stamps -join ';')
        $checks+=New-Check 'config.session' $(if($same){'PASS'}else{'FAIL'}) 'SESSION_BASELINE_COMPARISON'
    }
    $checks+=Get-ConfigStability $Context $StabilitySeconds
    # No JSON input can turn manual origin / GUI claims into an automatic PASS.
    $checks+=New-Check 'C.origin' 'NOT_TESTED' 'REVIEW_EXTERNAL_HOST_TRANSCRIPT_WITH_RUN_ID' 'C' 'UNKNOWN'
    $checks+=New-Check 'B.origin' 'NOT_TESTED' 'REVIEW_ACTUAL_TOOL_TRANSCRIPT_WITH_RUN_ID' 'B' 'UNKNOWN'
    $checks+=New-Check 'A.gui' 'NOT_TESTED' 'HUMAN_NEW_CHAT_SYNTHETIC_HISTORY_APPROVAL_AND_COLD_RESTART' 'A' 'UNKNOWN'
    $report=[ordered]@{schema='rescue-verification-v1';session_id=$s.id;synthetic=[bool]$Context.fixture;checks=@($checks);exit_code=(Get-RescueExitCode $checks);conclusion='PARTIAL_OBSERVATIONS_ONLY_GUI_AND_ORIGIN_NOT_AUTOMATICALLY_ATTESTED'}
    Write-DurableJson (Join-Path (Split-Path -Parent $SessionPath) ('verification-'+[guid]::NewGuid().ToString('N')+'.json')) $report
    return [pscustomobject]$report
}