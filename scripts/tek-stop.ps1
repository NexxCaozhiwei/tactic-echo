$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $RepoRoot
$ErrorActionPreference = "Stop"

$targets = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains($RepoRoot) -and
        ($_.CommandLine -match 'tek-live-sendinput-ui-toggle\.ps1' -or
         $_.CommandLine -match 'tek-ui-toggle-managed')
    }

if (-not $targets) {
    Write-Host "TEK is not running."
    exit 0
}

$targets | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize

foreach ($target in $targets) {
    if ($target.ProcessId -ne $PID) {
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "TEK stopped."
