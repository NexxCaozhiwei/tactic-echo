param(
    [switch]$OneDir,
    [switch]$SkipSmokeTest,
    [switch]$InstallDependencies,
    [switch]$SkipTests,
    [string]$PythonExe = "python",
    [ValidateRange(0, 60)]
    [int]$UnlockWaitSeconds = 8
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Test-FileExclusiveAccess {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        return $true
    } catch {
        return $false
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Test-SameCanonicalPath {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    try {
        $leftFull = [System.IO.Path]::GetFullPath($Left)
        $rightFull = [System.IO.Path]::GetFullPath($Right)
        return [System.String]::Equals(
            $leftFull,
            $rightFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    } catch {
        return $false
    }
}

function Stop-ExactTargetTekProcess {
    param(
        [Parameter(Mandatory = $true)][string]$TargetExe,
        [Parameter(Mandatory = $true)][int]$WaitSeconds
    )

    if (-not (Test-Path -LiteralPath $TargetExe)) { return $true }
    if (Test-FileExclusiveAccess -Path $TargetExe) { return $true }

    Write-Warning "Existing build target is locked: $TargetExe"
    Write-Host "[TEK] Looking only for a running TEK.exe launched from this exact dist path..."

    $targets = @()
    try {
        $targets = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'TEK.exe'" | Where-Object {
            $_.ExecutablePath -and (Test-SameCanonicalPath -Left $_.ExecutablePath -Right $TargetExe)
        })
    } catch {
        Write-Warning "Could not inspect TEK.exe process paths. The staged build fallback will remain available if replacement is still locked."
    }

    foreach ($target in $targets) {
        try {
            Write-Host "[TEK] Stopping previous dist target (PID $($target.ProcessId)) so it can be replaced."
            Stop-Process -Id $target.ProcessId -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not stop PID $($target.ProcessId): $($_.Exception.Message)"
        }
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    do {
        if (Test-FileExclusiveAccess -Path $TargetExe) {
            Write-Host "[TEK] Existing target is now unlocked."
            return $true
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $deadline)

    return (Test-FileExclusiveAccess -Path $TargetExe)
}

function Get-FallbackFilePath {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$BaseName,
        [Parameter(Mandatory = $true)][string]$Extension
    )

    $candidate = Join-Path $Directory ($BaseName + ".new" + $Extension)
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return (Join-Path $Directory ($BaseName + ".new-" + $stamp + $Extension))
}

function Get-BackupPath {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return (Join-Path $Directory ("." + $Name + ".previous-" + [Guid]::NewGuid().ToString("N")))
}

function Restore-BackupArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][string]$OriginalPath
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) { return }
    if (Test-Path -LiteralPath $OriginalPath) { return }

    try {
        Move-Item -LiteralPath $BackupPath -Destination $OriginalPath -Force
        Write-Host "[TEK] Restored the previous build output after a publish failure."
    } catch {
        Write-Warning "Could not restore previous output from ${BackupPath}: $($_.Exception.Message)"
    }
}

