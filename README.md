# MLIR For Beginners - Windows Native Edition

This is a Windows-native fork of the [MLIR tutorial series](https://jeremykun.com/2023/08/10/mlir-getting-started/) focused on providing a low-burden path to learning MLIR on Windows using **MSYS2/MinGW64** and **CMake**.

**Branch:** `WinOS-CMake` - Optimized for native Windows development without WSL.

## Why This Fork?

The original tutorial uses Bazel and assumes building LLVM from source. This fork provides:
- **Pre-built LLVM/MLIR** via MSYS2 package manager (no multi-hour compilation)
- **Native Windows tooling** with MSYS2/MinGW64 (not WSL or Cygwin)
- **CMake build system** (simpler than Bazel for learning)
- **PowerShell integration** for Windows-first workflow
- **Fast setup** - from zero to running tutorials in under 30 minutes

## Tutorial Series

This repository includes **complete Windows-adapted tutorials** that teach MLIR concepts using native Windows tools (MSYS2/CMake) instead of Bazel. All 13 tutorials are now available!

### Complete Tutorial Series (All Available Now!)

#### Beginner (Tutorials 1-4) - Getting Started with MLIR

1.  **[Getting Started](docs/tutorials/01-getting-started.md)** - MSYS2 setup, building with CMake, first MLIR program
2.  **[Running and Testing a Lowering](docs/tutorials/02-running-and-testing.md)** - lit/FileCheck testing, dialects, progressive lowering
3.  **[Writing Your First Pass](docs/tutorials/03-writing-first-pass.md)** - Pattern rewriting, IR walking, debugging passes
4.  **[Using Tablegen for Passes](docs/tutorials/04-using-tablegen.md)** - TableGen basics, `.td` files, CMake integration

#### Intermediate (Tutorials 5-9) - Building Custom Dialects

5.  **[Defining a New Dialect](docs/tutorials/05-defining-dialect.md)** - Dialect architecture, types, operations, TableGen definitions
6.  **[Using Traits](docs/tutorials/06-using-traits.md)** - Operation traits, optimization enablement, memory effects
7.  **[Folders and Constant Propagation](docs/tutorials/07-folders-constant-propagation.md)** - Constant folding, materializers, SCCP pass
8.  **[Verifiers](docs/tutorials/08-verifiers.md)** - Verification architecture, custom verifiers, error messages
9.  **[Canonicalizers and Declarative Rewrite Patterns](docs/tutorials/09-canonicalizers.md)** - DRR patterns, constraints, pattern benefits

#### Advanced (Tutorials 10-13) - Production Compiler Features

10. **[Dialect Conversion](docs/tutorials/10-dialect-conversion.md)** - Systematic conversion, type converters, materialization
11. **[Lowering through LLVM](docs/tutorials/11-lowering-through-llvm.md)** - Complete lowering pipeline, JIT compilation, code generation
12. **[Dataflow Analysis](docs/tutorials/12-dataflow-analysis.md)** - Analysis framework, lattices, custom analyses
13. **[Defining Patterns with PDLL](docs/tutorials/13-pdll-patterns.md)** - Pattern Description Language, advanced pattern features

**[→ Start Learning: Tutorial 01: Getting Started](docs/tutorials/01-getting-started.md)**

### About These Tutorials

All tutorials are based on Jeremy Kun's excellent series at [jeremykun.com](https://jeremykun.com/2023/08/10/mlir-getting-started/). Our Windows adaptations:
- ✅ Replace Bazel with CMake
- ✅ Use MSYS2/MinGW64 for native Windows development
- ✅ Include PowerShell commands and Windows-specific examples
- ✅ Preserve 100% of MLIR concepts and learning material
- ✅ Add Windows troubleshooting and debugging tips

**Time to Complete:** ~20-30 hours for all tutorials (2-3 hours each)

## Quick Start (Windows Native with MSYS2)

### Prerequisites

1. **Windows 10/11** (64-bit)
2. **PowerShell 5.1+** (included with Windows)
3. **Git for Windows** ([download](https://git-scm.com/download/win))
4. **MSYS2** - we'll install this next

### Step 1: Install MSYS2

MSYS2 provides pre-built LLVM/MLIR binaries, eliminating the need to compile LLVM from source (which can take hours).

```powershell
# Option A: Using winget (Windows 11 or Windows 10 with App Installer)
winget install --id MSYS2.MSYS2

# Option B: Using Chocolatey
choco install msys2

# Option C: Direct download
# Download installer from https://www.msys2.org/ and run it
```

After installation, **update MSYS2** (required before installing packages):

```bash
# Run this in the "MSYS2 MSYS" terminal (from Start Menu)
pacman -Syu --noconfirm
# Close terminal when prompted and reopen MSYS2 MSYS
pacman -Su --noconfirm
```

### Step 2: Install LLVM/MLIR Toolchain

**CRITICAL:** You must use the **MINGW64** environment, not the MSYS environment!

Open **"MSYS2 MINGW64"** from the Start Menu (look for the blue icon), then run:

```bash
# Install complete MLIR/LLVM toolchain with build tools
pacman -S mingw-w64-x86_64-llvm \
          mingw-w64-x86_64-clang \
          mingw-w64-x86_64-mlir \
          mingw-w64-x86_64-cmake \
          mingw-w64-x86_64-ninja \
          mingw-w64-x86_64-gcc \
          mingw-w64-x86_64-pkgconf

# Verify installation (should show /mingw64/bin/...)
which mlir-opt
which cmake
which ninja
```

### Step 3: Add MSYS2 to Windows PATH

This allows you to use MLIR tools from PowerShell and your IDE.

**For C: drive installation** (run in PowerShell as Administrator):

```powershell
[System.Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;C:\msys64\mingw64\bin;C:\msys64\usr\bin",
    [System.EnvironmentVariableTarget]::Machine
)
```

**For D: drive or external installation** (adjust path as needed):

```powershell
$msysPath = "D:\msys64"  # Change to your installation location
[System.Environment]::SetEnvironmentVariable(
    "Path",
    "$env:Path;$msysPath\mingw64\bin;$msysPath\usr\bin",
    [System.EnvironmentVariableTarget]::Machine
)
```

**Restart PowerShell** after updating PATH, then verify:

```powershell
mlir-opt --version
cmake --version
```

### Step 4: Clone and Build This Tutorial

```powershell
# Clone the repository (WinOS-CMake branch)
git clone --branch WinOS-CMake https://github.com/YOUR-FORK/mlir-tutorial.git
cd mlir-tutorial

# Run the automated build script
.\scripts\build-windows.ps1
```

That's it! You're ready to start learning MLIR.

### Manual Build (Alternative)

If you prefer to build manually:

```powershell
# Create build directory
mkdir build
cd build

# Configure with CMake
cmake -G Ninja `
      -DCMAKE_BUILD_TYPE=Debug `
      -DMLIR_DIR="C:\msys64\mingw64\lib\cmake\mlir" `
      -DLLVM_DIR="C:\msys64\mingw64\lib\cmake\llvm" `
      ..

# Build
ninja

# Run tests
ninja check-mlir-tutorial
```

### Running the Tutorial

```powershell
# Test the tutorial-opt tool
.\build\bin\tutorial-opt.exe --help

# Run example transformations
.\build\bin\tutorial-opt.exe ..\tests\poly_syntax.mlir --canonicalize
```

## Understanding MSYS2 vs MINGW64

**Important:** MSYS2 provides two different environments:

- **MSYS2** environment (`/usr/bin`): Unix compatibility layer - produces binaries that depend on `msys-2.0.dll`
- **MINGW64** environment (`/mingw64/bin`): Native Windows toolchain - produces standalone `.exe` files

**Always use MINGW64 for this tutorial** to generate true native Windows executables.

Check which environment you're in:
```bash
echo $MSYSTEM  # Should show "MINGW64"
```

## Troubleshooting

### "mlir-opt not found" or "cmake not found"

Make sure you:
1. Installed packages in **MINGW64** environment (not MSYS)
2. Added `C:\msys64\mingw64\bin` to your Windows PATH
3. Restarted PowerShell after updating PATH

Verify with:
```powershell
where.exe mlir-opt
# Should show: C:\msys64\mingw64\bin\mlir-opt.exe
```

### CMake can't find MLIR

If CMake reports "Could not find MLIR", ensure you're pointing to the correct cmake config:

```powershell
# Check if MLIR cmake files exist
ls C:\msys64\mingw64\lib\cmake\mlir
ls C:\msys64\mingw64\lib\cmake\llvm
```

If files are missing, reinstall the MLIR package:
```bash
# In MINGW64 terminal
pacman -S mingw-w64-x86_64-mlir --force
```

### Build Errors with or-tools

If you get errors downloading or-tools, you can disable it temporarily (it's only needed for one tutorial):

Edit `CMakeLists.txt` and comment out the or-tools section:
```cmake
# message(STATUS "Fetching or-tools...")
# include(FetchContent)
# ...
```

### Path Length Issues

Windows has a 260 character path limit by default. Enable long paths:

```powershell
# Run as Administrator
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1
```

## IDE Setup

### VSCode

Install recommended extensions:
- **MLIR** by LLVM Foundation
- **C/C++** by Microsoft
- **CMake Tools** by Microsoft

Settings will be auto-configured from `.vscode/settings.json` in this repository.

### CLion / Rider

CLion will auto-detect the CMake configuration. To use MSYS2 toolchain:

1. **Settings → Build, Execution, Deployment → Toolchains**
2. Add toolchain: "MinGW-w64 MSYS2"
3. Set paths:
   - Environment: `C:\msys64\mingw64`
   - CMake: `C:\msys64\mingw64\bin\cmake.exe`
   - Make: `C:\msys64\mingw64\bin\ninja.exe`
   - C Compiler: `C:\msys64\mingw64\bin\gcc.exe`
   - C++ Compiler: `C:\msys64\mingw64\bin\g++.exe`

## Additional Resources

- **MLIR Documentation**: [mlir.llvm.org](https://mlir.llvm.org/)
- **Original Tutorial Repo**: [github.com/j2kun/mlir-tutorial](https://github.com/j2kun/mlir-tutorial)
- **MSYS2 Documentation**: [www.msys2.org](https://www.msys2.org/)
- **Windows Development Guide**: See `WINDOWS_SETUP.md` for advanced configuration

## Contributing

This is a personal fork focused on Windows-native development. For issues with the tutorial content itself, please refer to [the original repository](https://github.com/j2kun/mlir-tutorial).

For Windows-specific issues with this fork, please open an issue.

## License

Same as the original mlir-tutorial repository - Apache 2.0 with LLVM Exceptions.

---

## Legacy Build Systems (Not Used in This Branch)

<details>
<summary>Bazel Build (Original Tutorial) - Click to expand</summary>

The original tutorial uses Bazel. This branch (`WinOS-CMake`) uses CMake instead for simplicity on Windows. If you want to use Bazel, switch to the `main` branch.

For Bazel documentation, see the [original README](https://github.com/j2kun/mlir-tutorial/blob/main/README.md).

</details>

<details>
<summary>Building LLVM from Source - Click to expand</summary>

This branch uses pre-built LLVM/MLIR from MSYS2. If you need to build LLVM from source (for development or custom builds), see the upstream LLVM documentation at [llvm.org/docs/GettingStarted.html](https://llvm.org/docs/GettingStarted.html).

**Warning:** Building LLVM from source on Windows takes 2-4 hours and requires 40GB+ disk space.

</details>
