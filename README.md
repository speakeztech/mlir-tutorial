# MLIR From a Warm Start

A comprehensive tutorial series for learning MLIR (Multi-Level Intermediate Representation), with **first-class support for Windows, Linux, and macOS**.

**Based on:** [Jeremy Kun's MLIR tutorial series](https://jeremykun.com/2023/08/10/mlir-getting-started/)

## Why This Fork?

This fork simplifies the original tutorial by:
- **Removing the or-tools dependency** (2100+ build targets eliminated!)
- **Fast Windows setup** using MSYS2 prebuilt MLIR libraries
- **Under 30 minutes from install to working build**
- **Beginner-friendly documentation** with clear setup instructions

## 🚀 Quick Start

### Windows Setup

#### Step 1: Install MSYS2

```powershell
# Using winget (recommended)
winget install --id MSYS2.MSYS2

# Or download from: https://www.msys2.org/
```

#### Step 2: Install CLANG64 Toolchain

Open **MSYS2 MSYS** terminal and run:

```bash
# Update package database
pacman -Syu

# Install CLANG64 toolchain and MLIR (prebuilt)
pacman -S --needed \
  mingw-w64-clang-x86_64-toolchain \
  mingw-w64-clang-x86_64-cmake \
  mingw-w64-clang-x86_64-ninja \
  mingw-w64-clang-x86_64-mlir \
  mingw-w64-clang-x86_64-llvm
```

#### Step 3: Build the Tutorial

Open **MSYS2 CLANG64** terminal (find it in Start menu), then:

```bash
# Clone the repository
git clone https://github.com/j2kun/mlir-tutorial.git
cd mlir-tutorial

# Build (takes 2-5 minutes)
./scripts/build-windows.ps1

# Test it works
./cmake-build/tools/tutorial-opt.exe --help
```

**That's it!** You're ready to start learning MLIR.

**📖 Detailed Windows setup:** See **[Windows Build Guide](docs/WINDOWS_BUILD_GUIDE.md)**

### Linux Setup

```bash
# Install dependencies (Ubuntu/Debian)
sudo apt install build-essential cmake ninja-build llvm-dev mlir-tools libmlir-dev

# Clone and build
git clone https://github.com/speakeztech/mlir-tutorial.git
cd mlir-tutorial
mkdir build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
ninja

# Test it works
./tools/tutorial-opt --help
```

### macOS Setup

```bash
# Install dependencies
brew install llvm cmake ninja

# Clone and build
git clone https://github.com/j2kun/mlir-tutorial.git
cd mlir-tutorial
mkdir build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_DIR=$(brew --prefix llvm)/lib/cmake/llvm \
  -DMLIR_DIR=$(brew --prefix llvm)/lib/cmake/mlir \
  ..
ninja

# Test it works
./tools/tutorial-opt --help
```

## 📚 Tutorial Series

This repository includes **13 complete tutorials** that progressively teach MLIR concepts, from basics to advanced compiler features.

### Beginner (Tutorials 1-4) - Getting Started with MLIR

1.  **[Getting Started](docs/tutorials/01-getting-started.md)** - Setup, building, first MLIR program
2.  **[Running and Testing a Lowering](docs/tutorials/02-running-and-testing.md)** - lit/FileCheck testing, dialects, progressive lowering
3.  **[Writing Your First Pass](docs/tutorials/03-writing-first-pass.md)** - Pattern rewriting, IR walking, debugging passes
4.  **[Using Tablegen for Passes](docs/tutorials/04-using-tablegen.md)** - TableGen basics, `.td` files, build integration

### Intermediate (Tutorials 5-9) - Building Custom Dialects

5.  **[Defining a New Dialect](docs/tutorials/05-defining-dialect.md)** - Dialect architecture, types, operations, TableGen definitions
6.  **[Using Traits](docs/tutorials/06-using-traits.md)** - Operation traits, optimization enablement, memory effects
7.  **[Folders and Constant Propagation](docs/tutorials/07-folders-constant-propagation.md)** - Constant folding, materializers, SCCP pass
8.  **[Verifiers](docs/tutorials/08-verifiers.md)** - Verification architecture, custom verifiers, error messages
9.  **[Canonicalizers and Declarative Rewrite Patterns](docs/tutorials/09-canonicalizers.md)** - DRR patterns, constraints, pattern benefits

### Advanced (Tutorials 10-13) - Production Compiler Features

10. **[Dialect Conversion](docs/tutorials/10-dialect-conversion.md)** - Systematic conversion, type converters, materialization
11. **[Lowering through LLVM](docs/tutorials/11-lowering-through-llvm.md)** - Complete lowering pipeline, JIT compilation, code generation
12. **[Dataflow Analysis](docs/tutorials/12-dataflow-analysis.md)** - Analysis framework, lattices, custom analyses
13. **[Defining Patterns with PDLL](docs/tutorials/13-pdll-patterns.md)** - Pattern Description Language, advanced pattern features

**[→ Start Learning: Tutorial 01: Getting Started](docs/tutorials/01-getting-started.md)**

**Time to Complete:** ~20-30 hours for all tutorials (2-3 hours each)

## 💡 What Changed in This Fork?

### Removed or-tools Dependency

**Original tutorial:** Used or-tools library for integer linear programming in Tutorial 12
- Added 2100+ build targets
- Required complex dependencies (SCIP, HiGHS, glpk, etc.)
- Long compilation times

**This fork:** Replaced with simple greedy algorithm
- Teaches the same MLIR concepts (dataflow analysis, lattices)
- Eliminates dependency complexity
- Much faster builds

### Windows Support with Prebuilt Libraries

- Uses MSYS2 CLANG64 with prebuilt MLIR libraries
- No multi-hour LLVM compilation required
- Fast setup: under 30 minutes from install to working build

## 📖 Documentation

- **[Windows Build Guide](docs/WINDOWS_BUILD_GUIDE.md)** - Complete Windows setup with MSYS2 CLANG64
- **[Tutorial Completion Summary](docs/TUTORIAL_COMPLETION_SUMMARY.md)** - Overview of all completed tutorials

## 🛠️ Common Tasks

### Windows (PowerShell from repo root)

```powershell
# Build
.\scripts\build-windows.ps1

# Clean build
.\scripts\build-windows.ps1 -Clean

# Release build
.\scripts\build-windows.ps1 -BuildType Release

# Run tutorial-opt
.\cmake-build\tools\tutorial-opt.exe --help
.\cmake-build\tools\tutorial-opt.exe .\tests\poly_syntax.mlir --canonicalize
```

### Linux/macOS

```bash
# Build
cd build && ninja

# Clean build
rm -rf build && mkdir build && cd build && cmake -G Ninja .. && ninja

# Run tutorial-opt
./tools/tutorial-opt --help
./tools/tutorial-opt ../tests/poly_syntax.mlir --canonicalize
```

## 🎓 IDE Setup

### Visual Studio Code (All Platforms)

1. Install extensions:
   - **C/C++** by Microsoft
   - **CMake Tools** by Microsoft
   - **MLIR** by LLVM Foundation

2. Open the repository folder in VS Code

3. Configure CMake (Ctrl+Shift+P → "CMake: Configure")

### CLion (All Platforms)

1. Open the repository as a CMake project
2. CLion will automatically detect CMakeLists.txt
3. Select build configuration and build

## 📦 Project Structure

```
mlir-tutorial/
├── docs/
│   ├── tutorials/          # 13 complete MLIR tutorials
│   └── WINDOWS_BUILD_GUIDE.md
├── lib/
│   ├── Dialect/           # Custom dialects (Poly, Noisy)
│   ├── Transform/         # Custom transformation passes
│   ├── Conversion/        # Dialect conversion passes
│   └── Analysis/          # Dataflow analyses
├── tools/
│   └── tutorial-opt.cpp   # Main compiler driver
├── tests/                 # lit/FileCheck tests
├── scripts/
│   └── build-windows.ps1  # Windows build script
└── CMakeLists.txt         # CMake configuration
```

## 🤝 Contributing

This fork focuses on simplifying the learning experience. Contributions welcome for:
- Tutorial improvements
- Documentation clarity
- Build system enhancements
- Cross-platform compatibility

## 📜 License

Apache 2.0 with LLVM Exceptions (same as upstream LLVM/MLIR)

## 🙏 Acknowledgments

- **Jeremy Kun** for the original [MLIR tutorial series](https://jeremykun.com/2023/08/10/mlir-getting-started/)
- **LLVM Foundation** for MLIR and documentation
- All contributors to the [original repository](https://github.com/j2kun/mlir-tutorial)

---

## 🆘 Getting Help

- **Windows build issues:** See [Windows Build Guide](docs/WINDOWS_BUILD_GUIDE.md)
- **MLIR questions:** [MLIR Discourse](https://discourse.llvm.org/c/mlir/31)
- **Project issues:** [GitHub Issues](https://github.com/j2kun/mlir-tutorial/issues)

**Happy hacking with MLIR!** 🎉
