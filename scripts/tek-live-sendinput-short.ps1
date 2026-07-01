param(
    [string]$TracePath = "logs/tek-live-sendinput.jsonl",
    [int]$MaxFrames = 200,
    [double]$Interval = 0.05
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

python -m tek.src.cli `
    --live `
    --auto-locate-signal `
    --send-input `
    --confirm-send-input I_UNDERSTAND_TEK_SENDS_KEYS `
    --max-frames $MaxFrames `
    --interval $Interval `
    --dispatch-budget 1 `
    --trace $TracePath
