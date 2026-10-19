$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source=Join-Path $root 'native/tip/meltype.ico'
$output=Join-Path $root 'native/tsf/meltype-logo.ico'
Copy-Item -LiteralPath $source -Destination $output -Force
if((Get-FileHash $source).Hash -ne (Get-FileHash $output).Hash){throw 'Brand icon copy mismatch'}
Write-Output 'Meltype 1.3.0 upstream snowflake + M icon copied without modification.'
