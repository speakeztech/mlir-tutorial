#Requires -Version 5.1

<#
.SYNOPSIS
    Verify MSYS2/MinGW64 setup for MLIR tutorial

.DESCRIPTION
    This script checks that all required tools are installed and configured
    correctly for Windows-native MLIR development.

.EXAMPLE
    .\scripts\verify-setup.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║   MLIR Tutorial - Setup Verification                         ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$script:allPassed = $true

function Test-Requirement {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$SuccessMessage,
        [string]$FailureMessage,
        [string]$FixSuggestion
    )

    Write-Host "`n[$Name]" -ForegroundColor Yellow -NoNewline

    try {
        $result = & $Test
        if ($result) {
            Write-Host " ✓" -ForegroundColor Green
            if ($SuccessMessage) {
                Write-Host "  $SuccessMessage" -ForegroundColor Gray
            }
            return $true
        } else {
            throw "Test failed"
        }
    } catch {
        Write-Host " ✗" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "  $FailureMessage" -ForegroundColor Red
        }
        if ($FixSuggestion) {
            Write-Host "  Fix: $FixSuggestion" -ForegroundColor Yellow
        }
        $script:allPassed = $false
        return $false
    }
}

# Test 1: MSYS2 Installation
Test-Requirement -Name "MSYS2 Installation" -Test {
    $msys2Paths = @("C:\msys64", "D:\msys64")
    foreach ($path in $msys2Paths) {
        if (Test-Path "$path\mingw64\bin") {
            return $path
        }
    }
    return $null
} -SuccessMessage "Found MSYS2 installation" `
  -FailureMessage "MSYS2 not found" `
  -FixSuggestion "Run: .\scripts\setup-msys2.ps1"

# Test 2: mlir-opt executable
$mlirOptFound = Test-Requirement -Name "mlir-opt" -Test {
    $path = Get-Command mlir-opt -ErrorAction SilentlyContinue
    if ($path) {
        Write-Host "  Path: $($path.Source)" -ForegroundColor Gray
        return $true
    }
    return $false
} -FailureMessage "mlir-opt not found in PATH" `
  -FixSuggestion "Install: pacman -S mingw-w64-x86_64-mlir (in MINGW64 terminal)"

# Test 3: Verify mlir-opt is MINGW64 version (not MSYS)
if ($mlirOptFound) {
    Test-Requirement -Name "mlir-opt (MINGW64)" -Test {
        $path = (Get-Command mlir-opt).Source
        if ($path -like "*\mingw64\bin\*") {
            return $true
        }
        throw "Wrong version: $path"
    } -SuccessMessage "Correct MINGW64 version" `
      -FailureMessage "Using MSYS version instead of MINGW64" `
      -FixSuggestion "Update PATH to prioritize C:\msys64\mingw64\bin"
}

# Test 4: cmake
Test-Requirement -Name "CMake" -Test {
    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    if ($cmake) {
        $version = & cmake --version | Select-Object -First 1
        Write-Host "  $version" -ForegroundColor Gray
        return $true
    }
    return $false
} -FailureMessage "CMake not found" `
  -FixSuggestion "Install: pacman -S mingw-w64-x86_64-cmake (in MINGW64 terminal)"

# Test 5: ninja
Test-Requirement -Name "Ninja" -Test {
    $ninja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($ninja) {
        $version = & ninja --version
        Write-Host "  Version: $version" -ForegroundColor Gray
        return $true
    }
    return $false
} -FailureMessage "Ninja not found" `
  -FixSuggestion "Install: pacman -S mingw-w64-x86_64-ninja (in MINGW64 terminal)"

# Test 6: clang
Test-Requirement -Name "Clang" -Test {
    $clang = Get-Command clang -ErrorAction SilentlyContinue
    if ($clang) {
        $version = & clang --version | Select-Object -First 1
        Write-Host "  $version" -ForegroundColor Gray
        return $true
    }
    return $false
} -FailureMessage "Clang not found" `
  -FixSuggestion "Install: pacman -S mingw-w64-x86_64-clang (in MINGW64 terminal)"