function Publish-OneFileArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$StagedExe,
        [Parameter(Mandatory = $true)][string]$FinalExe
    )

    $outputDirectory = Split-Path -Parent $FinalExe
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $backupExe = $null
    $canReplace = $true

    if (Test-Path -LiteralPath $FinalExe) {
        $canReplace = Test-FileExclusiveAccess -Path $FinalExe
        if ($canReplace) {
            $backupExe = Get-BackupPath -Directory $outputDirectory -Name "TEK.exe"
            try {
                Move-Item -LiteralPath $FinalExe -Destination $backupExe -Force
            } catch {
                $canReplace = $false
                $backupExe = $null
                Write-Warning "Could not stage the previous TEK.exe for safe replacement: $($_.Exception.Message)"
            }
        }
    }

    if ($canReplace -and -not (Test-Path -LiteralPath $FinalExe)) {
        try {
            Move-Item -LiteralPath $StagedExe -Destination $FinalExe -Force
            if ($backupExe -and (Test-Path -LiteralPath $backupExe)) {
                Remove-Item -LiteralPath $backupExe -Force -ErrorAction SilentlyContinue
            }
            return [pscustomobject]@{
                Executable = $FinalExe
                PrimaryPath = $true
                PublishState = "primary"
            }
        } catch {
            Write-Warning "Could not publish to dist\\TEK.exe: $($_.Exception.Message)"
            if ($backupExe) { Restore-BackupArtifact -BackupPath $backupExe -OriginalPath $FinalExe }
        }
    }

    $fallbackExe = Get-FallbackFilePath -Directory $outputDirectory -BaseName "TEK" -Extension ".exe"
    try {
        Copy-Item -LiteralPath $StagedExe -Destination $fallbackExe -Force
    } catch {
        throw "Build succeeded, but neither dist\\TEK.exe nor fallback output could be written. Close programs holding dist\\TEK.exe and retry. Detail: $($_.Exception.Message)"
    }

    Write-Warning "The previous dist\\TEK.exe was preserved because it is still locked or could not be safely replaced. New build: $fallbackExe"
    return [pscustomobject]@{
        Executable = $fallbackExe
        PrimaryPath = $false
        PublishState = "fallback_locked_target"
    }
}

function Publish-OneDirArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$StagedDirectory,
        [Parameter(Mandatory = $true)][string]$FinalDirectory
    )

    $outputDirectory = Split-Path -Parent $FinalDirectory
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $finalExe = Join-Path $FinalDirectory "TEK.exe"
    $backupDirectory = $null
    $canReplace = -not (Test-Path -LiteralPath $FinalDirectory)

    if (Test-Path -LiteralPath $FinalDirectory) {
        if ((Test-Path -LiteralPath $finalExe) -and (Test-FileExclusiveAccess -Path $finalExe)) {
            $backupDirectory = Get-BackupPath -Directory $outputDirectory -Name "TEK"
            try {
                Move-Item -LiteralPath $FinalDirectory -Destination $backupDirectory -Force
                $canReplace = $true
            } catch {
                $canReplace = $false
                $backupDirectory = $null
                Write-Warning "Could not stage previous one-dir output for safe replacement: $($_.Exception.Message)"
            }
        } else {
            Write-Warning "Previous one-dir output cannot be safely replaced while its TEK.exe or files are in use."
        }
    }

    if ($canReplace -and -not (Test-Path -LiteralPath $FinalDirectory)) {
        try {
            Move-Item -LiteralPath $StagedDirectory -Destination $FinalDirectory
            if ($backupDirectory -and (Test-Path -LiteralPath $backupDirectory)) {
                Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
            return [pscustomobject]@{
                Executable = (Join-Path $FinalDirectory "TEK.exe")
                PrimaryPath = $true
                PublishState = "primary"
            }
        } catch {
            Write-Warning "Could not publish to dist\\TEK\\TEK.exe: $($_.Exception.Message)"
            if ($backupDirectory) { Restore-BackupArtifact -BackupPath $backupDirectory -OriginalPath $FinalDirectory }
        }
    }

    $fallbackDirectory = Get-FallbackFilePath -Directory $outputDirectory -BaseName "TEK" -Extension ".new"
    try {
        Move-Item -LiteralPath $StagedDirectory -Destination $fallbackDirectory
    } catch {
        throw "Build succeeded, but neither dist\\TEK nor fallback output could be written. Close programs holding dist\\TEK and retry. Detail: $($_.Exception.Message)"
    }

    $fallbackExe = Join-Path $fallbackDirectory "TEK.exe"
    Write-Warning "The previous dist\\TEK output was preserved because it is still locked or could not be safely replaced. New build: $fallbackExe"
    return [pscustomobject]@{
        Executable = $fallbackExe
        PrimaryPath = $false
        PublishState = "fallback_locked_target"
    }
}

$Python = Get-Command $PythonExe -ErrorAction SilentlyContinue
if (-not $Python) {
    throw "Python executable was not found: $PythonExe. Install 64-bit Python 3.11+ and reopen PowerShell."
}

