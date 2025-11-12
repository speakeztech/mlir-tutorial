#Requires -Version 5.1

<#
.SYNOPSIS
    Build mlir-tutorial on Windows using MSYS2/MinGW64 toolchain

.DESCRIPTION
    This script automates the build process for the mlir-tutorial on Windows.
    It detects MSYS2 installation, configures CMake, and builds the project.

.PARAMETER BuildType
    Build configuration (Debug or Release). Default: Debug

.PARAMETER Clean
    Remove build directory before building

.PARAMETER DisableOrTools
    Disable or-tools dependency (useful if download fails)

.PARAMETER BuildDir
    Build directory path. Default: .\cmake-build (avoids conflict with Bazel BUILD file on Windows)

.PARAMETER Jobs
    Number of parallel build jobs. Default: CPU count

.EXAMPLE
    .\scripts\build-windows.ps1
    Build in Debug mode

.EXAMPLE
    .\scripts\build-windows.ps1 -BuildType Release -Clean
    Clean build in Release mode

.EXAMPLE
    .\scripts\build-windows.ps1 -DisableOrTools
    Build without or-tools dependency
#>

[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$BuildType = 'Debug',

    [switch]$Clean,

    [switch]$DisableOrTools,

    [string]$BuildDir = "cmake-build",

    [int]$Jobs = $env:NUMBER_OF_PROCESSORS
)

$ErrorActionPreference = 'Stop'

# Ensure we're running from the repository root
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Set-Location $repoRoot

Write-Host "`n=== MLIR Tutorial Windows Build Script ===" -ForegroundColor Cyan
Write-Host "Repository Root: $repoRoot" -ForegroundColor Yellow
Write-Host "Build Type: $BuildType" -ForegroundColor Yellow
Write-Host "Build Directory: $BuildDir" -ForegroundColor Yellow

# Detect MSYS2 installation
function Find-MSYS2 {
    $possiblePaths = @(
        "C:\msys64",
        "D:\msys64",
        "$env:SystemDrive\msys64"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\mingw64\bin") {
            return $path
        }
    }

    return $null
}

# Check prerequisites
Write-Host "`n[1/6] Checking prerequisites..." -ForegroundColor Green

$msys2Path = Find-MSYS2
if (-not $msys2Path) {
    Write-Error @"
MSYS2 not found!

Please install MSYS2 first:
    winget install --id MSYS2.MSYS2

Or download from: https://www.msys2.org/

Then install LLVM/MLIR packages:
    pacman -S mingw-w64-x86_64-llvm mingw-w64-x86_64-clang mingw-w64-x86_64-mlir \
              mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
"@
}

Write-Host "  Found MSYS2 at: $msys2Path" -ForegroundColor Gray

# Verify tools
$requiredTools = @(
    @{Name = "cmake"; Path = "$msys2Path\mingw64\bin\cmake.exe"},
    @{Name = "ninja"; Path = "$msys2Path\mingw64\bin\ninja.exe"},
    @{Name = "mlir-opt"; Path = "$msys2Path\mingw64\bin\mlir-opt.exe"}
)

foreach ($tool in $requiredTools) {
    if (-not (Test-Path $tool.Path)) {
        Write-Error @"
Required tool '$($tool.Name)' not found at: $($tool.Path)

Please install it in MSYS2 MINGW64 terminal:
    pacman -S mingw-w64-x86_64-$($tool.Name)
"@
    }
    Write-Host "  Found $($tool.Name)" -ForegroundColor Gray
}

# Set up environment
Write-Host "`n[2/6] Setting up environment..." -ForegroundColor Green

# Verify cmake is accessible (but don't modify PATH yet)
$cmakeVersion = & "$msys2Path\mingw64\bin\cmake.exe" --version | Select-Object -First 1
Write-Host "  $cmakeVersion" -ForegroundColor Gray

# Clean build directory if requested
if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "`n[3/6] Cleaning build directory..." -ForegroundColor Green
    Remove-Item -Path $BuildDir -Recurse -Force
    Write-Host "  Removed $BuildDir" -ForegroundColor Gray
} else {
    Write-Host "`n[3/6] Using existing build directory..." -ForegroundColor Green
}

# Create build directory BEFORE modifying PATH (to avoid MSYS2 interference)
$BuildDirAbsolute = Join-Path $repoRoot $BuildDir
Write-Host "  Absolute build path: $BuildDirAbsolute" -ForegroundColor Gray

if (-not (Test-Path $BuildDirAbsolute -PathType Container)) {
    Write-Host "  Creating directory..." -ForegroundColor Gray
    try {
        # Use .NET Framework method directly to avoid any PATH issues
        [System.IO.Directory]::CreateDirectory($BuildDirAbsolute) | Out-Null
        Write-Host "  Created: $BuildDirAbsolute" -ForegroundColor Gray

        # Verify it was created
        if (Test-Path $BuildDirAbsolute -PathType Container) {
            Write-Host "  Verified: Directory exists" -ForegroundColor Green
        } else {
            throw "Directory creation verification failed"
        }
    } catch {
        Write-Host "  ERROR: Directory creation failed: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  Build directory already exists" -ForegroundColor Gray
}

# NOW set MSYS2 in PATH (after directory operations complete)
$env:Path = "$msys2Path\mingw64\bin;$env:Path"

# Configure CMake
Write-Host "`n[4/6] Configuring CMake..." -ForegroundColor Green

$cmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_CXX_FLAGS=-D_USE_MATH_DEFINES -D__MINGW64__",
    "-DCMAKE_CXX_FLAGS_DEBUG=-O0",
    "-DMLIR_DIR=$msys2Path/mingw64/lib/cmake/mlir",
    "-DLLVM_DIR=$msys2Path/mingw64/lib/cmake/llvm"
)

