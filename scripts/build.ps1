#Requires -Version 5.1
<#
.SYNOPSIS
    MediaHasher - Windows build driver.

.DESCRIPTION
    Wraps the Conan + CMake steps needed to build MediaHasher on Windows,
    mirroring the targets the Makefile provides on macOS and Linux.

    Run from the repository root.

.PARAMETER Target
    app        Build the application (default). Builds the core library too.
    run        Build, then run the application.
    core       Build the core library, CLI and unit tests standalone.
    test       Run the core unit tests via ctest.
    dist       Stage a distributable folder in dist\MediaHasher.
    zip        Stage, then compress to a versioned .zip.
    clean      Remove build artifacts, keep the CMake configuration.
    distclean  Remove the build and dist directories entirely.
    help       Show this summary.

.PARAMETER BuildType
    Debug (default) or Release.

.PARAMETER QtPrefix
    Qt installation prefix. Auto-detected when omitted.

.PARAMETER Generator
    CMake generator. Left to CMake's default when omitted.

.PARAMETER Jobs
    Parallel build jobs. Defaults to the processor count.

.EXAMPLE
    .\scripts\build.ps1
    .\scripts\build.ps1 app -BuildType Release -Jobs 6
    .\scripts\build.ps1 zip -BuildType Release

.NOTES
    PowerShell blocks unsigned scripts by default. Either run:
        powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1
    or allow local scripts once, for your user only:
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

    SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('app', 'run', 'core', 'test', 'dist', 'zip', 'clean', 'distclean', 'help')]
    [string]$Target = 'app',

    [ValidateSet('Debug', 'Release')]
    [string]$BuildType = 'Debug',

    [string]$QtPrefix = '',

    [string]$Generator = '',

    [int]$Jobs = 0
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
#
# Each build type gets its own directory. CMAKE_BUILD_TYPE is baked into the
# CMake cache at configure time, so sharing one directory between Debug and
# Release would silently keep whichever was configured first.
# ---------------------------------------------------------------------------
$RepoRoot     = Split-Path -Parent $PSScriptRoot
$Suffix       = $BuildType.ToLower()
$AppBuildDir  = Join-Path $RepoRoot "build\win-$Suffix"
$CoreBuildDir = Join-Path $RepoRoot "build\core-$Suffix"
$DistRoot     = Join-Path $RepoRoot 'dist'
$DistDir      = Join-Path $DistRoot 'MediaHasher'

if ($Jobs -le 0) {
    $Jobs = [Environment]::ProcessorCount
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Detail {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

# CMake treats backslashes in -D values as escape characters, so every path
# handed to it must use forward slashes.
function ConvertTo-CMakePath {
    param([string]$Path)
    return ($Path -replace '\\', '/')
}

# Native commands do not raise terminating errors, so exit codes are checked
# explicitly rather than trusting $ErrorActionPreference.
function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    Write-Detail "$Exe $($Arguments -join ' ')"
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Exe exited with code $LASTEXITCODE"
    }
}

function Assert-Command {
    param([string]$Name, [string]$Hint)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "$Name not found on PATH. $Hint"
    }
}

function Assert-RepoRoot {
    if (-not (Test-Path (Join-Path $RepoRoot 'ui\CMakeLists.txt'))) {
        throw "ui\CMakeLists.txt not found under $RepoRoot. Is this the MediaHasher repository?"
    }
}

# ui\VERSION.txt is the single source of truth for the application version
# (ui\CMakeLists.txt feeds project() from the same file); artifacts are
# named after it so a release zip is identifiable without opening it.
function Get-ProjectVersion {
    $versionFile = Join-Path $RepoRoot 'ui\VERSION.txt'
    # Guarded rather than assumed: Show-Help calls this without
    # Assert-RepoRoot, and with ErrorActionPreference = Stop a missing
    # file would turn 'help' into a crash.
    if (-not (Test-Path $versionFile)) {
        return 'unversioned'
    }
    $version = (Get-Content -Path $versionFile -Raw).Trim()
    if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
        Write-Warning "ui\VERSION.txt does not contain a semantic version; artifacts will be named 'unversioned'."
        return 'unversioned'
    }
    return $version
}

