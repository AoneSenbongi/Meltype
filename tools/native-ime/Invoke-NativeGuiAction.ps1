param([Parameter(Mandatory)][string]$Script, [Parameter(Mandatory)][string]$ResultFile, [switch]$Disable, [switch]$NoStartOriginal)
$ErrorActionPreference = 'Stop'
try {
    $parameters = @{}
    if ($Disable) { $parameters.Disable = $true }
    if ($NoStartOriginal) { $parameters.NoStartOriginal = $true }
    $output = & $Script @parameters | Out-String
    @{ Success = $true; Output = $output } | ConvertTo-Json | Set-Content -LiteralPath $ResultFile -Encoding UTF8
} catch {
    @{ Success = $false; Output = ($_ | Out-String) } | ConvertTo-Json | Set-Content -LiteralPath $ResultFile -Encoding UTF8
    exit 1
}
