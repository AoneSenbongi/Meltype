function Get-NativeAutoStartCommand([string]$ScriptPath) {
    if ($ScriptPath -match '["\r\n]') { throw 'Invalid startup script path.' }
    $hostPath = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $command = '"' + $hostPath + '" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    if ($command.Length -gt 260) { throw 'Windows startup command exceeds 260 characters.' }
    return $command
}