# ---------------------------------------------------------------------------
# Qt discovery
#
# Checked in order: -QtPrefix, the QTDIR environment variable, then the Qt
# online installer's usual locations. A candidate only counts if it actually
# contains Qt6Config.cmake.
# ---------------------------------------------------------------------------
function Find-QtPrefix {
    $candidates = New-Object System.Collections.Generic.List[string]

    if ($QtPrefix)   { $candidates.Add($QtPrefix) }
    if ($env:QTDIR)  { $candidates.Add($env:QTDIR) }

    $roots = @('C:\Qt', (Join-Path $env:USERPROFILE 'Qt'))
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }

        $versions = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' } |
            Sort-Object -Descending -Property @{
                Expression = {
                    try { [version]($_.Name -replace '[^\d.].*$', '') }
                    catch { [version]'0.0' }
                }
            }

        foreach ($v in $versions) {
            $kits = Get-ChildItem -Path $v.FullName -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'msvc*_64' } |
                Sort-Object -Descending -Property Name
            foreach ($kit in $kits) { $candidates.Add($kit.FullName) }
        }
    }

    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'lib\cmake\Qt6\Qt6Config.cmake')) {
            return $c
        }
    }

    $searched = ''
    if ($candidates.Count -gt 0) {
        $searched = "`n  Checked:`n    " + ($candidates -join "`n    ")
    }

    throw @"
Qt 6 not found.$searched

  Expected <prefix>\lib\cmake\Qt6\Qt6Config.cmake to exist.

  Point the build at your installation:
      .\scripts\build.ps1 -QtPrefix C:\Qt\6.11.1\msvc2022_64
  or set QTDIR once for your user:
      setx QTDIR C:\Qt\6.11.1\msvc2022_64
"@
}

# ---------------------------------------------------------------------------
# Configure + build
# ---------------------------------------------------------------------------

function Invoke-ConanInstall {
    param([string]$SourceDir, [string]$OutputDir)

    Assert-Command -Name 'conan' -Hint 'Install it with: pip install conan'

    Write-Step "Resolving dependencies with Conan ($BuildType)"
    Invoke-Checked -Exe 'conan' -Arguments @(
        'install', $SourceDir,
        "--output-folder=$OutputDir",
        '--build=missing',
        '-s', "build_type=$BuildType"
    )
}

function Invoke-CMakeConfigure {
    param([string]$SourceDir, [string]$BuildDir, [switch]$NeedsQt)

    Assert-Command -Name 'cmake' -Hint 'Install it from https://cmake.org/download/'

    # The toolchain path must be absolute: CMake resolves a relative
    # CMAKE_TOOLCHAIN_FILE against the build directory, not the working
    # directory, which is a confusing way to fail.
    $toolchain = Join-Path $BuildDir 'conan_toolchain.cmake'
    if (-not (Test-Path $toolchain)) {
        throw "conan_toolchain.cmake not found in $BuildDir. Did 'conan install' succeed?"
    }
    $toolchain = (Resolve-Path $toolchain).Path

    $cmakeArgs = New-Object System.Collections.Generic.List[string]
    $cmakeArgs.AddRange([string[]]@('-S', (ConvertTo-CMakePath $SourceDir)))
    $cmakeArgs.AddRange([string[]]@('-B', (ConvertTo-CMakePath $BuildDir)))

    if ($Generator) {
        $cmakeArgs.AddRange([string[]]@('-G', $Generator))
    }

    $cmakeArgs.Add("-DCMAKE_TOOLCHAIN_FILE=$(ConvertTo-CMakePath $toolchain)")

    # Passed even under multi-config generators, where the generator itself
    # ignores it: ui/CMakeLists.txt keys its Windows console-subsystem branch
    # off CMAKE_BUILD_TYPE, and the build step below uses the same value.
    $cmakeArgs.Add("-DCMAKE_BUILD_TYPE=$BuildType")

    if ($NeedsQt) {
        $qt = Find-QtPrefix
        Write-Detail "Qt: $qt"
        $cmakeArgs.Add("-DCMAKE_PREFIX_PATH=$(ConvertTo-CMakePath $qt)")
    }

    Write-Step "Configuring $SourceDir"
    Invoke-Checked -Exe 'cmake' -Arguments $cmakeArgs.ToArray()
}

function Invoke-CMakeBuild {
    param([string]$BuildDir)

    Write-Step "Building ($BuildType, $Jobs jobs)"
    Invoke-Checked -Exe 'cmake' -Arguments @(
        '--build', (ConvertTo-CMakePath $BuildDir),
        '--config', $BuildType,
        '--parallel', "$Jobs"
    )
}

function Build-App {
    Assert-RepoRoot
    $src = Join-Path $RepoRoot 'ui'
    Invoke-ConanInstall  -SourceDir $src -OutputDir $AppBuildDir
    Invoke-CMakeConfigure -SourceDir $src -BuildDir $AppBuildDir -NeedsQt
    Invoke-CMakeBuild     -BuildDir $AppBuildDir
    $exe = Find-AppExecutable
    Write-Step "Built: $exe"
}

