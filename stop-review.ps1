$stateDirectory = Join-Path $PSScriptRoot '.review'
foreach ($entry in @(@{ File = 'tunnel.pid'; Name = 'cloudflared' }, @{ File = 'server.pid'; Name = 'python' })) {
    $pidFile = Join-Path $stateDirectory $entry.File
    if (Test-Path -LiteralPath $pidFile) {
        $reviewProcessId = [int](Get-Content -LiteralPath $pidFile)
        $reviewProcess = Get-Process -Id $reviewProcessId -ErrorAction SilentlyContinue
        if ($reviewProcess -and $reviewProcess.ProcessName -eq $entry.Name) {
            Stop-Process -Id $reviewProcessId
            Write-Output "Stopped $($entry.Name) review process."
        }
    }
}
