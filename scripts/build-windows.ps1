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
    Build directory path. Default: .\build

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

    [string]$BuildDir = "build",

    [int]$Jobs = $env:NUMBER_OF_PROCESSORS
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== MLIR Tutorial Windows Build Script ===" -ForegroundColor Cyan
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

$env:Path = "$msys2Path\mingw64\bin;$env:Path"

# Verify cmake is accessible
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

# Create build directory
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
    Write-Host "  Created $BuildDir" -ForegroundColor Gray
}

# Configure CMake
Write-Host "`n[4/6] Configuring CMake..." -ForegroundColor Green

$cmakeArgs = @(
    "-G", "Ninja",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DMLIR_DIR=$msys2Path/mingw64/lib/cmake/mlir",
    "-DLLVM_DIR=$msys2Path/mingw64/lib/cmake/llvm"
)

if ($DisableOrTools) {
    $cmakeArgs += "-DENABLE_ORTOOLS=OFF"
    Write-Host "  or-tools disabled" -ForegroundColor Yellow
}

$cmakeArgs += ".."

Push-Location $BuildDir
try {
    Write-Host "  Running: cmake $($cmakeArgs -join ' ')" -ForegroundColor Gray
    & "$msys2Path\mingw64\bin\cmake.exe" $cmakeArgs

    if ($LASTEXITCODE -ne 0) {
        throw "CMake configuration failed with exit code $LASTEXITCODE"
    }

    Write-Host "  CMake configuration successful" -ForegroundColor Gray

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
