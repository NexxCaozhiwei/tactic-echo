param(
    [string]$TracePath = "logs/tek-live-dry-run.jsonl",
    [double]$Interval = 0.05
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

python -m tek.src.cli `
    --live `
    --auto-locate-signal `
    --interval $Interval `
    --trace $TracePath