function Build-Core {
    Assert-RepoRoot
    $src = Join-Path $RepoRoot 'MediaHash'
    Invoke-ConanInstall  -SourceDir $src -OutputDir $CoreBuildDir
    Invoke-CMakeConfigure -SourceDir $src -BuildDir $CoreBuildDir
    Invoke-CMakeBuild     -BuildDir $CoreBuildDir
}

# ---------------------------------------------------------------------------
# Output discovery
#
# Multi-config generators place binaries in a per-config subdirectory while
# single-config generators do not, so the executable is located rather than
# assumed.
# ---------------------------------------------------------------------------
function Find-AppExecutable {
    if (-not (Test-Path $AppBuildDir)) {
        throw "Build directory $AppBuildDir does not exist. Run: .\scripts\build.ps1 app"
    }
    $exe = Get-ChildItem -Path $AppBuildDir -Filter 'MediaHasher.exe' -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $exe) {
        throw "MediaHasher.exe not found under $AppBuildDir. Did the build succeed?"
    }
    return $exe.FullName
}

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

function Invoke-Run {
    Build-App
    $exe = Find-AppExecutable
    Write-Step "Running $exe"
    & $exe
}

function Invoke-Test {
    Build-Core
    Assert-Command -Name 'ctest' -Hint 'It ships with CMake.'
    Write-Step 'Running core unit tests'
    Invoke-Checked -Exe 'ctest' -Arguments @(
        '--test-dir', (ConvertTo-CMakePath $CoreBuildDir),
        '--build-config', $BuildType,
        '--output-on-failure'
    )
}

