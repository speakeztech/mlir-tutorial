# WinOS-CMake Branch Changelog

This document tracks changes made to transform the mlir-tutorial repository into a Windows-native, MSYS2-based development environment.

## Branch: WinOS-CMake

### Overview

This branch provides a Windows-first approach to the MLIR tutorial, replacing Bazel builds and LLVM-from-source requirements with pre-built MSYS2 packages and CMake builds.

### Key Goals

1. **Fast Setup** - From zero to running in under 30 minutes
2. **Native Windows** - No WSL, no virtualization, true Windows executables
3. **Minimal Barriers** - Use pre-built packages, avoid multi-hour LLVM compilation
4. **IDE Support** - First-class VSCode and JetBrains integration
5. **Beginner Friendly** - Clear documentation, automated scripts

## Recent Updates

### 2025-11-12: Migration to CLANG64 Environment

**Breaking Change: MINGW64 → CLANG64**

The tutorial now uses the MSYS2 CLANG64 environment instead of MINGW64 for better LLVM/MLIR compatibility.

**Why the change?**
- **Better toolchain alignment**: CLANG64 uses Clang/LLVM compiler, matching the MLIR infrastructure
- **Improved linker compatibility**: LLD (LLVM linker) avoids library ordering issues present with GNU ld
- **Consistent compilation**: Same compiler toolchain from source through MLIR to final binary

**What changed:**
- All documentation updated to reference CLANG64 (`/clang64/bin`) instead of MINGW64 (`/mingw64/bin`)
- Package names changed from `mingw-w64-x86_64-*` to `mingw-w64-clang-x86_64-*`
- Scripts updated: `setup-msys2.ps1`, `verify-setup.ps1`, `build-windows.ps1`
- VSCode settings updated to use CLANG64 paths
- All tutorial markdown files updated with CLANG64 paths
- MSYS2 environment table now includes CLANG64 as the recommended option

**Migration guide:**
- Existing MINGW64 users should install CLANG64 packages: `pacman -S mingw-w64-clang-x86_64-llvm mingw-w64-clang-x86_64-mlir mingw-w64-clang-x86_64-cmake mingw-w64-clang-x86_64-ninja`
- Update PATH to use `/clang64/bin` instead of `/mingw64/bin`
- Update CMake configuration to point to `/clang64/lib/cmake/mlir` and `/clang64/lib/cmake/llvm`
- Rebuild the project with the new toolchain

**Files updated:**
- `QUICKSTART.md`, `WINDOWS_SETUP.md`, `README.md`
- `.vscode/settings.json` (also updated to D: drive for local environment)
- `scripts/setup-msys2.ps1`, `scripts/verify-setup.ps1`
- All tutorial files in `docs/tutorials/*.md`
- Note: `CHANGELOG-WinOS.md` preserves historical MINGW64 references

## Major Changes (Historical)

### Documentation

#### README.md
- **Complete rewrite** focused on Windows/MSYS2 workflow
- Added "Why This Fork?" section explaining benefits
- Replaced Bazel instructions with MSYS2/CMake quickstart
- **Complete tutorial series** - All 13 tutorials now linked and organized by difficulty
- Step-by-step installation guide
- Troubleshooting section for common Windows issues
- IDE setup instructions for VSCode and CLion
- Moved Bazel content to collapsible sections

#### New Tutorial Series (docs/tutorials/)
**All 13 Windows-adapted MLIR tutorials now complete!**

**Beginner Tutorials (1-4):**
- **01-getting-started.md** - MSYS2 setup, MLIR basics, first program
- **02-running-and-testing.md** - lit/FileCheck testing, progressive lowering
- **03-writing-first-pass.md** - Pattern rewriting, IR walking
- **04-using-tablegen.md** - TableGen for passes, CMake integration

**Intermediate Tutorials (5-9):**
- **05-defining-dialect.md** - Custom dialects, types, operations
- **06-using-traits.md** - Operation traits, optimization enablement
- **07-folders-constant-propagation.md** - Constant folding, SCCP
- **08-verifiers.md** - Verification, error messages
- **09-canonicalizers.md** - DRR patterns, constraints

**Advanced Tutorials (10-13):**
- **10-dialect-conversion.md** - Systematic conversion framework
- **11-lowering-through-llvm.md** - Complete lowering, JIT, codegen
- **12-dataflow-analysis.md** - Analysis framework, lattices
- **13-pdll-patterns.md** - Pattern Description Language

**Tutorial Index:**
- **README.md** - Complete series overview with learning paths

**Total Content:** ~40,000+ words, 150+ code examples, comprehensive Windows/CMake coverage

#### New Standalone Guides
- **QUICKSTART.md** - 5-minute getting started guide
- **WINDOWS_SETUP.md** - Comprehensive 4000+ word Windows development guide
  - Detailed MSYS2 vs MinGW64 explanation
  - Installation walkthrough
  - IDE configuration (VSCode, CLion, Rider)
  - Building and running tutorials
  - Extensive troubleshooting section
  - Advanced topics (cross-compilation, performance tuning, etc.)
- **CHANGELOG-WinOS.md** - This file

### Build System

#### CMakeLists.txt
- Added Windows/MSYS2 auto-detection
- Automatic MLIR/LLVM path discovery for C: and D: drive installations
- Made or-tools dependency optional (can be disabled)
- Added detailed status messages for easier debugging
- Maintained compatibility with existing CMake workflow

### Scripts

#### scripts/setup-msys2.ps1
**Automated MSYS2 setup script**
- Installs MSYS2 via winget/chocolatey
- Updates MSYS2 package database
- Installs complete LLVM/MLIR toolchain
- Configures Windows PATH
- Verifies installation
- Beautiful CLI output with progress indication

