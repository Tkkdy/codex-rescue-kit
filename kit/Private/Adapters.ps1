function Test-RunValueName([string]$Name) {
    return -not [string]::IsNullOrWhiteSpace($Name) -and $Name.Length -le 200 -and $Name -notmatch '[\\\x00-\x1f]'
}
function Open-RunKeyForWrite {
    # Fixed current-user, 64-bit Run key only. Never create missing keys or follow a PSDrive.
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
    try { $key=$hive.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run',$true) } finally { $hive.Dispose() }
    if($null -eq $key){throw 'RUN_KEY_UNAVAILABLE'}
    return $key
}
function Set-RunValueState($Target,$State) {
    if(-not (Test-RunValueName $Target.locator)){throw 'INVALID_RUN_NAME'}
    $key=Open-RunKeyForWrite
    try {
        $exists=$Target.locator -in $key.GetValueNames()
        if($State.exists) {
            if($exists){throw 'UNDO_CONFLICT'}
            if($State.definition -ne 'String'){throw 'UNSUPPORTED_REGISTRY_TYPE'}
            $key.SetValue($Target.locator,[string]$State.value,[Microsoft.Win32.RegistryValueKind]::String)
        } else {
            if(-not $exists -or $key.GetValueKind($Target.locator).ToString() -ne 'String' -or
                [string]$key.GetValue($Target.locator,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne [string]$Target.before.value){throw 'OBJECT_DRIFT'}
            $key.DeleteValue($Target.locator,$true)
        }
        $key.Flush()
    } finally { $key.Close() }
}
function Get-WriterMatch([string]$Command,[string]$Writer) {
    # Deliberately narrow grammar: no -Command, shell operators, extra script arguments or expansion.
    if($Command -match '[\r\n\x00&|<>\x60%$]') { return $false }
    $parts=@([regex]::Matches($Command,'(?:"[^"]*"|''[^'']*''|[^\s]+)') | ForEach-Object { $_.Value.Trim('"',"'") })
    if($parts.Count -eq 1) {
        try { return (Get-CanonicalPath $parts[0]).Equals($Writer,[StringComparison]::OrdinalIgnoreCase) } catch { return $false }
    }
    if($parts.Count -lt 2) { return $false }
    $exe=[IO.Path]::GetFileName($parts[0])
    $args=@($parts | Select-Object -Skip 1)
    if($exe -match '^(?i:powershell|pwsh)(\.exe)?$') {
        $allowed=@('-NoProfile','-NonInteractive','-NoLogo')
        $i=0; while($i -lt $args.Count -and $args[$i] -in $allowed) { $i++ }
        if($i -ne ($args.Count-2) -or $args[$i] -ine '-File') { return $false }
        $candidate=$args[$i+1]
    } elseif($exe -match '^(?i:python|pythonw|wscript|cscript)(\.exe)?$' -and $args.Count -eq 1) { $candidate=$args[0] } else { return $false }
    try { return (Get-CanonicalPath $candidate).Equals($Writer,[StringComparison]::OrdinalIgnoreCase) } catch { return $false }
}
function Get-WriterCandidates($Context,[string]$Writer) {
    Assert-Context $Context
    if($Context.fixture) {
        $db=Read-RescueJson (Join-Path $Context.fixture_root 'objects.json')
        foreach($o in $db.objects) {
            if($o.writer -eq $Writer -and $o.kind -in @('task','run','startup') -and ($o.kind -ne 'run' -or (Test-RunValueName $o.locator))) { $o }
        }
        return
    }
    # Errors are blockers, never equivalent to an empty list.
    $tasks=@(Get-ScheduledTask -ErrorAction Stop)
    foreach($t in $tasks) {
        $actions=@($t.Actions)
        if($actions.Count -ne 1) { continue }
        $cmd='"'+$actions[0].Execute+'" '+$actions[0].Arguments
        if(Get-WriterMatch $cmd $Writer) {
            # Never claim ownership of another principal's task.
            $principal=[string]$t.Principal.UserId
            $me=[Security.Principal.WindowsIdentity]::GetCurrent()
            if($principal -notin @($me.Name,$me.User.Value)) { continue }
            [pscustomobject]@{kind='task';locator=($t.TaskPath+$t.TaskName);writer=$Writer}
        }
    }
    $run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if(Test-Path $run) {
        $key=Get-Item -LiteralPath $run -ErrorAction Stop
        try { foreach($name in $key.GetValueNames()) {
            if(-not (Test-RunValueName $name) -or $key.GetValueKind($name).ToString() -ne 'String') { continue }
            $value=[string]$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if(Get-WriterMatch $value $Writer) { [pscustomobject]@{kind='run';locator=$name;writer=$Writer} }
        }} finally { $key.Close() }
    }
    $startup=[Environment]::GetFolderPath('Startup')
    foreach($link in @(Get-ChildItem -LiteralPath $startup -Filter '*.lnk' -File -ErrorAction Stop)) {
        $null=Assert-PlainPath $link.FullName -MustExist
        $shell=New-Object -ComObject WScript.Shell
        try {
            $shortcut=$shell.CreateShortcut($link.FullName)
            $cmd='"'+$shortcut.TargetPath+'" '+$shortcut.Arguments
            if(Get-WriterMatch $cmd $Writer) { [pscustomobject]@{kind='startup';locator=$link.FullName;writer=$Writer} }
        } finally { if($null -ne $shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)} }
    }
}
function Get-TargetState($Context,$Target) {
    Assert-Context $Context
    if($Target.kind -eq 'run' -and -not (Test-RunValueName $Target.locator)){throw 'INVALID_RUN_NAME'}
    if($Context.fixture -and $Target.kind -ne 'startup') {
        $db=Read-RescueJson (Join-Path $Context.fixture_root 'objects.json')
        $o=@($db.objects | Where-Object { $_.kind -eq $Target.kind -and $_.locator -eq $Target.locator })
        if($o.Count -ne 1) { throw 'OBJECT_MISSING_OR_AMBIGUOUS' }
        return [pscustomobject]@{exists=[bool]$o[0].exists;enabled=[bool]$o[0].enabled;value=[string]$o[0].value;kind=[string]$o[0].kind;locator=[string]$o[0].locator;definition=[string]$o[0].definition}
    }
    switch($Target.kind) {
        'task' {
            if($Target.locator -match '[*?\[\]]'){throw 'TASK_WILDCARD_REFUSED'}
            $split=$Target.locator.LastIndexOf('\')
            if($split -lt 0) { throw 'INVALID_TASK' }
            $taskPath=$Target.locator.Substring(0,$split+1);$taskName=$Target.locator.Substring($split+1)
            $t=Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
            # State describes running/queued instances, not the persisted enable setting.
            if(-not $t.PSObject.Properties['Settings'] -or $null -eq $t.Settings -or
                -not $t.Settings.PSObject.Properties['Enabled'] -or $t.Settings.Enabled -isnot [bool]){throw 'TASK_ENABLED_UNAVAILABLE'}
            $configuredEnabled=$t.Settings.Enabled
            [xml]$xml=Export-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop
            foreach($n in @($xml.SelectNodes('/*[local-name()="Task"]/*[local-name()="Settings"]/*[local-name()="Enabled"]'))){$null=$n.ParentNode.RemoveChild($n)}
            $definition=Get-ShaText $xml.OuterXml
            return [pscustomobject]@{exists=$true;enabled=$configuredEnabled;value='';kind='task';locator=$Target.locator;definition=$definition}
        }
        'run' {
            if($Target.locator -match '[\\\r\n]' -or $Target.locator.Length -gt 200) { throw 'INVALID_RUN_NAME' }
            $key=Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction Stop
            try {
                $exists=$Target.locator -in $key.GetValueNames()
                $value='';$type=''
                if($exists) { $type=$key.GetValueKind($Target.locator).ToString();$value=[string]$key.GetValue($Target.locator,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
                if($exists -and $type -ne 'String') { throw 'UNSUPPORTED_REGISTRY_TYPE' }
                return [pscustomobject]@{exists=$exists;enabled=$false;value=$value;kind='run';locator=$Target.locator;definition=$type}
            } finally { $key.Close() }
        }
        'startup' {
            $p=Assert-PlainPath $Target.locator
            $startup=if($Context.fixture){Join-Path $Context.profile 'Startup'}else{Get-CanonicalPath ([Environment]::GetFolderPath('Startup'))}
            if((Split-Path -Parent $p) -ine $startup -or [IO.Path]::GetExtension($p) -ine '.lnk') { throw 'STARTUP_SCOPE_REFUSED' }
            $exists=Test-Path -LiteralPath $p -PathType Leaf
            return [pscustomobject]@{exists=$exists;enabled=$false;value='';kind='startup';locator=$p;definition=$(if($exists){Get-ShaFile $p}else{''})}
        }
        default { throw 'UNSUPPORTED_TARGET' }
    }
}
function Get-StateHash($State) { return Get-ShaText ($State | ConvertTo-Json -Depth 8 -Compress) }
function Get-DesiredState($State) {
    $copy=$State | ConvertTo-Json -Depth 8 -Compress | ConvertFrom-Json
    switch($copy.kind) {
        'task' { $copy.enabled=$false }
        'run' { $copy.exists=$false;$copy.value='';$copy.definition='' }
        'startup' { $copy.exists=$false;$copy.definition='' }
        default { throw 'UNSUPPORTED_TARGET' }
    }
    return $copy
}
function Set-TargetState($Context,$Target,$State,[string]$HeldPath) {
    Assert-Context $Context -Mutation
    if($Target.kind -eq 'run' -and -not (Test-RunValueName $Target.locator)){throw 'INVALID_RUN_NAME'}
    if($Context.fixture -and $Target.kind -ne 'startup') {
        $dbPath=Join-Path $Context.fixture_root 'objects.json';$db=Read-RescueJson $dbPath
        $matches=@($db.objects | Where-Object { $_.kind -eq $Target.kind -and $_.locator -eq $Target.locator })
        if($matches.Count -ne 1) { throw 'OBJECT_MISSING_OR_AMBIGUOUS' }
        foreach($key in @('exists','enabled','value','definition')) { $matches[0].$key=$State.$key }
        Write-DurableJson $dbPath $db -Replace
        return
    }
    switch($Target.kind) {
        'task' {
            if($Target.locator -match '[*?\[\]]'){throw 'TASK_WILDCARD_REFUSED'}
            $split=$Target.locator.LastIndexOf('\')
            $args=@{TaskPath=$Target.locator.Substring(0,$split+1);TaskName=$Target.locator.Substring($split+1);ErrorAction='Stop'}
            if($State.enabled) { Enable-ScheduledTask @args | Out-Null } else { Disable-ScheduledTask @args | Out-Null }
        }
        'run' {
            Set-RunValueState $Target $State
        }
        'startup' {
            $null=Assert-PlainPath $HeldPath
            if($State.exists) {
                if(Test-Path -LiteralPath $Target.locator) { throw 'UNDO_CONFLICT' }
                [IO.File]::Move($HeldPath,$Target.locator)
            } else {
                if(Test-Path -LiteralPath $HeldPath) { throw 'HELD_PATH_CONFLICT' }
                [IO.File]::Move($Target.locator,$HeldPath)
            }
        }
        default { throw 'UNSUPPORTED_TARGET' }
    }
}
function Get-ActiveWriters($Context,[string]$Writer) {
    if($Context.fixture) { return @($Context.facts.processes | Where-Object writer -eq $Writer) }
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object { $_.CommandLine -and (Get-WriterMatch ([string]$_.CommandLine) $Writer) })
}