& $PythonExe -c "import platform, sys; raise SystemExit(0 if sys.version_info >= (3, 11) and platform.architecture()[0] == '64bit' else 1)"
if ($LASTEXITCODE -ne 0) {
    throw "TEK.exe build requires 64-bit Python 3.11+; resolved executable: $PythonExe"
}

$ProfilePath = Join-Path $RepoRoot "examples\profiles\laptop.json"
$TekAssetsPath = Join-Path $RepoRoot "tek\assets"
$TekIconPath = Join-Path $TekAssetsPath "tek.ico"
$RequirementsPath = Join-Path $RepoRoot "requirements-windows.txt"

$required = @("PyInstaller", "pystray", "PIL", "win32api", "pytest")
$missing = @()
foreach ($module in $required) {
    & $PythonExe -c "import importlib.util as u; raise SystemExit(0 if u.find_spec('$module') else 1)"
    if ($LASTEXITCODE -ne 0) { $missing += $module }
}

if ($missing.Count -gt 0) {
    if ($InstallDependencies) {
        Write-Host "Installing build dependencies..."
        & $PythonExe -m pip install -r $RequirementsPath
        if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed with exit code $LASTEXITCODE" }
    } else {
        throw "Missing build/runtime modules: $($missing -join ', '). Run: python -m pip install -r $RequirementsPath, or rerun this script with -InstallDependencies."
    }
}

if (-not $SkipTests) {
    Write-Host "Running baseline contract and test suites..."
    & $PythonExe scripts\verify-baseline-contract.py --repo-root $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "baseline contract failed with exit code $LASTEXITCODE" }
    & $PythonExe -m pytest -q tek/tests tests/unit
    if ($LASTEXITCODE -ne 0) { throw "pytest failed with exit code $LASTEXITCODE" }
    & $PythonExe -m unittest discover -s tek/tests -v
    if ($LASTEXITCODE -ne 0) { throw "tek/tests failed with exit code $LASTEXITCODE" }
    & $PythonExe -m unittest discover -s tests/unit -v
    if ($LASTEXITCODE -ne 0) { throw "tests/unit failed with exit code $LASTEXITCODE" }
    & $PythonExe -m compileall -q tek/src tek/app tek/runtime
    if ($LASTEXITCODE -ne 0) { throw "compileall failed with exit code $LASTEXITCODE" }

    $luaCompiler = Get-Command texluac -ErrorAction SilentlyContinue
    if (-not $luaCompiler) { $luaCompiler = Get-Command luac -ErrorAction SilentlyContinue }
    if ($luaCompiler) {
        Get-ChildItem -Path (Join-Path $RepoRoot "addon") -Recurse -Filter *.lua | ForEach-Object {
            & $luaCompiler.Source -p $_.FullName
            if ($LASTEXITCODE -ne 0) { throw "Lua syntax check failed: $($_.FullName)" }
        }
    } else {
        Write-Warning "Lua compiler (texluac/luac) was not found; Python lexical and TOC contracts still ran. Install a Lua compiler to add the optional full syntax gate."
    }
}

$DistRoot = Join-Path $RepoRoot "dist"
$FinalExe = if ($OneDir) { Join-Path $DistRoot "TEK\TEK.exe" } else { Join-Path $DistRoot "TEK.exe" }
if ((Test-Path -LiteralPath $FinalExe) -and -not (Stop-ExactTargetTekProcess -TargetExe $FinalExe -WaitSeconds $UnlockWaitSeconds)) {
    Write-Warning "dist target remains locked. PyInstaller will build in an isolated staging directory; the new executable will be retained under dist as TEK.new.exe (or a timestamped variant) if it cannot replace the primary target."
}

$StageRoot = Join-Path $RepoRoot ("build\tek-stage-" + [Guid]::NewGuid().ToString("N"))
$StageDist = Join-Path $StageRoot "dist"
$StageWork = Join-Path $StageRoot "work"
$StageSpec = Join-Path $StageRoot "spec"
New-Item -ItemType Directory -Path $StageDist, $StageWork, $StageSpec -Force | Out-Null