# Test 7: MLIR tools
$mlirTools = @("mlir-translate", "mlir-tblgen", "llc", "opt")
foreach ($tool in $mlirTools) {
    Test-Requirement -Name $tool -Test {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        return $null -ne $cmd
    } -FailureMessage "$tool not found" `
      -FixSuggestion "Install: pacman -S mingw-w64-x86_64-llvm mingw-w64-x86_64-mlir"
}

# Test 8: MLIR cmake config files
Test-Requirement -Name "MLIR CMake Config" -Test {
    $paths = @("C:\msys64\mingw64\lib\cmake\mlir", "D:\msys64\mingw64\lib\cmake\mlir")
    foreach ($path in $paths) {
        if (Test-Path "$path\MLIRConfig.cmake") {
            Write-Host "  Found: $path" -ForegroundColor Gray
            return $true
        }
    }
    return $false
} -FailureMessage "MLIR CMake config not found" `
  -FixSuggestion "Reinstall: pacman -S mingw-w64-x86_64-mlir --force"

# Test 9: LLVM cmake config files
Test-Requirement -Name "LLVM CMake Config" -Test {
    $paths = @("C:\msys64\mingw64\lib\cmake\llvm", "D:\msys64\mingw64\lib\cmake\llvm")
    foreach ($path in $paths) {
        if (Test-Path "$path\LLVMConfig.cmake") {
            Write-Host "  Found: $path" -ForegroundColor Gray
            return $true
        }
    }
    return $false
} -FailureMessage "LLVM CMake config not found" `
  -FixSuggestion "Reinstall: pacman -S mingw-w64-x86_64-llvm --force"

# Test 10: Git
Test-Requirement -Name "Git" -Test {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $version = & git --version
        Write-Host "  $version" -ForegroundColor Gray
        return $true
    }
    return $false
} -FailureMessage "Git not found" `
  -FixSuggestion "Install Git for Windows from https://git-scm.com/"

# Test 11: PowerShell version
Test-Requirement -Name "PowerShell Version" -Test {
    $version = $PSVersionTable.PSVersion
    Write-Host "  Version: $version" -ForegroundColor Gray
    return $version.Major -ge 5
} -FailureMessage "PowerShell version too old" `
  -FixSuggestion "Upgrade to PowerShell 5.1 or newer"

# Test 12: Verify mlir-opt works
if ($mlirOptFound) {
    Test-Requirement -Name "mlir-opt (functional test)" -Test {
        $output = & mlir-opt --version 2>&1
        return $output -match "MLIR|LLVM"
    } -SuccessMessage "mlir-opt executes correctly" `
      -FailureMessage "mlir-opt fails to execute" `
      -FixSuggestion "Check for missing DLL dependencies"
}

# Summary
Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    Verification Summary                      ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

if ($script:allPassed) {
    Write-Host "✓ All checks passed!" -ForegroundColor Green
    Write-Host "`nYour system is ready for MLIR development." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Build the tutorial: .\scripts\build-windows.ps1" -ForegroundColor Gray
    Write-Host "  2. Run tutorial-opt: .\build\bin\tutorial-opt.exe --help" -ForegroundColor Gray
    Write-Host "  3. Try an example: .\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir" -ForegroundColor Gray
} else {
    Write-Host "✗ Some checks failed" -ForegroundColor Red
    Write-Host "`nPlease fix the issues above before building." -ForegroundColor Yellow
    Write-Host "`nFor detailed setup instructions, see:" -ForegroundColor Yellow
    Write-Host "  - QUICKSTART.md (fast setup)" -ForegroundColor Gray
    Write-Host "  - WINDOWS_SETUP.md (comprehensive guide)" -ForegroundColor Gray
    Write-Host "`nOr run automated setup:" -ForegroundColor Yellow
    Write-Host "  .\scripts\setup-msys2.ps1" -ForegroundColor Gray
}

Write-Host ""

# Exit with appropriate code
if ($script:allPassed) {
    exit 0
} else {
    exit 1
}
