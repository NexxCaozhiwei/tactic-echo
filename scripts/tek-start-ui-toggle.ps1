param(
    [string]$TracePath = "",
    [int]$DispatchBudget = 100000,
    [double]$Interval = 0.25
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$existing = Get-CimInstance Win32_Process |
    Where-Object {
        $_.CommandLine -match 'tek-live-sendinput-ui-toggle\.ps1' -or
        $_.CommandLine -match 'tek-ui-toggle-managed' -or
        $_.CommandLine -match 'tek\.src\.cli'
    }

if ($existing) {
    Write-Host "TEK UI-toggle already running:"
    $existing | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize
    exit 0
}

if ([string]::IsNullOrWhiteSpace($TracePath)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $TracePath = Join-Path $RepoRoot "logs\tek-ui-toggle-sendinput-$timestamp.jsonl"
}

$stdout = [System.IO.Path]::ChangeExtension($TracePath, ".out.log")
$stderr = [System.IO.Path]::ChangeExtension($TracePath, ".err.log")
$launcher = Join-Path $RepoRoot "logs\tek-ui-toggle-managed-launcher.ps1"
$currentTrace = Join-Path $RepoRoot "logs\tek-ui-toggle-current.txt"

$script = @"
Set-Location -LiteralPath '$RepoRoot'
while (`$true) {
    & '$PSScriptRoot\tek-live-sendinput-ui-toggle.ps1' -TracePath '$TracePath' -DispatchBudget $DispatchBudget -Interval $Interval
    `$code = `$LASTEXITCODE
    Add-Content -LiteralPath '$stdout' -Value ((Get-Date -Format o) + ' TEK exited with code ' + `$code + '; retrying in 2s')
    Start-Sleep -Seconds 2
}
"@

New-Item -ItemType Directory -Path (Split-Path -Parent $TracePath) -Force | Out-Null
Set-Content -LiteralPath $launcher -Value $script -Encoding UTF8
Set-Content -LiteralPath $currentTrace -Value $TracePath -Encoding UTF8

$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "`$env:TEK_MODE='tek-ui-toggle-managed'; & '$launcher'") `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

Write-Host "TEK UI-toggle started."
Write-Host "Launcher PID: $($process.Id)"
Write-Host "Trace: $TracePath"
Write-Host "Stdout: $stdout"
Write-Host "Stderr: $stderr"
