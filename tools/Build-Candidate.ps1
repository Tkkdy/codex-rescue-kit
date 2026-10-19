#requires -Version 5.1
[CmdletBinding()]param([Parameter(Mandatory)][string]$Destination,[string]$GitExecutable='git.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$destinationPath=[IO.Path]::GetFullPath($Destination)
if($destinationPath.Equals($repo,[StringComparison]::OrdinalIgnoreCase)){throw 'CANDIDATE_MUST_BE_OUTSIDE_SOURCE'}
if($destinationPath.StartsWith($repo.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'CANDIDATE_MUST_BE_OUTSIDE_SOURCE'}
$cursor=$destinationPath
while($cursor){if(Test-Path -LiteralPath $cursor){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'DESTINATION_REPARSE_REFUSED'}};$cursor=Split-Path -Parent $cursor}
[IO.Directory]::CreateDirectory($destinationPath)|Out-Null
& (Join-Path $PSScriptRoot 'Test-CandidateEvidence.ps1') -GitExecutable $GitExecutable | Out-Null
$dirty=@(& $GitExecutable -C $repo status --porcelain);if($LASTEXITCODE -ne 0 -or $dirty.Count){throw 'COMMIT_CLEAN_SOURCE_FIRST'}
$commit=(& $GitExecutable -C $repo rev-parse HEAD).Trim();if($LASTEXITCODE -ne 0){throw 'GIT_FAILED'}
$files=@(& $GitExecutable -C $repo -c core.quotepath=false ls-files);if($LASTEXITCODE -ne 0){throw 'GIT_FAILED'}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Join-Path $destinationPath ('codex-rescue-kit-v0.2-'+$commit.Substring(0,12)+'-candidate.zip')
if(Test-Path -LiteralPath $zip){throw 'CANDIDATE_ALREADY_EXISTS'}
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
$manifest=@()
try{
    foreach($relative in $files){
        # Packaging is an allowlist over committed source, not a recursive archive of the workspace.
        if($relative -notmatch '^(kit/|tests/|tools/|skills/|docs/|evidence/|README\.md$|README\.en\.md$|PREVIEW-RELEASE-NOTES\.md$|SECURITY\.md$|\.ai/handoff\.md$|LICENSE$|THIRD_PARTY_NOTICES\.md$|rescue\.cmd$|\.gitignore$|\.gitattributes$)' -or $relative -match '(^|/)(out|artifacts|\.test-runs|\.git)(/|$)|\.\.|:|^/'){throw 'PACKAGE_PATH_REFUSED'}
        $p=Join-Path $repo $relative
        $cursor=$p;while($cursor.Length -ge $repo.Length){if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'REPARSE_REFUSED'};$cursor=Split-Path -Parent $cursor;if(-not $cursor){break}}
        $hash=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest+=@{path=$relative;bytes=(Get-Item -LiteralPath $p).Length;sha256=$hash}
        $null=[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$p,$relative,[IO.Compression.CompressionLevel]::Optimal)
    }
}finally{$archive.Dispose()}
# Verify every archived byte against the source hash, not just the ZIP size.
$read=[IO.Compression.ZipFile]::OpenRead($zip)
try{
    if($read.Entries.Count -ne $manifest.Count){throw 'PACKAGE_COUNT_MISMATCH'}
    foreach($item in $manifest){
        $entry=$read.GetEntry($item.path);if($null -eq $entry){throw 'PACKAGE_ENTRY_MISSING'}
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
        if($hash -ne $item.sha256){throw 'PACKAGE_CONTENT_MISMATCH'}
    }
}finally{$read.Dispose()}
$zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(($zip+'.sha256'),($zipHash+'  '+[IO.Path]::GetFileName($zip)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
$record=[ordered]@{schema='rescue-candidate-v1';state='REAL_REPAIR_REVIEW_READY';commit=$commit;created_at=[DateTime]::UtcNow.ToString('o');archive=[IO.Path]::GetFileName($zip);sha256=$zipHash;files=@($manifest);public_release=$false}
[IO.File]::WriteAllText(($zip+'.manifest.json'),($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
[pscustomobject]@{commit=$commit;archive=$zip;sha256=$zipHash;files=$manifest.Count}|ConvertTo-Json