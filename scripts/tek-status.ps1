$ErrorActionPreference = "Stop"

$targets = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -match 'tek-live-sendinput-ui-toggle\.ps1' -or
        $_.CommandLine -match 'tek-ui-toggle-managed' -or
        $_.CommandLine -match 'tek\.src\.cli'
    }

if (-not $targets) {
    Write-Host "TEK is not running."
    exit 0
}

Write-Host "TEK processes:"
$targets | Select-Object ProcessId, ParentProcessId, Name, CommandLine | Format-Table -AutoSize

$currentTracePath = "logs\tek-ui-toggle-current.txt"
$latestTrace = $null
$hasCurrentTrace = $false

if (Test-Path -LiteralPath $currentTracePath) {
    $hasCurrentTrace = $true
    $tracePath = (Get-Content -LiteralPath $currentTracePath -Raw).Trim()
    if ($tracePath -and (Test-Path -LiteralPath $tracePath)) {
        $latestTrace = Get-Item -LiteralPath $tracePath
    } elseif ($tracePath) {
        Write-Host ""
        Write-Host "Current trace is not created yet: $tracePath"
    }
}

if (-not $latestTrace -and -not $hasCurrentTrace) {
    $latestTrace = Get-ChildItem -Path "logs" -Filter "tek-ui-toggle-sendinput-*.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

if ($latestTrace) {
    Write-Host ""
    Write-Host "Latest trace: $($latestTrace.FullName)"
    Get-Content -LiteralPath $latestTrace.FullName -Tail 5
}
