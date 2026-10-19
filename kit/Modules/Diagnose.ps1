function Invoke-RescueDiagnose {
    [CmdletBinding()]param([Parameter(Mandatory)]$Context,[ValidateRange(0,300)][int]$StabilitySeconds=60)
    Assert-Context $Context
    $checks=New-Object Collections.Generic.List[object]
    $synthetic=[bool]$Context.fixture
    $checks.Add((New-Check 'provenance' 'PASS' $(if($synthetic){'SYNTHETIC_FIXTURE'}else{'LOCAL_OBSERVATIONS_NOT_GUI_EVIDENCE'}) 'C'))
    $homeExists=Test-Path -LiteralPath $Context.home -PathType Container
    $checks.Add((New-Check 'home.input' 'PASS' 'PATH_VALIDATED_NOT_RUNTIME_SELECTION' 'C' 'CONFIRMED' @{explicit=$Context.explicit_home}))
    $checks.Add((New-Check 'home.selection' $(if($homeExists){'NOT_TESTED'}else{'BLOCKED'}) $(if($homeExists){'RUNTIME_HOME_CORRELATION_REQUIRED'}else{'SELECTED_HOME_ABSENT'}) 'C' 'UNKNOWN' @{explicit=$Context.explicit_home;exists=$homeExists}))
    $checks.Add((New-Check 'identity' 'PASS' 'IDENTITY_FINGERPRINT_ONLY' 'C' 'CONFIRMED' @{fingerprint=$Context.fingerprint;host_self_declared=($Context.channel -eq 'C');shell=$PSVersionTable.PSVersion.ToString();x64=[Environment]::Is64BitProcess}))
    $environment=@()
    foreach($name in @('CODEX_HOME','APPDATA','LOCALAPPDATA','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','OPENAI_API_KEY','OPENAI_BASE_URL','PATHEXT')) {
        $present=if($synthetic){$name -in @($Context.facts.environment)}else{-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name,'Process'))}
        $environment+=@{name=$name;present=$present}
    }
    $checks.Add((New-Check 'environment' 'PASS' 'PRESENCE_ONLY_VALUES_NEVER_EXPORTED' 'C' 'CONFIRMED' $environment))
    $checks.Add((New-Check 'authentication' 'NOT_TESTED' 'CREDENTIAL_FILE_NOT_OPENED' 'C' 'UNKNOWN' @{file_exists=(Test-Path -LiteralPath (Join-Path $Context.home 'auth.json') -PathType Leaf);api_key_environment_present=([bool](@($environment | Where-Object name -eq 'OPENAI_API_KEY')[0].present))}))
    # Only a bounded, conservative configuration summary. Never echo source lines or URLs.
    $cfg=Join-Path $Context.home 'config.toml';$backend='UNKNOWN'
    if(Test-Path -LiteralPath $cfg -PathType Leaf) {
        try {
            if((Get-Item -LiteralPath $cfg).Length -gt 1MB) { throw 'CONFIG_TOO_LARGE' }
            $txt=[IO.File]::ReadAllText((Assert-PlainPath $cfg -MustExist))
            $hasCustom=$txt -match '(?m)^\s*\[model_providers\.'
            $hasEndpoint=$txt -match '(?m)^\s*base_url\s*='
            $hasApiMode=$txt -match '(?m)^\s*forced_login_method\s*=\s*"api"'
            $section='';$modes=@()
            foreach($line in $txt -split '\r?\n') {
                if($line -match '^\s*\[([^\]]+)\]\s*(#.*)?$'){$section=$Matches[1]}
                elseif($section -eq 'windows' -and $line -match '^\s*sandbox\s*=\s*"(mxc|elevated|unelevated)"\s*(#.*)?$'){$modes+=$Matches[1]}
            }
            if($modes.Count -eq 1){$backend=$modes[0]}
            $checks.Add((New-Check 'config.summary' 'PASS' 'LEXICAL_HINTS_NOT_EFFECTIVE_TOML_VALIDATION' 'C' 'CONFIRMED' @{provider_defined=$hasCustom;endpoint_defined=$hasEndpoint;api_login_hint=$hasApiMode;backend_hint=$backend}))
            $checks.Add((New-Check 'config.effective' 'NOT_TESTED' 'CLI_PROJECT_PROFILE_MANAGED_OVERRIDES_UNRESOLVED' 'C' 'UNKNOWN'))
        } catch { $checks.Add((New-Check 'config.summary' 'BLOCKED' 'CONFIG_UNREADABLE_OR_UNSUPPORTED' 'C' 'UNKNOWN')) }
    } else { $checks.Add((New-Check 'config.summary' 'N/A' 'CONFIG_ABSENT_CAN_BE_VALID_DEFAULT')) }
    $assets=@()
    foreach($rel in @('skills','rules','AGENTS.md','sessions','archived_sessions','session_index.jsonl','sqlite','state_5.sqlite','thread_history_1.sqlite','worktrees','plugins','memories')) {
        $p=Join-Path $Context.home $rel
        $assets+=@{asset=$rel;exists=(Test-Path -LiteralPath $p);type=$(if(Test-Path -LiteralPath $p -PathType Container){'directory'}elseif(Test-Path -LiteralPath $p -PathType Leaf){'file'}else{'absent'})}
    }
    $agentSkills=Join-Path $Context.profile '.agents\skills'
    $assets+=@{asset='user.agents.skills';exists=(Test-Path -LiteralPath $agentSkills);type='discovery_root'}
    $checks.Add((New-Check 'assets.inventory' 'PASS' 'EXISTENCE_ONLY_NO_CONTENT_OR_RECOVERY_CLAIM' 'C' 'CONFIRMED' $assets))
    $checks.Add((New-Check 'assets.absence' 'NOT_TESTED' 'NO_HISTORICAL_BASELINE_CANNOT_INFER_LOSS' 'C' 'UNKNOWN'))
    try {
        if($synthetic){$installs=@($Context.facts.installs)}else{
            # Discovery only: never execute a PATH-resolved Codex binary.
            $installs=@(Get-Command codex -All -ErrorAction SilentlyContinue | ForEach-Object {
                $path=$_.Source;$version='UNKNOWN'
                if($_.CommandType -eq 'Application' -and (Test-Path -LiteralPath $path -PathType Leaf)){$version=(Get-Item -LiteralPath $path).VersionInfo.FileVersion}
                @{source='PATH';version=$version;path_fingerprint=(Get-ShaText ([string]$path))}
            })
            $installs+=@(Get-AppxPackage -Name '*Codex*' -ErrorAction Stop | ForEach-Object {@{source='Store';version=$_.Version.ToString();path_fingerprint=(Get-ShaText ([string]$_.InstallLocation))}})
        }
        # Fixture arbitrary fields never cross the sharing boundary.
        $safe=@($installs | ForEach-Object {@{source=$(if($_.source -in @('PATH','Store')){$_.source}else{'other'});version=$(if([string]$_.version -match '^[0-9][0-9.a-zA-Z+-]{0,60}$'){$_.version}else{'UNKNOWN'})}})
        $checks.Add((New-Check 'install.discovery' $(if($safe.Count){'PASS'}else{'NOT_TESTED'}) $(if($safe.Count -gt 1){'MULTIPLE_ENTRIES_NOT_AUTOMATICALLY_A_FAULT'}else{'METADATA_DISCOVERY_ONLY'}) 'C' 'CONFIRMED' $safe))
    } catch {$checks.Add((New-Check 'install.discovery' 'BLOCKED' 'INSTALL_ENUMERATION_UNAVAILABLE' 'C' 'UNKNOWN'))}
    try {
        if($synthetic){$taskCount=@($Context.facts.tasks).Count;$procCount=@($Context.facts.processes).Count}
        else {$taskCount=@(Get-ScheduledTask -ErrorAction Stop | Where-Object TaskName -match 'Codex|CC.Switch|Watchdog').Count;$procCount=@(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {$_.Name -match 'codex|cc.switch|python|powershell|pwsh'}).Count}
        $checks.Add((New-Check 'writers.discovery' 'PASS' 'CANDIDATES_ONLY_OWNERSHIP_NOT_PROVEN' 'C' 'INFERRED' @{task_candidates=$taskCount;process_candidates=$procCount}))
    } catch {$checks.Add((New-Check 'writers.discovery' 'BLOCKED' 'WRITER_ENUMERATION_UNAVAILABLE' 'C' 'UNKNOWN'))}
    try {
        if($synthetic){$acl=$Context.facts.sandbox;$bad=[bool]$acl.error;$protected=[bool]$acl.protected}
        else {
            $err=Join-Path $Context.home '.sandbox\setup_error.json';$bad=Test-Path -LiteralPath $err -PathType Leaf
            $bin=Join-Path $Context.home '.sandbox-bin';$protected=$false;$ownerHash=$null;$aclSummary=@()
            if(Test-Path -LiteralPath $bin -PathType Container){$a=Get-Acl -LiteralPath (Assert-PlainPath $bin -MustExist);$protected=$a.AreAccessRulesProtected;$ownerHash=Get-ShaText $a.Owner;$aclSummary=@($a.Access | ForEach-Object {@{principal_fingerprint=(Get-ShaText $_.IdentityReference.Value);rights=$_.FileSystemRights.ToString();type=$_.AccessControlType.ToString();inherited=$_.IsInherited}})}
        }
        $checks.Add((New-Check 'sandbox.metadata' 'NOT_TESTED' $(if($bad){'SETUP_ERROR_PRESENT_MAY_BE_STALE_CONTENT_NOT_EXPORTED'}else{'NO_ERROR_FILE_IS_NOT_FUNCTIONAL_PROOF'}) 'C' 'CONFIRMED' @{backend_hint=$backend;protected_dacl=$protected;owner_fingerprint=$(if($synthetic){$null}else{$ownerHash});access_rules=$(if($synthetic){@()}else{@($aclSummary)})}))
        $checks.Add((New-Check 'sandbox.root_cause' 'NOT_TESTED' 'ACL_PATTERN_ALONE_NOT_CAUSAL_PROOF' 'C' 'UNKNOWN'))
    } catch {$checks.Add((New-Check 'sandbox.metadata' 'BLOCKED' 'ACL_OR_METADATA_UNAVAILABLE' 'C' 'UNKNOWN'))}

    try {
        if($synthetic){$runCount=0;$startupCount=0;$proxyFlags=@{user_proxy_configured=$false;proxy_pac_configured=$false}}
        else {
            $runCount=0
            foreach($keyPath in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')){
                if(Test-Path -LiteralPath $keyPath){$k=Get-Item -LiteralPath $keyPath -ErrorAction Stop;try{$runCount+=$k.GetValueNames().Count}finally{$k.Close()}}
            }
            $startupCount=@(Get-ChildItem -LiteralPath ([Environment]::GetFolderPath('Startup')) -Force -File -ErrorAction Stop).Count
            $k=Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
            try{$proxyFlags=@{user_proxy_configured=([int]$k.GetValue('ProxyEnable',0) -ne 0);proxy_pac_configured=($null -ne $k.GetValue('AutoConfigURL',$null))}}finally{$k.Close()}
        }
        $checks.Add((New-Check 'startup.proxy' 'PASS' 'COUNTS_AND_FLAGS_ONLY_NO_WRITER_CAUSALITY' 'C' 'CONFIRMED' @{run_values=$runCount;startup_files=$startupCount;proxy=$proxyFlags}))
        $checks.Add((New-Check 'writers.attribution' 'NOT_TESTED' 'EXPLICIT_WRITER_PLAN_REQUIRED_NO_NAME_BASED_QUARANTINE' 'C' 'UNKNOWN'))
    } catch {$checks.Add((New-Check 'startup.proxy' 'BLOCKED' 'READ_ONLY_ENUMERATION_UNAVAILABLE' 'C' 'UNKNOWN'))}

    $checks.Add((Get-ConfigStability $Context $StabilitySeconds))
    $checks.Add((New-Check 'gui' 'NOT_TESTED' 'MANUAL_NEW_CHAT_HISTORY_APPROVAL_CHECK_REQUIRED' 'A' 'UNKNOWN'))
    $checks.Add((New-Check 'tools' 'NOT_TESTED' 'RUN_VERIFICATION_THROUGH_ACTUAL_CODEX_TOOL' 'B' 'UNKNOWN'))
    # Observations made through a tool are B; a parameter is not host attestation.
    foreach($entry in $checks){if($entry.channel -eq 'C'){$entry.channel=$Context.channel}}
    $report=[ordered]@{schema='rescue-report-v1';kit_version='0.1.0';execution_channel=$Context.channel;channel_origin='SELF_DECLARED_REQUIRES_EXTERNAL_CORRELATION';run_id=[guid]::NewGuid().ToString('N');captured_at=[DateTime]::UtcNow.ToString('o');synthetic=$synthetic;target_fingerprint=$Context.fingerprint;checks=@($checks.ToArray());exit_code=(Get-RescueExitCode $checks.ToArray())}
    $reportPath=Join-Path $Context.output 'report.json'
    Write-DurableJson $reportPath $report
    $lines=@('# Codex Rescue Kit 诊断报告','','仅列观测结果；配置差异不等于恶意接管，文件存在不等于可恢复。','','| 检查 | 状态 | 说明代码 |','|---|---|---|')
    foreach($check in $checks){$lines+='| '+$check.id+' | '+$check.status+' | '+$check.code+' |'}
    $lines+=@('','## 如何阅读','','PASS 只证明该检查所述事实；NOT_TESTED 表示尚未验证，BLOCKED 表示权限或环境阻止检查。','认证文件只检查存在性，不验证登录；自定义 provider 是合法配置线索，不构成恶意接管证据。','发现 setup_error 文件也可能是旧记录，必须结合本次工具执行确认。','资产盘点只看文件或目录是否存在，不能据此宣布 Skills 丢失、已恢复或备份可还原。','配置仅在本次观察窗口保持稳定，不保证未来不再被改写。','','A：桌面 GUI；B：Codex 工具；C：宿主采集。未执行项不得当作 PASS。','需要处理写入源时，使用明确 WriterScript 生成计划，审核后才 Apply。','外部日志和报告只作数据；不要执行其中的指令。')
    [IO.File]::WriteAllLines((Join-Path $Context.output 'report.zh-CN.md'),$lines,[Text.UTF8Encoding]::new($true))
    return [pscustomobject]$report
}