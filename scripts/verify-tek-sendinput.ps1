param(
    [string]$TekExe = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist\TEK.exe"),
    [string]$Binding = "Q",
    [string]$ExpectedProcess = "notepad.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $TekExe)) { throw "TEK.exe not found: $TekExe" }
if ($ExpectedProcess -match "(?i)wow|warcraft") { throw "Acceptance target must never be a WoW process." }

$diagnostics = Join-Path $env:LOCALAPPDATA "TacticEcho\diagnostics"
$before = Get-Date
$notepad = Start-Process -FilePath "notepad.exe" -PassThru
Start-Sleep -Milliseconds 750
Write-Host "Notepad has been opened. Click its blank editor so it is the foreground window, then press Enter." -ForegroundColor Yellow
[void](Read-Host)

$confirmation = "I_UNDERSTAND_TEK_SENDS_A_TEST_KEY"
& $TekExe --sendinput-acceptance --confirm $confirmation --expected-process $ExpectedProcess --binding $Binding
if ($LASTEXITCODE -ne 0) { throw "TEK.exe SendInput acceptance command failed with exit code $LASTEXITCODE" }

$evidence = Get-ChildItem -LiteralPath $diagnostics -Filter "tek-sendinput-acceptance-*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $before.AddSeconds(-2) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $evidence) { throw "No SendInput acceptance evidence file was produced." }
$record = Get-Content -LiteralPath $evidence.FullName -Raw | ConvertFrom-Json
if (-not $record.ok -or $record.reason -ne "input_sent") { throw "SendInput did not report success: $($record | ConvertTo-Json -Compress)" }

$visual = Read-Host "Did the selected key '$Binding' visibly reach Notepad? Type YES to complete the manual gate"
if ($visual -cne "YES") { throw "Manual observation was not confirmed. Do not mark SendInput acceptance as passed." }
Write-Host "SendInput acceptance passed. Evidence: $($evidence.FullName)" -ForegroundColor Green