try {
    $PyInstallerArgs = @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--windowed",
        "--name", "TEK",
        "--paths", $RepoRoot,
        "--distpath", $StageDist,
        "--workpath", $StageWork,
        "--specpath", $StageSpec,
        "--collect-submodules", "tek",
        "--collect-submodules", "pystray",
        "--collect-submodules", "PIL",
        "--hidden-import", "pystray._win32",
        "--hidden-import", "pystray._util.win32",
        "--hidden-import", "win32api",
        "--hidden-import", "win32con",
        "--hidden-import", "win32gui",
        "--hidden-import", "win32gui_struct"
    )

    if ($OneDir) { $PyInstallerArgs += "--onedir" } else { $PyInstallerArgs += "--onefile" }
    $PyInstallerArgs += @("--add-data", "$TekAssetsPath;tek\assets")
    $PyInstallerArgs += @("--add-data", "$ProfilePath;examples\profiles")
    if (Test-Path -LiteralPath $TekIconPath) { $PyInstallerArgs += @("--icon", $TekIconPath) }
    $PyInstallerArgs += "tek\app\main.py"

    Write-Host "[TEK] Building in isolated staging output: $StageDist"
    & $PythonExe @PyInstallerArgs
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE" }

    $stagedExe = if ($OneDir) { Join-Path $StageDist "TEK\TEK.exe" } else { Join-Path $StageDist "TEK.exe" }
    if (-not (Test-Path -LiteralPath $stagedExe)) { throw "Build finished but staged TEK.exe was not found at $stagedExe" }
    if ((Get-Item -LiteralPath $stagedExe).Length -lt 1MB) { throw "Staged TEK.exe size is unexpectedly small; treating build as invalid" }

    $publish = if ($OneDir) {
        Publish-OneDirArtifact -StagedDirectory (Split-Path -Parent $stagedExe) -FinalDirectory (Join-Path $DistRoot "TEK")
    } else {
        Publish-OneFileArtifact -StagedExe $stagedExe -FinalExe $FinalExe
    }
    $exe = $publish.Executable

    if (-not $SkipSmokeTest) {
        $process = Start-Process -FilePath $exe -PassThru
        Start-Sleep -Seconds 3
        if ($process.HasExited) { throw "TEK.exe smoke test failed: process exited with code $($process.ExitCode)" }
        Stop-Process -Id $process.Id -Force
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $exe
    $manifest = [ordered]@{
        schemaVersion = 2
        component = "TEK"
        builtAt = (Get-Date).ToUniversalTime().ToString("o")
        executable = (Resolve-Path -LiteralPath $exe).Path
        standardOutput = $FinalExe
        publishState = $publish.PublishState
        sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
        bytes = (Get-Item -LiteralPath $exe).Length
        oneDir = [bool]$OneDir
        signatureStatus = [string]$signature.Status
        signatureSubject = if ($signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { $null }
        smokeTest = if ($SkipSmokeTest) { "skipped" } else { "passed" }
        sendInputAcceptance = "manual_gate_required"
    }
    $manifestLeaf = if ($publish.PrimaryPath) { "TEK-build-manifest.json" } else { ([System.IO.Path]::GetFileNameWithoutExtension($exe) + "-build-manifest.json") }
    $manifestPath = Join-Path (Split-Path -Parent $exe) $manifestLeaf
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host "Built: $exe"
    Write-Host "Manifest: $manifestPath"
    if (-not $publish.PrimaryPath) {
        Write-Warning "Primary dist target remains in use. Close the locking program, then rerun TEKEXEBUILD.CMD to republish the current build at $FinalExe."
    }
    Write-Host "Next required Windows gate: .\scripts\verify-tek-sendinput.ps1 -TekExe $exe"
} finally {
    if (Test-Path -LiteralPath $StageRoot) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
