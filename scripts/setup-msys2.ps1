#Requires -Version 5.1

<#
.SYNOPSIS
    Automated MSYS2 setup for MLIR tutorial on Windows

.DESCRIPTION
    This script automates the installation and configuration of MSYS2 with
    LLVM/MLIR toolchain for the mlir-tutorial on Windows.

.PARAMETER InstallPath
    MSYS2 installation path. Default: C:\msys64

.PARAMETER SkipMSYS2Install
    Skip MSYS2 installation (use if already installed)

.PARAMETER SkipPathSetup
    Skip adding MSYS2 to Windows PATH

.EXAMPLE
    .\scripts\setup-msys2.ps1
    Full automated setup

.EXAMPLE
    .\scripts\setup-msys2.ps1 -SkipMSYS2Install
    Configure existing MSYS2 installation

.EXAMPLE
    .\scripts\setup-msys2.ps1 -InstallPath D:\msys64
    Install to D: drive
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\msys64",

    [switch]$SkipMSYS2Install,

    [switch]$SkipPathSetup
)

$ErrorActionPreference = 'Stop'

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║   MLIR Tutorial - Windows MSYS2 Setup Script                 ║
║   Sets up MSYS2 with LLVM/MLIR for native Windows dev       ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Warning @"
This script should be run as Administrator to:
  - Install MSYS2 via winget/choco
  - Modify system PATH environment variable

If you don't have admin rights:
  1. Manually install MSYS2 from https://www.msys2.org/
  2. Run this script with -SkipMSYS2Install -SkipPathSetup
  3. Manually add to your user PATH: $InstallPath\mingw64\bin

Continue anyway? (Press Ctrl+C to cancel)
"@
    Read-Host "Press Enter to continue"
}

# Step 1: Install MSYS2
if (-not $SkipMSYS2Install) {
    Write-Host "`n[1/5] Installing MSYS2..." -ForegroundColor Green

    if (Test-Path $InstallPath) {
        Write-Host "  MSYS2 already exists at $InstallPath" -ForegroundColor Yellow
        $response = Read-Host "  Reinstall? (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host "  Skipping MSYS2 installation" -ForegroundColor Gray
            $SkipMSYS2Install = $true
        }
    }

    if (-not $SkipMSYS2Install) {
        # Try winget first
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Host "  Installing via winget..." -ForegroundColor Gray
            winget install --id MSYS2.MSYS2 --silent --accept-source-agreements --accept-package-agreements

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  MSYS2 installed successfully" -ForegroundColor Gray
            } else {
                Write-Warning "winget installation failed, trying chocolatey..."
                if (Get-Command choco -ErrorAction SilentlyContinue) {
                    choco install msys2 -y
                } else {
                    Write-Error @"
Failed to install MSYS2 automatically.

Please install manually:
  1. Download from: https://www.msys2.org/
  2. Run the installer
  3. Re-run this script with -SkipMSYS2Install
"@
                }
            }
        } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "  Installing via chocolatey..." -ForegroundColor Gray
            choco install msys2 -y
        } else {
            Write-Error @"
No package manager found (winget or chocolatey).

Please install MSYS2 manually from: https://www.msys2.org/
Then re-run this script with -SkipMSYS2Install
"@
        }
    }
} else {
    Write-Host "`n[1/5] Skipping MSYS2 installation..." -ForegroundColor Green
}

# Verify MSYS2 exists
if (-not (Test-Path $InstallPath)) {
    Write-Error "MSYS2 not found at $InstallPath"
}

Write-Host "  MSYS2 found at: $InstallPath" -ForegroundColor Gray

# Step 2: Update MSYS2
Write-Host "`n[2/5] Updating MSYS2..." -ForegroundColor Green

$msysBash = "$InstallPath\usr\bin\bash.exe"
if (-not (Test-Path $msysBash)) {
    Write-Error "MSYS2 bash not found at $msysBash"
}

Write-Host "  Running pacman -Syu..." -ForegroundColor Gray
& $msysBash -lc "pacman -Syu --noconfirm"

# Step 3: Install LLVM/MLIR packages
Write-Host "`n[3/5] Installing LLVM/MLIR toolchain..." -ForegroundColor Green

$packages = @(
    "mingw-w64-x86_64-llvm",
    "mingw-w64-x86_64-clang",
    "mingw-w64-x86_64-mlir",
    "mingw-w64-x86_64-cmake",
    "mingw-w64-x86_64-ninja",
    "mingw-w64-x86_64-gcc",
    "mingw-w64-x86_64-pkgconf"
)

