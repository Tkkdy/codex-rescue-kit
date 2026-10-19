function Convert-RescueUtc($Value) {
    if($Value -is [DateTime]){return $Value.ToUniversalTime()}
    return [DateTime]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}
function Get-ShaText([string]$Text) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
}
function Get-ShaFile([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
function Get-CanonicalPath([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]') { throw 'ABSOLUTE_PATH_REQUIRED' }
    if($Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '^\\\\' -or $Path -match '^[A-Za-z]:.*:') { throw 'UNSUPPORTED_OR_TRAVERSAL_PATH' }
    if($Path -match '[?*"<\x00-\x1f>]' -or $Path -match '[. ]([\\/]|$)' -or $Path -match '(?i)(^|[\\/])(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.[^\\/]*)?([\\/]|$)'){throw 'UNSUPPORTED_DEVICE_OR_ALIAS_PATH'}
    $full=[IO.Path]::GetFullPath($Path)
    if($full.Length -eq 3){return $full}
    return $full.TrimEnd('\')
}
function Assert-PlainPath([string]$Path,[switch]$MustExist) {
    $p=Get-CanonicalPath $Path
    $cursor=$p
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            $i=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'REPARSE_PATH_REFUSED' }
        }
        $parent=Split-Path -Parent $cursor
        if($parent -eq $cursor) { break }; $cursor=$parent
    }
    if($MustExist -and -not (Test-Path -LiteralPath $p)) { throw 'PATH_NOT_FOUND' }
    return $p
}
function Test-Within([string]$Path,[string]$Root) {
    $p=Get-CanonicalPath $Path; $r=Get-CanonicalPath $Root
    return $p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Write-DurableJson([string]$Path,$Data,[switch]$Replace) {
    $p=Assert-PlainPath $Path
    [IO.Directory]::CreateDirectory((Split-Path -Parent $p)) | Out-Null
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Data | ConvertTo-Json -Depth 30 -Compress))
    if(-not $Replace) {
        $f=[IO.FileStream]::new($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $f.Write($bytes,0,$bytes.Length); $f.Flush($true) } finally { $f.Dispose() }
    } else {
        $tmp=$p+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
        $f=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $f.Write($bytes,0,$bytes.Length); $f.Flush($true) } finally { $f.Dispose() }
        if(Test-Path -LiteralPath $p) { [IO.File]::Replace($tmp,$p,[System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($tmp,$p) }
    }
}
function Read-RescueJson([string]$Path) {
    $p=Assert-PlainPath $Path -MustExist
    if((Get-Item -LiteralPath $p).Length -gt 2MB) { throw 'JSON_TOO_LARGE' }
    return ([IO.File]::ReadAllText($p) | ConvertFrom-Json -ErrorAction Stop)
}
function New-Check([string]$Id,[string]$Status,[string]$Code,[string]$Channel='C',[string]$Level='CONFIRMED',$Data=$null) {
    if($Status -notin @('PASS','FAIL','BLOCKED','NOT_TESTED','N/A')) { throw 'INVALID_STATUS' }
    return [pscustomobject][ordered]@{ id=$Id;status=$Status;code=$Code;channel=$Channel;evidence_level=$Level;observed_at=[DateTime]::UtcNow.ToString('o');data=$Data }
}
function Get-RescueExitCode($Checks) {
    if(@($Checks | Where-Object status -eq 'FAIL').Count) { return 2 }
    if(@($Checks | Where-Object { $_.status -in @('BLOCKED','NOT_TESTED') }).Count) { return 3 }
    return 0
}
function New-RescueContext {
    [CmdletBinding()]param([string]$CodexHome,[string]$OutputDirectory,[string]$FixtureRoot)
    $fixture=$false
    if($FixtureRoot) {
        $fr=Assert-PlainPath $FixtureRoot -MustExist
        $marker=Read-RescueJson (Join-Path $fr 'fixture.json')
        if($marker.schema -ne 'rescue-synthetic-v1') { throw 'INVALID_FIXTURE' }
        $fixture=$true; $profile=Join-Path $fr 'profile'
    } else { $fr=''; $profile=[Environment]::GetFolderPath('UserProfile') }
    $profile=Assert-PlainPath $profile -MustExist
    $explicit=-not [string]::IsNullOrWhiteSpace($CodexHome)
    if(-not $explicit) { $CodexHome=if(-not $fixture -and $env:CODEX_HOME){$env:CODEX_HOME}else{Join-Path $profile '.codex'} }
    $homePath=Assert-PlainPath $CodexHome
    if($fixture -and -not (Test-Within $homePath $fr)) { throw 'FIXTURE_ESCAPE' }
    if(-not $OutputDirectory) { $OutputDirectory=Join-Path $profile ('CodexRescueReports\'+[guid]::NewGuid().ToString('N')) }
    $output=Assert-PlainPath $OutputDirectory
    if((Test-Within $output $homePath) -or (Test-Within $homePath $output)) { throw 'OUTPUT_OVERLAPS_HOME' }
    if($fixture -and -not (Test-Within $output $fr)) { throw 'FIXTURE_ESCAPE' }
    $identity=if($fixture){'synthetic-user'}else{[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
    $machine=if($fixture){'synthetic-machine'}else{$env:COMPUTERNAME}
    $facts=$null
    if($fixture) { $facts=Read-RescueJson (Join-Path $fr 'facts.json') }
    return [pscustomobject]@{schema='rescue-context-v1';home=$homePath;profile=$profile;output=$output;fixture=$fixture;fixture_root=$fr;facts=$facts;explicit_home=$explicit;identity=$identity;machine=$machine;fingerprint=(Get-ShaText ($identity+'|'+$machine+'|'+$homePath));channel='UNATTESTED'}
}
function Assert-Context($Context,[switch]$Mutation) {
    $null=Assert-PlainPath $Context.home
    $null=Assert-PlainPath $Context.output
    if($Context.fixture) {
        if(-not (Test-Within $Context.home $Context.fixture_root) -or -not (Test-Within $Context.output $Context.fixture_root)) { throw 'FIXTURE_ESCAPE' }
        $m=Read-RescueJson (Join-Path $Context.fixture_root 'fixture.json')
        if($m.schema -ne 'rescue-synthetic-v1') { throw 'INVALID_FIXTURE' }
    } elseif($Mutation) {
        if(-not [Environment]::Is64BitProcess -or [Environment]::OSVersion.Version.Build -lt 22000){throw 'WINDOWS11_X64_REQUIRED'}
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'NON_ELEVATED_HOST_REQUIRED'}
        if([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Context.output)).DriveFormat -ne 'NTFS'){throw 'NTFS_REQUIRED'}
        $computer=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if($computer.PartOfDomain -or (Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo')){throw 'MANAGED_DEVICE_NOT_SUPPORTED'}
        $id=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if($id -ne $Context.identity -or $env:COMPUTERNAME -ne $Context.machine) { throw 'IDENTITY_DRIFT' }
        if($id -match '-(18|19|20)$' -or [Security.Principal.WindowsIdentity]::GetCurrent().Name -match 'CodexSandbox') { throw 'HOST_WINDOW_REQUIRED' }
        if($Context.channel -ne 'C') { throw 'HOST_CONFIRMATION_REQUIRED' }
    }
}
function Get-Stamp([string]$Path) {
    $p=Assert-PlainPath $Path
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'ABSENT' }
    $i=Get-Item -LiteralPath $p -Force
    if($i.Name -ieq '.env'){return 'METADATA_ONLY|'+$i.Length+'|'+$i.LastWriteTimeUtc.Ticks}
    return (Get-ShaFile $p)+'|'+$i.Length+'|'+$i.LastWriteTimeUtc.Ticks
}
function Get-ConfigSnapshot($Context) {
    try {
        $stamps=@('config.toml','.env' | ForEach-Object {Get-Stamp (Join-Path $Context.home $_)})
        return [pscustomobject]@{status='PASS';code='SNAPSHOT_READ';stamps=$stamps}
    } catch {
        $ex=$_.Exception;while($ex.InnerException){$ex=$ex.InnerException}
        $code=if($ex -is [UnauthorizedAccessException]){'CONFIG_ACCESS_DENIED'}elseif($ex -is [IO.IOException]){'CONFIG_IO_UNAVAILABLE'}else{'CONFIG_SAMPLE_UNAVAILABLE'}
        return [pscustomobject]@{status='BLOCKED';code=$code;stamps=@()}
    }
}
function Get-ConfigStability($Context,[int]$Seconds) {
    if($Seconds -lt 1) { return New-Check 'config.stability' 'NOT_TESTED' 'OBSERVATION_SKIPPED' 'C' 'UNKNOWN' }
    $before=Get-ConfigSnapshot $Context
    if($before.status -ne 'PASS'){return New-Check 'config.stability' 'BLOCKED' $before.code 'C' 'UNKNOWN'}
    $changed=$false;$readFailure=$null
    for($s=0;$s -lt $Seconds;$s++) {
        Start-Sleep -Milliseconds 1000
        $current=Get-ConfigSnapshot $Context
        if($current.status -ne 'PASS'){$readFailure=$current.code;continue}
        if(($current.stamps -join ';') -ne ($before.stamps -join ';')) { $changed=$true }
    }
    if($changed){return New-Check 'config.stability' 'FAIL' 'CHANGED_DURING_WINDOW' 'C' 'CONFIRMED' @{seconds=$Seconds;sampling_incomplete=($null -ne $readFailure)}}
    if($readFailure){return New-Check 'config.stability' 'BLOCKED' $readFailure 'C' 'UNKNOWN' @{seconds=$Seconds}}
    return New-Check 'config.stability' 'PASS' 'STABLE_DURING_WINDOW_ONLY' 'C' 'CONFIRMED' @{seconds=$Seconds}
}
function Read-BoundedManifestText([string]$Path) {
    # Deny concurrent writers while reading this handle, so the size check and read agree.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -gt 32MB){throw 'MANIFEST_SIZE_UNSUPPORTED'}
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
        try{return $reader.ReadToEnd()}finally{$reader.Dispose()}
    } finally {$stream.Dispose()}
}
function Test-BackupManifest {
    [CmdletBinding()]param([Parameter(Mandatory)] [string]$Manifest,[Parameter(Mandatory)] [string]$PayloadRoot)
    # Independent bounds: journal/plan JSON limits must not limit backup manifests.
    try {
        $root=Assert-PlainPath $PayloadRoot -MustExist
        $manifestPath=Assert-PlainPath $Manifest -MustExist
        if((Get-Item -LiteralPath $manifestPath -ErrorAction Stop).Length -gt 32MB){return New-Check 'backup.content' 'BLOCKED' 'MANIFEST_SIZE_UNSUPPORTED' 'C' 'UNKNOWN'}
        $text=Read-BoundedManifestText $manifestPath
    } catch {return New-Check 'backup.content' 'BLOCKED' $(if($_.Exception.Message -eq 'MANIFEST_SIZE_UNSUPPORTED'){'MANIFEST_SIZE_UNSUPPORTED'}else{'MANIFEST_OR_PAYLOAD_UNAVAILABLE'}) 'C' 'UNKNOWN'}
    try {$m=$text | ConvertFrom-Json -ErrorAction Stop}
    catch {return New-Check 'backup.content' 'FAIL' 'MANIFEST_JSON_INVALID'}
    try {
        if($m.schema -ne 'rescue-backup-v1' -or -not $m.PSObject.Properties['files'] -or @($m.files).Count -eq 0) { return New-Check 'backup.content' 'NOT_TESTED' 'PER_FILE_MANIFEST_REQUIRED' 'C' 'UNKNOWN' }
        if(@($m.files).Count -gt 100000){return New-Check 'backup.content' 'BLOCKED' 'MANIFEST_FILE_COUNT_UNSUPPORTED' 'C' 'UNKNOWN'}
        $seen=@{}
        foreach($file in $m.files) {
            if(-not $file.PSObject.Properties['path'] -or -not $file.PSObject.Properties['sha256'] -or -not $file.PSObject.Properties['bytes']){throw 'MANIFEST_ENTRY_INVALID'}
            [long]$length=0
            if([string]::IsNullOrWhiteSpace($file.path) -or [IO.Path]::IsPathRooted($file.path) -or $file.path -match ':|(^|[\\/])\.\.([\\/]|$)') { throw 'INVALID_MANIFEST_PATH' }
            if($file.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not [long]::TryParse([string]$file.bytes,[ref]$length) -or $length -lt 0){throw 'MANIFEST_ENTRY_INVALID'}
            $p=Assert-PlainPath (Join-Path $root $file.path)
            if(-not (Test-Within $p $root) -or $seen.ContainsKey($p)) { throw 'INVALID_MANIFEST_PATH' }; $seen[$p]=$true
            if(-not (Test-Path -LiteralPath $p -PathType Leaf -ErrorAction Stop)){throw 'LISTED_FILE_MISSING'}
            if((Get-ShaFile $p) -ne $file.sha256 -or (Get-Item -LiteralPath $p -ErrorAction Stop).Length -ne $length) { throw 'CONTENT_MISMATCH' }
        }
        $queue=New-Object Collections.Generic.Queue[string];$queue.Enqueue($root);$actualCount=0
        while($queue.Count){
            foreach($item in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force -ErrorAction Stop)){
                $null=Assert-PlainPath $item.FullName -MustExist
                if($item.PSIsContainer){$queue.Enqueue($item.FullName)}else{
                    $actualCount++
                    if(-not $seen.ContainsKey($item.FullName)){throw 'PAYLOAD_COVERAGE_MISMATCH'}
                }
            }
        }
        if($actualCount -ne $seen.Count) { throw 'PAYLOAD_COVERAGE_MISMATCH' }
        return New-Check 'backup.content' 'PASS' 'LISTED_PAYLOAD_HASHES_MATCH_NOT_RESTORE_PROOF'
    } catch {
        $code=[string]$_.Exception.Message
        if($code -in @('CONTENT_MISMATCH','LISTED_FILE_MISSING','PAYLOAD_COVERAGE_MISMATCH','MANIFEST_ENTRY_INVALID','INVALID_MANIFEST_PATH','REPARSE_PATH_REFUSED','UNSUPPORTED_OR_TRAVERSAL_PATH','UNSUPPORTED_DEVICE_OR_ALIAS_PATH')){
            return New-Check 'backup.content' 'FAIL' $code
        }
        return New-Check 'backup.content' 'BLOCKED' 'PAYLOAD_VERIFICATION_UNAVAILABLE' 'C' 'UNKNOWN'
    }
}
