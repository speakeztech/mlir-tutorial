# Windows Build Guide for MLIR Tutorial

This guide shows you how to build the MLIR tutorial on Windows using MSYS2 with prebuilt MLIR libraries.

**Build time:** Under 30 minutes from fresh install to working executable
**No LLVM compilation required** - uses prebuilt binaries from MSYS2

## Table of Contents
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Building the Project](#building-the-project)
- [Troubleshooting](#troubleshooting)

## Quick Start

```powershell
# 1. Install MSYS2
winget install --id MSYS2.MSYS2

# 2. Open MSYS2 MSYS terminal and install packages
pacman -Syu
pacman -S --needed \
  mingw-w64-clang-x86_64-toolchain \
  mingw-w64-clang-x86_64-cmake \
  mingw-w64-clang-x86_64-ninja \
  mingw-w64-clang-x86_64-mlir \
  mingw-w64-clang-x86_64-llvm

# 3. Clone and build (in MSYS2 CLANG64 terminal)
git clone https://github.com/j2kun/mlir-tutorial.git
cd mlir-tutorial
./scripts/build-windows.ps1

# 4. Test
./cmake-build/tools/tutorial-opt.exe --help
```

## Detailed Setup

### Step 1: Install MSYS2

**Option A: Using winget (recommended)**
```powershell
winget install --id MSYS2.MSYS2
```

**Option B: Manual download**
Download the installer from https://www.msys2.org/ and run it.

**Default installation path:** `C:\msys64` or `D:\msys64`

### Step 2: Install CLANG64 Toolchain

#### Why CLANG64?

MSYS2 provides MLIR in two environments:
- **MINGW64**: Uses GCC + GNU linker (has library linking issues with MLIR)
- **CLANG64**: Uses Clang + LLD linker (works reliably with MLIR)

We use CLANG64 because the LLVM LLD linker doesn't have the library ordering issues that affect GNU ld when linking MLIR applications.

#### Installation

1. Open **MSYS2 MSYS** terminal (find it in Start menu)

2. Update package database:
   ```bash
   pacman -Syu
   ```

   If prompted to close the terminal, close it and reopen before continuing.

3. Install CLANG64 packages:
   ```bash
   pacman -S --needed \
     mingw-w64-clang-x86_64-toolchain \
     mingw-w64-clang-x86_64-cmake \
     mingw-w64-clang-x86_64-ninja \
     mingw-w64-clang-x86_64-mlir \
     mingw-w64-clang-x86_64-llvm
   ```

4. Verify installation (in **MSYS2 CLANG64** terminal):
   ```bash
   clang --version      # Should show clang version 19+
   cmake --version       # Should show cmake version 3.20+
   ninja --version       # Should show ninja version 1.10+
   which mlir-opt        # Should show /clang64/bin/mlir-opt
   ```

### Step 3: Clone the Repository

In **MSYS2 CLANG64** terminal:

```bash
cd ~
git clone https://github.com/j2kun/mlir-tutorial.git
cd mlir-tutorial
```

## Building the Project

### Using the Build Script (Recommended)

From PowerShell in the repository root:

```powershell
# Debug build (default)
.\scripts\build-windows.ps1

# Clean build
.\scripts\build-windows.ps1 -Clean

# Release build with optimizations
.\scripts\build-windows.ps1 -BuildType Release -Clean

# Custom parallel jobs (default: CPU count)
.\scripts\build-windows.ps1 -Jobs 8
```

The build script will:
1. Detect MSYS2 CLANG64 installation
2. Verify required tools are installed
3. Configure CMake with correct compilers and paths
4. Build the project (typically 2-5 minutes)
5. Test the resulting executable

### Manual Build

If you prefer manual control (in **MSYS2 CLANG64** terminal):

```bash
cd ~/mlir-tutorial
mkdir cmake-build && cd cmake-build

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_C_COMPILER=/clang64/bin/clang.exe \
  -DCMAKE_CXX_COMPILER=/clang64/bin/clang++.exe \
  -DMLIR_DIR=/clang64/lib/cmake/mlir \
  -DLLVM_DIR=/clang64/lib/cmake/llvm \
  ..

ninja

# Test
./tools/tutorial-opt.exe --help
```

### Build Output

After a successful build:
- **Executable:** `cmake-build/tools/tutorial-opt.exe` (approximately 100MB)
- **Libraries:** `cmake-build/lib/*/lib*.a`
- **Build time:** 2-5 minutes on modern hardware

## Running the Tutorial

### Test the Executable

```powershell
# Show help
.\cmake-build\tools\tutorial-opt.exe --help

# Run on example file
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize

# Run with passes
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_syntax.mlir --poly-to-standard
```

### Run Examples from Tutorials

Each tutorial includes example `.mlir` files in the `tests/` directory:

```powershell
# Tutorial 2: Lowering
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_syntax.mlir --poly-to-standard

# Tutorial 3: First pass
.\cmake-build\tools\tutorial-opt.exe .\tests\simple_mul.mlir --mul-to-add

# Tutorial 7: Constant folding
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_fold.mlir --canonicalize

# Tutorial 9: Pattern rewriting
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_patterns.mlir --canonicalize
```

## Troubleshooting

### MSYS2 Not Found

**Error:** `MSYS2 not found at C:\msys64 or D:\msys64`

**Solution:**
1. Install MSYS2: `winget install --id MSYS2.MSYS2`
2. Or verify your installation path and set `$env:MSYS2_ROOT` in PowerShell

### CLANG64 Packages Not Found

**Error:** `Required tool 'clang' not found`

**Solution:** Install CLANG64 packages in **MSYS2 MSYS** terminal:
```bash
pacman -S --needed \
  mingw-w64-clang-x86_64-toolchain \
  mingw-w64-clang-x86_64-cmake \
  mingw-w64-clang-x86_64-ninja \
  mingw-w64-clang-x86_64-mlir
```

### Wrong Terminal Environment

**Symptom:** `clang: command not found` or paths show `/mingw64/` instead of `/clang64/`

**Solution:** Make sure you're using the **MSYS2 CLANG64** terminal (not MINGW64, not MSYS).
- Look for "MSYS2 CLANG64" in your Start menu
- The prompt should show `CLANG64` in purple/magenta

### CMake Configuration Fails

**Error:** `Could not find MLIR`

**Solution:** Verify MLIR is installed:
```bash
# In MSYS2 CLANG64 terminal
ls /clang64/lib/cmake/mlir  # Should show MLIRConfig.cmake
pacman -S mingw-w64-clang-x86_64-mlir  # Reinstall if missing
```

### Build Stops at "Building CXX object..."

**Symptom:** Build appears frozen

**Cause:** Large MLIR files take time to compile (especially in Debug mode)

**Solution:** Wait patiently. Check Task Manager to verify clang++.exe is using CPU. Some files can take 2-3 minutes each.

### Deprecation Warnings

**Warning:** `'applyPatternsAndFoldGreedily' is deprecated`

**Status:** These are harmless warnings about MLIR API changes. The code works correctly. We'll update to the newer API names in a future update.

### Tests Fail: `\llvm-lit.py not found`

**Symptom:** Build succeeds but test suite fails

**Status:** This is a known issue with lit (LLVM's test runner) configuration. The main executable works fine. Tests can be run manually if needed.

## System Requirements

- **OS:** Windows 10 or later (tested on Windows 11)
- **RAM:** 8GB minimum, 16GB recommended
- **Disk Space:** ~5GB for MSYS2 + CLANG64 + build artifacts
- **CPU:** Any modern x64 processor

## Development Tips

### Using Multiple Build Configurations

Create separate build directories for Debug and Release:

```powershell
# Debug build
mkdir cmake-build-debug
cd cmake-build-debug
cmake -G Ninja -DCMAKE_BUILD_TYPE=Debug ..
ninja

# Release build
mkdir cmake-build-release
cd cmake-build-release
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
ninja
```

### IDE Integration

**CLion:**
1. Open the repository as a CMake project
2. File → Settings → Build → Toolchains
3. Add MSYS2 CLANG64 toolchain:
   - C Compiler: `D:\msys64\clang64\bin\clang.exe`
   - C++ Compiler: `D:\msys64\clang64\bin\clang++.exe`
   - Make: `D:\msys64\clang64\bin\ninja.exe`

**Visual Studio Code:**
1. Install CMake Tools extension
2. Configure CMake to use CLANG64 compilers
3. Set CMake: Configure Environment:
   ```json
   {
     "CMAKE_C_COMPILER": "D:/msys64/clang64/bin/clang.exe",
     "CMAKE_CXX_COMPILER": "D:/msys64/clang64/bin/clang++.exe"
   }
   ```

## Next Steps

Once you have a working build:

1. **Start the tutorials:** Begin with [Tutorial 01: Getting Started](tutorials/01-getting-started.md)
2. **Explore the code:** Look at `lib/Dialect/Poly/` for a simple dialect implementation
3. **Modify and rebuild:** Make changes and run `.\scripts\build-windows.ps1` to test
4. **Run examples:** Try the `.mlir` files in the `tests/` directory

## Getting Help

- **Build issues:** Review this guide's troubleshooting section
- **MLIR questions:** [MLIR Discourse Forum](https://discourse.llvm.org/c/mlir/31)
- **Project issues:** [GitHub Issues](https://github.com/j2kun/mlir-tutorial/issues)

---

**Happy hacking with MLIR on Windows!** 🎉