Write-Host "  Installing packages:" -ForegroundColor Gray
foreach ($pkg in $packages) {
    Write-Host "    - $pkg" -ForegroundColor DarkGray
}

$packageList = $packages -join " "
& $msysBash -lc "export MSYSTEM=MINGW64 && pacman -S --noconfirm $packageList"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install MLIR/LLVM packages"
}

Write-Host "  Packages installed successfully" -ForegroundColor Gray

# Step 4: Verify installation
Write-Host "`n[4/5] Verifying installation..." -ForegroundColor Green

$toolsToVerify = @(
    "mlir-opt.exe",
    "mlir-translate.exe",
    "llc.exe",
    "cmake.exe",
    "ninja.exe"
)

$allFound = $true
foreach ($tool in $toolsToVerify) {
    $toolPath = "$InstallPath\mingw64\bin\$tool"
    if (Test-Path $toolPath) {
        Write-Host "  Found: $tool" -ForegroundColor Gray
    } else {
        Write-Warning "Missing: $tool"
        $allFound = $false
    }
}

if (-not $allFound) {
    Write-Error "Some tools are missing. Installation may have failed."
}

# Step 5: Configure PATH
if (-not $SkipPathSetup) {
    Write-Host "`n[5/5] Configuring Windows PATH..." -ForegroundColor Green

    $mingw64Path = "$InstallPath\mingw64\bin"
    $msysUsrPath = "$InstallPath\usr\bin"

    $currentPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)

    $needsUpdate = $false
    $pathsToAdd = @()

    if ($currentPath -notlike "*$mingw64Path*") {
        $pathsToAdd += $mingw64Path
        $needsUpdate = $true
    }

    if ($currentPath -notlike "*$msysUsrPath*") {
        $pathsToAdd += $msysUsrPath
        $needsUpdate = $true
    }

    if ($needsUpdate) {
        try {
            $newPath = $currentPath
            foreach ($pathToAdd in $pathsToAdd) {
                $newPath = "$newPath;$pathToAdd"
                Write-Host "  Adding to PATH: $pathToAdd" -ForegroundColor Gray
            }

            [Environment]::SetEnvironmentVariable(
                "Path",
                $newPath,
                [EnvironmentVariableTarget]::Machine
            )

            Write-Host "  PATH updated successfully" -ForegroundColor Gray
            Write-Warning "  Please restart PowerShell for PATH changes to take effect"
        } catch {
            Write-Warning @"
Failed to update system PATH automatically.

Please add these paths manually to your system PATH:
  1. $mingw64Path
  2. $msysUsrPath

Instructions:
  1. Open System Properties > Environment Variables
  2. Edit the system 'Path' variable
  3. Add the paths above
"@
        }
    } else {
        Write-Host "  PATH already configured" -ForegroundColor Gray
    }
} else {
    Write-Host "`n[5/5] Skipping PATH setup..." -ForegroundColor Green
    Write-Host @"

  To use MLIR tools, add to your PATH:
    $InstallPath\mingw64\bin
    $InstallPath\usr\bin

"@ -ForegroundColor Yellow
}

# Summary
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                   Setup Complete!                            ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "MSYS2 Location: " -NoNewline -ForegroundColor Yellow
Write-Host "$InstallPath" -ForegroundColor White

Write-Host "`nInstalled Tools:" -ForegroundColor Yellow
Write-Host "  - LLVM/MLIR toolchain" -ForegroundColor Gray
Write-Host "  - CMake + Ninja build system" -ForegroundColor Gray
Write-Host "  - GCC/Clang compilers" -ForegroundColor Gray

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. " -NoNewline -ForegroundColor Gray
Write-Host "Restart PowerShell" -ForegroundColor White -NoNewline
Write-Host " (to apply PATH changes)" -ForegroundColor Gray

Write-Host "  2. Verify installation:" -ForegroundColor Gray
Write-Host "     mlir-opt --version" -ForegroundColor DarkGray

Write-Host "  3. Build the tutorial:" -ForegroundColor Gray
Write-Host "     .\scripts\build-windows.ps1" -ForegroundColor DarkGray

Write-Host "`nFor more information, see README.md" -ForegroundColor Yellow
Write-Host ""
