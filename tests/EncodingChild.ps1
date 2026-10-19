#requires -Version 5.1
# Synthetic pipe fixture: valid UTF-8 text plus one deliberately invalid byte.
$ErrorActionPreference='Stop'
$prefix=[Text.Encoding]::UTF8.GetBytes('中文|é|')
$suffix=[Text.Encoding]::UTF8.GetBytes('|end')
$stdout=[Console]::OpenStandardOutput()
$stdout.Write($prefix,0,$prefix.Length);$stdout.WriteByte(255);$stdout.Write($suffix,0,$suffix.Length);$stdout.Flush()
$bytes=[Text.Encoding]::UTF8.GetBytes('err|café|中文')
$stderr=[Console]::OpenStandardError();$stderr.Write($bytes,0,$bytes.Length);$stderr.Flush()
exit 0
