param(
    [string]$TekExe = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist\TEK.exe"),
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "dist\TacticEcho-Windows-release.zip"),
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AddonPath = Join-Path $RepoRoot "addon\!TacticEcho"
$Contract = Join-Path $RepoRoot "scripts\verify-baseline-contract.py"
if (-not (Test-Path -LiteralPath $TekExe)) { throw "TEK.exe not found: $TekExe" }
if (-not (Test-Path -LiteralPath $AddonPath)) { throw "Addon folder not found: $AddonPath" }
if (-not (Test-Path -LiteralPath $Contract)) { throw "Baseline contract script not found: $Contract" }

& $PythonExe $Contract --repo-root $RepoRoot
if ($LASTEXITCODE -ne 0) { throw "Baseline contract failed before release packaging." }

$forbiddenAddonParts = @(".git", ".pytest_cache", "__pycache__", "build", "dist", "logs", "trace", "release")
Get-ChildItem -LiteralPath $AddonPath -Recurse -Force | ForEach-Object {
    $relative = $_.FullName.Substring($AddonPath.Length).TrimStart("\\", "/").Split("\\", "/")
    if ($relative | Where-Object { $forbiddenAddonParts -contains $_ }) {
        throw "Refusing to package generated or local AddOn content: $($_.FullName)"
    }
}

$staging = Join-Path ([System.IO.Path]::GetTempPath()) ("tactic-echo-release-" + [Guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    $releaseRoot = Join-Path $staging "TacticEcho"
    New-Item -ItemType Directory -Path $releaseRoot | Out-Null
    Copy-Item -LiteralPath $TekExe -Destination (Join-Path $releaseRoot "TEK.exe")
    Copy-Item -LiteralPath $AddonPath -Destination (Join-Path $releaseRoot "!TacticEcho") -Recurse
    foreach ($file in @("README.md", "docs\BUILD_TEK_EXE_WINDOWS.md", "docs\TEK_EXE.md", "docs\testing-strategy.md")) {
        $source = Join-Path $RepoRoot $file
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $releaseRoot }
    }

    $manifestLeaf = ([System.IO.Path]::GetFileNameWithoutExtension($TekExe) + "-build-manifest.json")
    $manifest = Join-Path (Split-Path -Parent $TekExe) $manifestLeaf
    if (-not (Test-Path -LiteralPath $manifest) -and $manifestLeaf -eq "TEK-build-manifest.json") {
        $manifest = Join-Path (Split-Path -Parent $TekExe) "TEK-build-manifest.json"
    }
    if (Test-Path -LiteralPath $manifest) { Copy-Item -LiteralPath $manifest -Destination $releaseRoot }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
    if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }
    Compress-Archive -Path $releaseRoot -DestinationPath $OutputPath -Force

    & $PythonExe $Contract --archive $OutputPath --expect-root "TacticEcho" --release-package
    if ($LASTEXITCODE -ne 0) { throw "Release archive hygiene check failed." }
    Write-Host "Release package: $OutputPath"
} finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