#### scripts/build-windows.ps1
**Automated build script**
- Auto-detects MSYS2 installation (C: or D: drive)
- Configures CMake with correct paths
- Builds with Ninja
- Runs tests automatically
- Options for Debug/Release, clean builds, disabling or-tools
- Detailed progress output
- Error handling with helpful messages

#### scripts/verify-setup.ps1
**Setup verification script**
- Tests all prerequisites
- Verifies tools are MINGW64 versions (not MSYS)
- Checks CMake config files exist
- Validates functional execution
- Provides specific fix suggestions for each issue
- Color-coded output (green = pass, red = fail)

### IDE Configuration

#### .vscode/settings.json
- MSYS2 tool paths (mlir-opt, cmake, ninja, etc.)
- Three terminal profiles (PowerShell, MINGW64, MSYS)
- C++ configuration for IntelliSense
- CMake integration
- File associations for MLIR/LLVM files
- Search/watcher exclusions for build directories

#### .vscode/tasks.json
- Build tasks (Debug, Release, Clean)
- Run tutorial-opt on current file
- Apply MLIR passes (canonicalize, etc.)
- Show available dialects
- Manual CMake configure and Ninja build
- Run test suite

#### .vscode/launch.json
- Debug configurations for Visual Studio debugger (cppvsdbg)
- Debug configurations for GDB
- Pre-launch build tasks
- Current file and custom arguments support

#### .vscode/extensions.json
- Recommended extensions for MLIR/LLVM development
- C/C++ tools
- CMake tools
- Markdown support

### Repository Configuration

#### .gitignore
- Keep .vscode shared settings, ignore personal configs
- Windows-specific patterns (*.exe, *.obj, *.dll, *.pdb)
- JetBrains IDE patterns (.idea/, cmake-build-*)
- Build artifact exclusions

## Philosophy Changes

### From: "Build Everything from Source"
- Original tutorial: Clone LLVM submodule, build from source (2-4 hours)
- **New approach**: Use pre-built MSYS2 packages (5 minutes)

### From: "Bazel-First"
- Original tutorial: Requires learning Bazel
- **New approach**: CMake (more familiar to Windows developers)

### From: "Linux/Mac Primary, Windows Secondary"
- Original tutorial: macOS build scripts, Bazel (Google-centric)
- **New approach**: Windows-first with native tooling

### From: "Expert Audience"
- Original tutorial: Assumes Unix familiarity, build system expertise
- **New approach**: Beginner-friendly with automated setup

## Technical Decisions

### Why MSYS2/MinGW64?

1. **Pre-built LLVM/MLIR** - No compilation required
2. **Package management** - pacman for easy updates
3. **Native binaries** - Produces true Windows .exe files
4. **Active maintenance** - Regular LLVM updates
5. **No runtime dependencies** - Unlike Cygwin/MSYS compatibility layer

### Why Not WSL?

- Not truly "Windows native"
- Adds virtualization overhead
- Path translation complexity
- Not all Windows tools work in WSL
- This branch focuses on native Windows experience

### Why CMake over Bazel?

- More familiar to Windows developers
- Simpler for learning MLIR (not learning build system)
- Better IDE integration on Windows
- Bazel still available on main branch

### Why PowerShell Scripts?

- Native to Windows
- No additional installation required
- Good tooling support
- Can automate system configuration

## Compatibility

### What Still Works
- All original MLIR tutorial code (lib/, tests/, tools/)
- CMake build (enhanced, not replaced)
- All tutorial examples and tests
- Cross-platform compatibility (still builds on Linux/Mac with CMake)

### What's Different
- Default build method (CMake instead of Bazel)
- Documentation focus (Windows instead of Linux/macOS)
- Setup process (package manager instead of source build)

### What's Added
- Windows automation scripts
- VSCode configuration
- Comprehensive Windows documentation
- Setup verification tools

## Migration Guide

### For Users of the Original Tutorial

If you were using the original tutorial and want to switch:

1. Switch to this branch:
   ```bash
   git checkout WinOS-CMake
   ```

2. If you built LLVM from source, you can now remove it:
   ```bash
   rm -rf externals/llvm-project/build
   ```

3. Install MSYS2 packages:
   ```bash
   # In MINGW64 terminal
   pacman -S mingw-w64-x86_64-llvm mingw-w64-x86_64-mlir \
             mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
   ```

4. Build with new script:
   ```powershell
   .\scripts\build-windows.ps1
   ```

### For New Users

Just follow the QUICKSTART.md guide - no migration needed!

## Future Plans

### Potential Additions
- [ ] GitHub Actions workflow for Windows CI
- [ ] Chocolatey package for one-command install
- [ ] Integration examples with Fidelity Framework
- [ ] Performance profiling guide with Tracy
- [ ] Docker container option (for those who prefer containers)
- [ ] Visual Studio (non-Code) configuration

### Maintenance
- Keep LLVM/MLIR package versions in sync with MSYS2 updates
- Update documentation as MLIR evolves
- Maintain compatibility with upstream tutorial updates

## Credits

### Original Tutorial
- **Author**: Jeremy Kun ([@j2kun](https://github.com/j2kun))
- **Repository**: [github.com/j2kun/mlir-tutorial](https://github.com/j2kun/mlir-tutorial)
- **Articles**: [jeremykun.com](https://jeremykun.com)

### WinOS-CMake Branch
- Windows-native adaptation for Fidelity Framework development
- MSYS2/MinGW64 integration
- PowerShell automation
- Comprehensive Windows documentation

## License

Same as original mlir-tutorial: Apache 2.0 with LLVM Exceptions

## See Also

- [README.md](README.md) - Main documentation
- [QUICKSTART.md](QUICKSTART.md) - Fast getting started
- [WINDOWS_SETUP.md](WINDOWS_SETUP.md) - Detailed Windows guide
