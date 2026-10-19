#requires -Version 5.1
param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$Challenge,
      [Parameter(Mandatory)][ValidateSet('location','version','clock')][string]$Kind)
$ErrorActionPreference='Stop'
try {
    switch($Kind) {
        'location' { $null=Get-Location -ErrorAction Stop }
        'version' { if(-not $PSVersionTable.PSVersion){throw 'VERSION_UNAVAILABLE'} }
        'clock' { $null=Get-Date -Format o -ErrorAction Stop }
    }
    [Console]::Out.Write($Challenge+'|'+$Kind+'|OK')
    exit 0
} catch { exit 2 }
