# Windows Native Development Guide for MLIR Tutorial

This guide provides comprehensive instructions for setting up and using the MLIR tutorial on Windows with native tooling (MSYS2/CLANG64), without WSL or virtualization.

## Table of Contents

- [Quick Start](#quick-start)
- [Understanding MSYS2 and CLANG64](#understanding-msys2-and-clang64)
- [Detailed Installation Steps](#detailed-installation-steps)
- [IDE Configuration](#ide-configuration)
- [Building the Tutorial](#building-the-tutorial)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## Quick Start

For experienced users who just want to get started:

```powershell
# 1. Run automated setup (as Administrator)
.\scripts\setup-msys2.ps1

# 2. Restart PowerShell

# 3. Build the tutorial
.\scripts\build-windows.ps1

# 4. Run tutorial-opt
.\build\bin\tutorial-opt.exe --help
```

## Understanding MSYS2 and CLANG64

### What is MSYS2?

**MSYS2** is a software distribution and building platform for Windows that provides:
- A Unix-like environment on Windows
- The `pacman` package manager (from Arch Linux)
- Pre-built packages for development tools, including LLVM/MLIR

### MSYS2 Environments: Critical Distinction

MSYS2 provides **four different environments**:

| Environment | Purpose | Binary Type | Compiler | Use Case |
|-------------|---------|-------------|----------|----------|
| **MSYS** (`/usr/bin`) | Unix compatibility layer | Depends on `msys-2.0.dll` | GCC | Running Unix build scripts |
| **MINGW64** (`/mingw64/bin`) | Native Windows 64-bit | Standalone `.exe` files | GCC | GCC-based Windows development |
| **MINGW32** (`/mingw32/bin`) | Native Windows 32-bit | Standalone `.exe` files | GCC | Legacy 32-bit support |
| **CLANG64** (`/clang64/bin`) | Native Windows 64-bit | Standalone `.exe` files | Clang/LLVM | **Use this for MLIR** |

**For this tutorial, always use CLANG64!** It uses the Clang compiler toolchain, which provides better compatibility with LLVM/MLIR.

### How to Tell Which Environment You're In

**In MSYS2 terminal:**
```bash
echo $MSYSTEM
# Should show: CLANG64 (not MSYS or MINGW64)
```

**Check which tools you're using:**
```bash
which mlir-opt
# CORRECT: /clang64/bin/mlir-opt
# WRONG:   /usr/bin/mlir-opt or /clang64/bin/mlir-opt
```

**In PowerShell:**
```powershell
where.exe mlir-opt
# CORRECT: C:\msys64\clang64\bin\mlir-opt.exe
# WRONG:   C:\msys64\usr\bin\mlir-opt.exe
```

### Why This Matters

Using the **wrong environment** results in:
- ❌ Executables that require MSYS2 DLLs to run
- ❌ Incorrect calling conventions in generated code
- ❌ Inability to link with native Windows libraries
- ❌ Problems with Windows debugging tools
- ❌ Path translation issues

Using **CLANG64 (correct)** gives you:
- ✅ True native Windows executables
- ✅ Proper Windows calling conventions
- ✅ Compatible with Windows debugging tools
- ✅ Can link with any Windows library
- ✅ Executables run on any Windows system
- ✅ Better LLVM/MLIR integration (same compiler toolchain)

## Detailed Installation Steps

### Step 1: Install MSYS2

#### Option A: Automated Installation (Recommended)

```powershell
# Using winget (Windows 11 or Windows 10 with App Installer)
winget install --id MSYS2.MSYS2

# OR using Chocolatey
choco install msys2
```

#### Option B: Manual Installation

1. Download installer from [msys2.org](https://www.msys2.org/)
2. Run the installer (`msys2-x86_64-YYYYMMDD.exe`)
3. Install to default location: `C:\msys64`
4. Complete the installation wizard

#### Option C: Automated Setup Script

```powershell
# Run as Administrator
.\scripts\setup-msys2.ps1
```

This script automates the entire setup process.

### Step 2: Update MSYS2

**CRITICAL:** You must update MSYS2 before installing packages!

1. Open **"MSYS2 MSYS"** from Start Menu
2. Run:
```bash
pacman -Syu --noconfirm
```
3. Close terminal when prompted
4. Reopen **"MSYS2 MSYS"**
5. Run:
```bash
pacman -Su --noconfirm
```

### Step 3: Install LLVM/MLIR Toolchain

1. Open **"MSYS2 CLANG64"** from Start Menu (purple icon)
2. Verify you're in CLANG64:
```bash
echo $MSYSTEM  # Should show: CLANG64
```
3. Install packages:
```bash
pacman -S mingw-w64-clang-x86_64-llvm \
          mingw-w64-clang-x86_64-clang \
          mingw-w64-clang-x86_64-mlir \
          mingw-w64-clang-x86_64-cmake \
          mingw-w64-clang-x86_64-ninja \
          mingw-w64-clang-x86_64-gcc \
          mingw-w64-clang-x86_64-pkgconf
```

4. Verify installation:
```bash
which mlir-opt     # Should show: /clang64/bin/mlir-opt
which cmake        # Should show: /clang64/bin/cmake
mlir-opt --version
```

### Step 4: Configure Windows PATH

This allows you to use MLIR tools from PowerShell and your IDE.

#### For C: Drive Installation (Standard)

Run in **PowerShell as Administrator**:

```powershell
[System.Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;C:\msys64\clang64\bin;C:\msys64\usr\bin",
    [System.EnvironmentVariableTarget]::Machine
)
```

#### For D: Drive or Custom Location

```powershell
# Adjust path to your MSYS2 installation
$msysPath = "D:\msys64"  # Change as needed

[System.Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;$msysPath\mingw64\bin;$msysPath\usr\bin",
    [System.EnvironmentVariableTarget]::Machine
)
```

#### Verify PATH Configuration

**Restart PowerShell**, then:

```powershell
mlir-opt --version
cmake --version

# Verify you're getting the MINGW64 version
where.exe mlir-opt
# Should show: C:\msys64\clang64\bin\mlir-opt.exe
```

## IDE Configuration

### Visual Studio Code

#### Install Recommended Extensions

Open Command Palette (Ctrl+Shift+P) and run:
```
Extensions: Show Recommended Extensions
```

Or install manually:
- **MLIR** (llvm-vs-code-extensions.vscode-mlir)
- **C/C++** (ms-vscode.cpptools)
- **CMake Tools** (ms-vscode.cmake-tools)

#### Configuration Files

This repository includes pre-configured VSCode settings in `.vscode/`:

- **settings.json** - MSYS2 paths, MLIR tools, terminal profiles
- **tasks.json** - Build tasks (F1 → "Run Task")
- **launch.json** - Debug configurations (F5)
- **extensions.json** - Recommended extensions

#### Using VSCode Terminals

VSCode provides three terminal profiles:

1. **PowerShell** (default) - For running build scripts and Windows commands
2. **MSYS2 CLANG64** - For native Windows development (use this for MLIR)
3. **MSYS2 MSYS** - For Unix compatibility (rarely needed)

Switch terminals: Click the dropdown next to "+" in terminal panel.

#### Building from VSCode

- **Ctrl+Shift+B** - Run default build task
- **F1 → "Run Task"** - Choose specific task:
  - Build (Windows)
  - Build (Release)
  - Clean Build
  - Run tutorial-opt
  - Run MLIR Pass (Canonicalize)

#### Debugging from VSCode

- **F5** - Start debugging current file with tutorial-opt
- Choose debug configuration:
  - **Debug tutorial-opt (Current File)** - Debug with current .mlir file
  - **Debug with GDB (MinGW)** - Use GDB debugger

### JetBrains CLion

#### Toolchain Setup

1. **File → Settings → Build, Execution, Deployment → Toolchains**
2. Click "+" to add new toolchain
3. Name: "MinGW-w64 MSYS2"
4. Configure paths:

| Setting | Path |
|---------|------|
| Environment | `C:\msys64\clang64` |
| CMake | `C:\msys64\clang64\bin\cmake.exe` |
| Make | `C:\msys64\clang64\bin\ninja.exe` |
| C Compiler | `C:\msys64\clang64\bin\gcc.exe` |
| C++ Compiler | `C:\msys64\clang64\bin\g++.exe` |
| Debugger | `C:\msys64\clang64\bin\gdb.exe` |

5. Move "MinGW-w64 MSYS2" to top of toolchain list
6. Apply changes

#### CMake Configuration

CLion should auto-detect `CMakeLists.txt`. If not:

1. **File → Settings → Build, Execution, Deployment → CMake**
2. Add configuration:
   - Name: Debug
   - Build type: Debug
   - Toolchain: MinGW-w64 MSYS2
   - CMake options:
     ```
     -DMLIR_DIR=C:/msys64/clang64/lib/cmake/mlir
     -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm
     ```

#### Building and Running

- **Ctrl+F9** - Build project
- **Shift+F10** - Run tutorial-opt
- **Shift+F9** - Debug tutorial-opt

### JetBrains Rider

For F# development with Fidelity Framework:

1. Install Rider
2. Install F# plugin
3. Configure external tools:
   - **Tools → External Tools → Add**
   - Name: MLIR Opt
   - Program: `C:\msys64\clang64\bin\mlir-opt.exe`
   - Arguments: `$FilePath$`
   - Working directory: `$ProjectFileDir$`

## Building the Tutorial

### Automated Build (Recommended)

```powershell
# Debug build (default)
.\scripts\build-windows.ps1

# Release build
.\scripts\build-windows.ps1 -BuildType Release

# Clean build
.\scripts\build-windows.ps1 -Clean

# Disable or-tools (if download fails)
.\scripts\build-windows.ps1 -DisableOrTools
```

### Manual Build

```powershell
# Create build directory
mkdir build
cd build

# Configure with CMake
cmake -G Ninja `
      -DCMAKE_BUILD_TYPE=Debug `
      -DMLIR_DIR="C:\msys64\clang64\lib\cmake\mlir" `
      -DLLVM_DIR="C:\msys64\clang64\lib\cmake\llvm" `
      ..

# Build
ninja

# Run tests
ninja check-mlir-tutorial
```

### Build Options

| Option | Description | Default |
|--------|-------------|---------|
| `-BuildType` | Debug or Release | Debug |
| `-Clean` | Remove build directory first | Off |
| `-DisableOrTools` | Skip or-tools dependency | Off |
| `-BuildDir` | Build directory path | `build` |
| `-Jobs` | Parallel build jobs | CPU count |

## Running the Tutorial

### Basic Usage

```powershell
# Show help
.\build\bin\tutorial-opt.exe --help

# Show available dialects
.\build\bin\tutorial-opt.exe --show-dialects

# Run on a file
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir

# Apply canonicalization pass
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize

# Output to file
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize -o output.mlir
```

### Running Tests

```powershell
# Run all tests
cd build
ninja check-mlir-tutorial

# Or use the build script
.\scripts\build-windows.ps1  # Tests run automatically
```

### Common MLIR Passes

```powershell
$opt = ".\build\bin\tutorial-opt.exe"

# Canonicalization
& $opt test.mlir --canonicalize

# Common Subexpression Elimination (CSE)
& $opt test.mlir --cse

# Affine loop unrolling
& $opt test.mlir --affine-full-unroll

# Convert to LLVM dialect
& $opt test.mlir --convert-poly-to-standard

# Multiple passes
& $opt test.mlir --canonicalize --cse --inline
```

## Troubleshooting

### "mlir-opt not found" or "cmake not found"

**Cause:** Tools not in PATH or installed in wrong environment.

**Solution:**
```powershell
# Check PATH
where.exe mlir-opt

# Should show: C:\msys64\clang64\bin\mlir-opt.exe
# If not found, verify PATH was updated

# Restart PowerShell to apply PATH changes
exit
# Open new PowerShell window

# If still not found, manually add to PATH
$env:Path += ";C:\msys64\clang64\bin"
```

### CMake Can't Find MLIR

**Cause:** MLIR cmake config files not installed or wrong path.

**Solution:**
```powershell
# Check if MLIR cmake files exist
ls C:\msys64\clang64\lib\cmake\mlir
ls C:\msys64\clang64\lib\cmake\llvm

# If missing, reinstall MLIR package
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-mlir --force
```

### Wrong MSYS2 Environment

**Symptom:** Tools installed but `which mlir-opt` shows `/usr/bin/mlir-opt` instead of `/clang64/bin/mlir-opt`.

**Solution:**
```bash
# Check current environment
echo $MSYSTEM
# If shows "MSYS", you're in wrong environment

# Switch to MINGW64
export MSYSTEM=CLANG64
source /etc/profile

# Or close terminal and open "MSYS2 CLANG64" instead
```

### Build Fails with or-tools Error

**Cause:** Network issues downloading or-tools dependency.

**Solution:**
```powershell
# Option 1: Disable or-tools
.\scripts\build-windows.ps1 -DisableOrTools

# Option 2: Edit CMakeLists.txt
# Comment out lines 61-70 (the or-tools FetchContent block)
```

### Path Length Issues

**Symptom:** Build fails with "path too long" errors.

**Solution:**
```powershell
# Enable long paths (Windows 10 1607+)
# Run as Administrator
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1

# Restart required
```

### Antivirus Interference

**Symptom:** Build is extremely slow or executables are quarantined.

**Solution:**
```powershell
# Add exclusions (Run as Administrator)
Add-MpPreference -ExclusionPath "C:\msys64"
Add-MpPreference -ExclusionPath "$env:USERPROFILE\source\mlir-tutorial"
Add-MpPreference -ExclusionProcess "mlir-opt.exe"
Add-MpPreference -ExclusionProcess "ninja.exe"
```

### Debugging GDB Issues

**Symptom:** GDB doesn't start or crashes.

**Solution:**
```powershell
# Verify GDB is installed
C:\msys64\clang64\bin\gdb.exe --version

# If missing, install in MINGW64 terminal:
pacman -S mingw-w64-clang-x86_64-gdb

# Use Visual Studio debugger instead (cppvsdbg in launch.json)
```

## Advanced Topics

### External Drive Installation

If you installed MSYS2 on an external drive (e.g., D:), update all paths accordingly:

**Update VSCode settings.json:**
```json
{
    "mlir.server_path": "D:\\msys64\\clang64\\bin\\mlir-lsp-server.exe",
    "cmake.cmakePath": "D:\\msys64\\clang64\\bin\\cmake.exe"
}
```

**Update build script:**
```powershell
# Edit scripts\build-windows.ps1
# Change the Find-MSYS2 function to check your drive
```

### Building LLVM from Source

This branch uses pre-built LLVM/MLIR, but if you need to build from source:

⚠️ **Warning:** Building LLVM takes 2-4 hours and requires 40GB+ disk space.

See: [LLVM Getting Started](https://llvm.org/docs/GettingStarted.html)

### Using Multiple LLVM Versions

```powershell
# Install specific version
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-llvm18  # or llvm17, llvm19, etc.

# Use specific version
cmake -DLLVM_DIR=C:/msys64/clang64/lib/cmake/llvm18 ...
```

### Cross-Compilation

MinGW64 supports cross-compilation to other architectures:

```powershell
# Install cross-compiler
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-aarch64-w64-mingw32-gcc

# Configure CMake for ARM64
cmake -DCMAKE_C_COMPILER=aarch64-w64-mingw32-gcc ...
```

### Performance Tuning

**Parallel builds:**
```powershell
.\scripts\build-windows.ps1 -Jobs 16  # Use 16 parallel jobs
```

**Faster linker:**
```bash
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-lld

# Use lld in CMake
cmake -DCMAKE_LINKER=ld.lld ...
```

**CCache for faster rebuilds:**
```bash
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-ccache

# Enable in CMake
cmake -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ...
```

### Integration with Fidelity Framework

This setup is designed to work with the Fidelity/Firefly F# compiler framework:

```powershell
# F# to MLIR pipeline
dotnet run --project Firefly -- emit-mlir program.fs -o program.mlir

# Optimize MLIR
.\build\bin\tutorial-opt.exe program.mlir --canonicalize -o program.opt.mlir

# Lower to LLVM IR
mlir-translate --mlir-to-llvmir program.opt.mlir -o program.ll

# Compile to object file
llc -filetype=obj program.ll -o program.obj

# Link executable
ld.lld program.obj -o program.exe -lmsvcrt
```

## Additional Resources

- **MLIR Documentation:** [mlir.llvm.org](https://mlir.llvm.org/)
- **MSYS2 Website:** [msys2.org](https://www.msys2.org/)
- **MSYS2 Package Search:** [packages.msys2.org](https://packages.msys2.org/)
- **Original Tutorial:** [github.com/j2kun/mlir-tutorial](https://github.com/j2kun/mlir-tutorial)
- **Jeremy Kun's Articles:** [jeremykun.com](https://jeremykun.com)

## Getting Help

- **Tutorial Issues:** [Original Repository Issues](https://github.com/j2kun/mlir-tutorial/issues)
- **Windows Setup Issues:** Open issue on this fork
- **MLIR Questions:** [LLVM Discord](https://discord.gg/xS7Z362) #mlir channel
- **MSYS2 Questions:** [MSYS2 Discussion](https://github.com/msys2/msys2/discussions)
