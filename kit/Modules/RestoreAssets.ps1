function Get-RestoreSelections($Context,[string]$Manifest,[string]$Payload,[string[]]$AssetPaths,[switch]$ReviewedSources) {
    if(-not $AssetPaths.Count){return @()}
    if(-not $ReviewedSources){throw 'ASSET_SOURCE_REVIEW_REQUIRED'}
    if((Test-BackupManifest $Manifest $Payload).status -ne 'PASS'){throw 'RESTORE_SOURCE_INVALID'}
    $m=Read-BoundedManifestText $Manifest|ConvertFrom-Json;$out=@()
    foreach($rel in $AssetPaths){
        if($rel -notmatch '^(?i:skills[\\/].+|rules[\\/].+|AGENTS\.md)$'){throw 'ASSET_SCOPE_REFUSED'}
        $src=Assert-PlainPath (Join-Path $Payload $rel) -MustExist
        if($Context.fixture -and -not (Test-Within $src $Context.fixture_root)){throw 'FIXTURE_ESCAPE'}
        $dst=Assert-PlainPath (Join-Path $Context.home $rel)
        if(-not (Test-Within $src $Payload) -or -not (Test-Within $dst $Context.home)){throw 'ASSET_SCOPE_REFUSED'}
        if(Test-Path -LiteralPath $dst){throw 'ASSET_DESTINATION_EXISTS'}
        $entry=@($m.files|Where-Object path -eq $rel);if($entry.Count -ne 1){throw 'ASSET_NOT_IN_MANIFEST'}
        $out += [pscustomobject]@{relative=$rel;source=$src;sha256=$entry[0].sha256;bytes=$entry[0].bytes;destination=$dst;source_review='EXPLICIT_USER_REVIEW_NOT_AUTOMATIC_TRUST'}
    }
    return @($out)
}
function Restore-RepairAssets($Context,$Plan,[string]$Run,[string]$Journal) {
    foreach($a in @($Plan.assets)){
        $src=Assert-PlainPath $a.source -MustExist;$dst=Assert-PlainPath $a.destination
        if(-not (Test-Within $dst $Context.home) -or $dst -ne (Join-Path $Context.home $a.relative)){throw 'ASSET_SCOPE_REFUSED'}
        if((Get-ShaFile $src) -ne $a.sha256){throw 'ASSET_SOURCE_DRIFT'}
        $history=Get-JournalRecords $Journal
        $pending=@($history.records|Where-Object {$_.event -eq 'ASSET_PENDING' -and $_.relative -eq $a.relative})
        if(Test-Path -LiteralPath $dst){
            if($pending.Count -eq 1 -and (Get-ShaFile $dst) -eq $a.sha256){continue}
            throw 'ASSET_DESTINATION_EXISTS'
        }
        Add-Journal $Journal @{event='ASSET_PENDING';relative=$a.relative;sha256=$a.sha256;before='ABSENT';desired='COPY_REVIEWED_FILE'}
        [IO.Directory]::CreateDirectory((Split-Path -Parent $dst))|Out-Null
        [IO.File]::Copy($src,$dst,$false)
        if((Get-ShaFile $dst) -ne $a.sha256){throw 'ASSET_COPY_FAILED'}
        Add-Journal $Journal @{event='ASSET_APPLIED';relative=$a.relative;sha256=$a.sha256}
    }
}

function Get-AssetRecoveryCandidates {
    [CmdletBinding()]param($Context,[string]$Manifest,[string]$Payload)
    Assert-Context $Context
    if((Test-BackupManifest $Manifest $Payload).status -ne 'PASS'){throw 'RESTORE_SOURCE_INVALID'}
    $m=Read-BoundedManifestText $Manifest|ConvertFrom-Json
    $current=Get-BackupInventory $Context.home
    $past=@($m.files|Where-Object {$_.path -match '^(?i:skills[\\/].+|rules[\\/].+|AGENTS\.md)$'})
    $now=@($current.files|Where-Object {$_.path -match '^(?i:skills[\\/].+|rules[\\/].+|AGENTS\.md)$'})
    return [pscustomobject]@{status='NOT_TESTED';backup_asset_files=$past.Count;current_asset_files=$now.Count;count_basis='FILES_IN_VERIFIED_MANIFEST_VS_CURRENT_EXPLICIT_HOME_NOT_HISTORICAL_TOTAL_SKILLS';manifest_sha256=(Get-ShaFile $Manifest);candidates=@($past|ForEach-Object {@{path=$_.path;sha256=$_.sha256;bytes=$_.bytes;destination_exists=(Test-Path -LiteralPath (Join-Path $Context.home $_.path));trust='UNKNOWN_USER_SOURCE_AND_VERSION_REVIEW_REQUIRED';load='NOT_TESTED';callable='NOT_TESTED'}});exit_code=3}
}
