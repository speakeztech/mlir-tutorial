# MLIR Tutorial - Windows Quick Start

Get up and running with MLIR on Windows in under 30 minutes.

## Prerequisites

- Windows 10/11 (64-bit)
- Administrator access (for initial setup)
- 10 GB free disk space

## Installation (One-Time Setup)

### Option A: Automated Setup (Easiest)

```powershell
# 1. Run setup script as Administrator
.\scripts\setup-msys2.ps1

# 2. Restart PowerShell

# 3. Verify installation
mlir-opt --version
```

### Option B: Manual Setup

```powershell
# 1. Install MSYS2
winget install --id MSYS2.MSYS2

# 2. Update MSYS2 (in "MSYS2 MSYS" terminal)
pacman -Syu --noconfirm
# Close and reopen terminal
pacman -Su --noconfirm

# 3. Install tools (in "MSYS2 MINGW64" terminal - blue icon)
pacman -S mingw-w64-x86_64-llvm \
          mingw-w64-x86_64-clang \
          mingw-w64-x86_64-mlir \
          mingw-w64-x86_64-cmake \
          mingw-w64-x86_64-ninja \
          mingw-w64-x86_64-gcc

# 4. Add to Windows PATH (in PowerShell as Admin)
[System.Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;C:\msys64\mingw64\bin",
    [System.EnvironmentVariableTarget]::Machine
)

# 5. Restart PowerShell
```

## Building the Tutorial

```powershell
# Quick build
.\scripts\build-windows.ps1

# Or manually
mkdir build
cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug ..
ninja
```

## Running Examples

```powershell
# Show help
.\build\bin\tutorial-opt.exe --help

# Run canonicalization pass
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize

# Run all tests
cd build
ninja check-mlir-tutorial
```

## Common Commands

| Task | Command |
|------|---------|
| Build (Debug) | `.\scripts\build-windows.ps1` |
| Build (Release) | `.\scripts\build-windows.ps1 -BuildType Release` |
| Clean build | `.\scripts\build-windows.ps1 -Clean` |
| Run tutorial-opt | `.\build\bin\tutorial-opt.exe <file.mlir>` |
| Show dialects | `.\build\bin\tutorial-opt.exe --show-dialects` |
| Run tests | `cd build; ninja check-mlir-tutorial` |

## IDE Setup

### VSCode

1. Install extensions:
   - MLIR (llvm-vs-code-extensions.vscode-mlir)
   - C/C++ (ms-vscode.cpptools)
   - CMake Tools (ms-vscode.cmake-tools)

2. Open folder in VSCode
3. Settings are already configured in `.vscode/`
4. Build: `Ctrl+Shift+B`
5. Debug: `F5`

### CLion

1. File → Settings → Toolchains
2. Add "MinGW-w64 MSYS2" toolchain:
   - Environment: `C:\msys64\mingw64`
   - CMake: `C:\msys64\mingw64\bin\cmake.exe`
   - Make: `C:\msys64\mingw64\bin\ninja.exe`
   - C/C++ Compiler: `C:\msys64\mingw64\bin\gcc.exe` / `g++.exe`

3. Build: `Ctrl+F9`

## Troubleshooting

### "command not found" errors

```powershell
# Verify PATH includes MSYS2
where.exe mlir-opt
# Should show: C:\msys64\mingw64\bin\mlir-opt.exe

# If not found, restart PowerShell or add to PATH:
$env:Path += ";C:\msys64\mingw64\bin"
```

### CMake can't find MLIR

```powershell
# Check MLIR cmake files exist
ls C:\msys64\mingw64\lib\cmake\mlir

# If missing, reinstall (in MINGW64 terminal):
pacman -S mingw-w64-x86_64-mlir --force
```

### Build errors with or-tools

```powershell
# Disable or-tools dependency
.\scripts\build-windows.ps1 -DisableOrTools
```

## Next Steps

1. **Follow the tutorials**: See [README.md](README.md) for article links
2. **Read detailed setup**: See [WINDOWS_SETUP.md](WINDOWS_SETUP.md)
3. **Try examples**: Explore `.mlir` files in `tests/` directory

## Key Concepts

### MSYS2 Environments

- **MSYS** (`/usr/bin`) - Unix compatibility ❌ Don't use for MLIR
- **MINGW64** (`/mingw64/bin`) - Native Windows ✅ Use this

### Verify you're using MINGW64:

```bash
# In MSYS2 terminal
echo $MSYSTEM  # Should be "MINGW64"
which mlir-opt # Should be "/mingw64/bin/mlir-opt"
```

```powershell
# In PowerShell
where.exe mlir-opt # Should be "C:\msys64\mingw64\bin\mlir-opt.exe"
```

## Getting Help

- **Detailed setup**: [WINDOWS_SETUP.md](WINDOWS_SETUP.md)
- **Tutorial articles**: [README.md](README.md)
- **MLIR docs**: [mlir.llvm.org](https://mlir.llvm.org/)
- **MSYS2 docs**: [msys2.org](https://www.msys2.org/)