if ($DisableOrTools) {
    $cmakeArgs += "-DENABLE_ORTOOLS=OFF"
    Write-Host "  or-tools disabled" -ForegroundColor Yellow
}

$cmakeArgs += ".."

Push-Location $BuildDirAbsolute
try {
    Write-Host "  Running: cmake $($cmakeArgs -join ' ')" -ForegroundColor Gray
    & "$msys2Path\mingw64\bin\cmake.exe" $cmakeArgs

    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code $LASTEXITCODE"
    }

    Write-Host "  CMake configuration successful" -ForegroundColor Gray

    # Patch HiGHS header file if it exists (attempt to fix compilation issue with GCC 15+)
    $highs_zstr_header = Join-Path $BuildDirAbsolute "_deps\highs-src\extern\zstr\zstr.hpp"
    if (Test-Path $highs_zstr_header) {
        Write-Host "`n  Patching HiGHS zstr.hpp for GCC compatibility..." -ForegroundColor Gray
        $content = Get-Content $highs_zstr_header -Raw
        if ($content -notmatch '#include <cstdint>') {
            $content = $content -replace '(#include <cassert>)', "$1`n#include <cstdint>"
            Set-Content -Path $highs_zstr_header -Value $content -NoNewline
            Write-Host "  Applied cstdint patch" -ForegroundColor Green
        }
    }

    # Patch or-tools aligned_memory header for MinGW compatibility
    $ortools_aligned_header = Join-Path $BuildDirAbsolute "_deps\or-tools-src\ortools\util\aligned_memory_internal.h"
    if (Test-Path $ortools_aligned_header) {
        Write-Host "`n  Patching or-tools aligned_memory_internal.h for MinGW..." -ForegroundColor Gray
        $content = Get-Content $ortools_aligned_header -Raw
        if ($content -notmatch '__MINGW64__') {
            $content = $content -replace '#if !defined\(_MSC_VER\)', '#if !defined(_MSC_VER) && !defined(__MINGW64__)'
            $content = $content -replace '#else', '#elif defined(_MSC_VER) || defined(__MINGW64__)'
            Set-Content -Path $ortools_aligned_header -Value $content -NoNewline
            Write-Host "  Applied MinGW aligned_alloc patch" -ForegroundColor Green
        }
    }

    # Patch or-tools fp_utils header for MinGW compatibility
    $ortools_fp_header = Join-Path $BuildDirAbsolute "_deps\or-tools-src\ortools\util\fp_utils.h"
    if (Test-Path $ortools_fp_header) {
        Write-Host "`n  Patching or-tools fp_utils.h for MinGW..." -ForegroundColor Gray
        $content = Get-Content $ortools_fp_header -Raw
        if ($content -notmatch '__MINGW64__') {
            # Skip fenv manipulation code on MinGW (incompatible fenv_t structure)
            $content = $content -replace '#elif \(defined\(__GNUC__\) \|\| defined\(__llvm__\)\) && defined\(__x86_64__\) && \\', '#elif (defined(__GNUC__) || defined(__llvm__)) && defined(__x86_64__) && !defined(__MINGW64__) && \'
            Set-Content -Path $ortools_fp_header -Value $content -NoNewline
            Write-Host "  Applied MinGW fp_utils patch" -ForegroundColor Green
        }
    }

    # Build
    Write-Host "`n[5/6] Building project..." -ForegroundColor Green
    Write-Host "  Using $Jobs parallel jobs" -ForegroundColor Gray

    & "$msys2Path\mingw64\bin\ninja.exe" -j $Jobs

    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE"
    }

    Write-Host "  Build successful" -ForegroundColor Gray

    # Run tests
    Write-Host "`n[6/6] Running tests..." -ForegroundColor Green

    if (Test-Path ".\bin\tutorial-opt.exe") {
        Write-Host "  Testing tutorial-opt..." -ForegroundColor Gray
        & ".\bin\tutorial-opt.exe" --help | Select-Object -First 3
        Write-Host "  tutorial-opt is working" -ForegroundColor Gray
    }

    # Run test suite if available
    if (& "$msys2Path\mingw64\bin\ninja.exe" -t targets | Select-String -Pattern "check-mlir-tutorial") {
        Write-Host "  Running test suite..." -ForegroundColor Gray
        & "$msys2Path\mingw64\bin\ninja.exe" check-mlir-tutorial

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  All tests passed" -ForegroundColor Green
        } else {
            Write-Warning "Some tests failed"
        }
    }

} finally {
    Pop-Location
}

# Summary
Write-Host "`n=== Build Complete ===" -ForegroundColor Cyan
Write-Host "Build directory: $BuildDir" -ForegroundColor Yellow
Write-Host "Binary location: $BuildDir\bin\tutorial-opt.exe" -ForegroundColor Yellow

if (Test-Path "$BuildDir\bin\tutorial-opt.exe") {
    Write-Host "`nTo run tutorial-opt:" -ForegroundColor Green
    Write-Host "  .\$BuildDir\bin\tutorial-opt.exe --help" -ForegroundColor Gray
    Write-Host "`nTo run examples:" -ForegroundColor Green
    Write-Host "  .\$BuildDir\bin\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize" -ForegroundColor Gray
}

Write-Host ""
