#requires -Version 5.1
[CmdletBinding()]param([string]$Root)
$ErrorActionPreference='Stop'
if(-not $Root){$Root=Split-Path -Parent $PSScriptRoot}
$rootPath=[IO.Path]::GetFullPath($Root);$failures=New-Object Collections.Generic.List[string]
$files=@(Get-ChildItem -LiteralPath $rootPath -Recurse -File | Where-Object {
    $_.FullName -notmatch '[\\/](out|artifacts|\.test-runs|\.git)[\\/]'
})
$parsed=0
foreach($f in $files){
    if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$failures.Add('REPARSE_FILE');continue}
    if($f.Extension -in @('.ps1','.psm1')){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
        foreach($e in @($errors)){$failures.Add(($f.Name+':'+$e.ErrorId))};$parsed++
    }
    if($f.Extension -in @('.ps1','.psm1','.md','.json','.cmd','.txt') -or $f.Name -eq 'LICENSE'){
        $s=[IO.File]::ReadAllText($f.FullName)
        # Heuristics supplement, never replace independent privacy/security review.
        if($s -match '(?i)sk-[a-zA-Z0-9_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|Bearer\s+[a-zA-Z0-9._-]{24,}|C:[\\/]Users[\\/](?!<|Public|Default)[^\\/\s]+'){$failures.Add($f.Name+':SENSITIVE_PATTERN')}
        if($f.FullName -match '[\\/]kit[\\/]' -and $s -match '(?i)\b(takeown|icacls|Set-Acl|Stop-Process|Invoke-Expression|Invoke-WebRequest|Set-ExecutionPolicy)\b'){$failures.Add($f.Name+':FORBIDDEN_OPERATION')}
    }
}
if($failures.Count){$failures|ForEach-Object {Write-Error $_ -ErrorAction Continue};exit 2}
[pscustomobject]@{schema='rescue-static-v1';status='PASS';files=$files.Count;powershell_files_parsed=$parsed;scope='Parser and bounded sensitive-pattern/forbidden-operation checks; not a security audit'}|ConvertTo-Json