param(
    [string]$TracePath = "logs/tek-ui-toggle-sendinput.jsonl",
    [int]$DispatchBudget = 100000,
    [double]$Interval = 0.25
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

python -m tek.src.cli `
    --live `
    --auto-locate-signal `
    --send-input `
    --confirm-send-input I_UNDERSTAND_TEK_SENDS_KEYS `
    --interval $Interval `
    --dispatch-budget $DispatchBudget `
    --require-start-toggle `
    --trace $TracePath
