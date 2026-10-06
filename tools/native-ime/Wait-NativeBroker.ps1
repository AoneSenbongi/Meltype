if (-not ('MeltypeBrokerReadiness' -as [type])) {
    Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public static class MeltypeBrokerReadiness { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool WaitNamedPipe(string name, uint timeout); }'
}
function Test-NativeBrokerReady([string]$Name) {
    return [MeltypeBrokerReadiness]::WaitNamedPipe($Name, 50)
}
function Wait-NativeBrokerReady([string]$Name, [Diagnostics.Process]$Process, [int]$TimeoutSeconds = 60) {
    $elapsed = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (Test-NativeBrokerReady $Name) { return }
        $Process.Refresh()
        if ($Process.HasExited) { throw "Native broker exited (code $($Process.ExitCode))." }
        Start-Sleep -Milliseconds 100
    } while ($elapsed.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Native broker did not become ready within $TimeoutSeconds seconds."
}