function Invoke-Dist {
    Build-App
    $exe = Find-AppExecutable
    $srcDir = Split-Path -Parent $exe

    Write-Step "Staging $DistDir"

    if (Test-Path $DistDir) {
        Remove-Item -Path $DistDir -Recurse -Force
    }
    New-Item -Path $DistDir -ItemType Directory -Force | Out-Null

    # windeployqt runs as a POST_BUILD step and drops the Qt runtime beside
    # the executable, so copying that directory captures the whole payload.
    Copy-Item -Path (Join-Path $srcDir '*') -Destination $DistDir -Recurse -Force

    # Build system leftovers that should not ship.
    Get-ChildItem -Path $DistDir -Include '*.ilk', '*.exp', '*.lib', '*.pdb' -Recurse -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # Qt runtime payload this application never exercises. windeployqt
    # deploys by framework category, not by what the application actually
    # loads, so all of the following arrive uninvited:
    #
    #   opengl32sw.dll     software OpenGL rasterizer, used only when the
    #                      RHI is forced to OpenGL on a machine with no
    #                      working GPU driver; Qt Quick renders through
    #                      Direct3D 11 on Windows
    #   dxcompiler.dll     Direct3D 12 shader toolchain, used only by the
    #   dxil.dll           D3D12 RHI backend when compiling at runtime
    #   D3Dcompiler_47.dll runtime HLSL compiler; Qt Quick ships its
    #                      shaders precompiled (qsb), so nothing compiles
    #                      shaders at runtime
    #   translations\      Qt's own UI translations; the application is
    #                      US English only
    #   qmltooling\        QML debugger and profiler server plugins,
    #                      which have no place in a release artifact
    #   generic\           TUIO network-touch input plugin, unused
    #
    # If a Qt upgrade ever changes rendering behavior on machines without
    # GPU drivers, opengl32sw.dll and D3Dcompiler_47.dll are the first
    # candidates to restore.
    $unusedFiles = @('opengl32sw.dll', 'dxcompiler.dll', 'dxil.dll', 'D3Dcompiler_47.dll')
    foreach ($name in $unusedFiles) {
        $path = Join-Path $DistDir $name
        if (Test-Path $path) {
            Remove-Item -Path $path -Force
            Write-Detail "pruned $name"
        }
    }
    $unusedDirs = @('translations', 'qmltooling', 'generic')
    foreach ($name in $unusedDirs) {
        $path = Join-Path $DistDir $name
        if (Test-Path $path) {
            Remove-Item -Path $path -Recurse -Force
            Write-Detail "pruned $name\"
        }
    }

    # Sweep empty directories, deepest first so a parent emptied by its
    # children's removal is caught in the same pass. windeployqt creates
    # the full QML module skeleton (including Controls style directories
    # this build ships no files for), and the prunes above can hollow out
    # others; either way an empty directory in the zip is noise.
    Get-ChildItem -Path $DistDir -Directory -Recurse |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue) } |
        ForEach-Object {
            Write-Detail "pruned empty $($_.FullName.Substring($DistDir.Length + 1))\"
            Remove-Item -Path $_.FullName -Force
        }

    $cli = Join-Path $DistDir 'mediahash.exe'
    if (Test-Path $cli) {
        Write-Detail 'mediahash.exe included'
    }
    else {
        Write-Warning "mediahash.exe is not in the staged output. The CLI target may not be co-located with the application yet."
    }

    $size = (Get-ChildItem -Path $DistDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Detail ("{0} files, {1:N1} MB" -f `
        (Get-ChildItem -Path $DistDir -Recurse -File).Count, ($size / 1MB))
    Write-Step "Staged: $DistDir"
}

function Invoke-Zip {
    Invoke-Dist
    $version = Get-ProjectVersion
    # Release artifacts carry no build-type suffix (they are the ones
    # published on GitHub); anything else is marked so a Debug zip can
    # never masquerade as a release.
    $typeTag = if ($BuildType -eq 'Release') { '' } else { "-$Suffix" }
    $zip = Join-Path $DistRoot "MediaHasher-$version-windows-x64$typeTag.zip"
    if (Test-Path $zip) {
        Remove-Item -Path $zip -Force
    }
    Write-Step "Compressing $zip"
    # Prefer bsdtar (ships with Windows 10 1803+): it writes forward-slash
    # entry separators, whereas Compress-Archive on Windows PowerShell 5.1
    # writes backslashes, which confuses some non-Windows unzip tools.
    $tar = Get-Command 'tar.exe' -ErrorAction SilentlyContinue
    if ($tar) {
        Invoke-Checked -Exe $tar.Source -Arguments @(
            '-a', '-c',
            '-f', $zip,
            '-C', $DistRoot,
            'MediaHasher'
        )
    }
    else {
        Compress-Archive -Path $DistDir -DestinationPath $zip -CompressionLevel Optimal
    }
    $mb = (Get-Item $zip).Length / 1MB
    Write-Step ("Created: {0} ({1:N1} MB)" -f $zip, $mb)
}

function Invoke-Clean {
    foreach ($dir in @($AppBuildDir, $CoreBuildDir)) {
        if (Test-Path $dir) {
            Write-Step "Cleaning $dir"
            & cmake --build $dir --config $BuildType --target clean
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "clean target failed in $dir; use distclean to remove it outright."
            }
        }
        else {
            Write-Detail "nothing to clean in $dir"
        }
    }
}

function Invoke-DistClean {
    foreach ($dir in @((Join-Path $RepoRoot 'build'), $DistRoot)) {
        if (Test-Path $dir) {
            Write-Step "Removing $dir"
            Remove-Item -Path $dir -Recurse -Force
        }
    }
}

function Show-Help {
    Write-Host ''
    Write-Host 'MediaHasher - Windows build' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  app         Build the application (default). Builds the core too.'
    Write-Host '  run         Build, then run the application.'
    Write-Host '  core        Build the core library, CLI and tests standalone.'
    Write-Host '  test        Run the core unit tests via ctest.'
    Write-Host '  dist        Stage a distributable folder in dist\MediaHasher.'
    Write-Host '  zip         Stage, then compress to a versioned .zip.'
    Write-Host '  clean       Remove build artifacts, keep the CMake configuration.'
    Write-Host '  distclean   Remove the build and dist directories entirely.'
    Write-Host ''
    Write-Host 'Common workflows:' -ForegroundColor Cyan
    Write-Host '  .\scripts\build.ps1 -Jobs 6'
    Write-Host '  .\scripts\build.ps1 run'
    Write-Host '  .\scripts\build.ps1 zip -BuildType Release'
    Write-Host ''
    Write-Host 'Current settings:' -ForegroundColor Cyan
    Write-Host "  Version      $(Get-ProjectVersion)"
    Write-Host "  BuildType    $BuildType"
    Write-Host "  Jobs         $Jobs"
    Write-Host "  AppBuildDir  $AppBuildDir"
    Write-Host "  CoreBuildDir $CoreBuildDir"
    if ($Generator) { Write-Host "  Generator    $Generator" }
    else            { Write-Host "  Generator    (CMake default)" }
    try   { Write-Host "  Qt           $(Find-QtPrefix)" }
    catch { Write-Host "  Qt           not found" -ForegroundColor Yellow }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
try {
    switch ($Target) {
        'app'       { Build-App }
        'run'       { Invoke-Run }
        'core'      { Build-Core }
        'test'      { Invoke-Test }
        'dist'      { Invoke-Dist }
        'zip'       { Invoke-Zip }
        'clean'     { Invoke-Clean }
        'distclean' { Invoke-DistClean }
        'help'      { Show-Help }
    }
}
catch {
    Write-Host ''
    Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
    exit 1
}
