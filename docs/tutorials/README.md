# MLIR Tutorial Series - Windows Native Edition

This directory contains Windows-adapted versions of Jeremy Kun's excellent [MLIR tutorial series](https://jeremykun.com). These tutorials focus on MLIR concepts while using **Windows-native tooling** (MSYS2/MinGW64 and CMake) instead of Bazel.

**📘 For complete details about these tutorials, see [TUTORIAL_COMPLETION_SUMMARY.md](../TUTORIAL_COMPLETION_SUMMARY.md)**

## Important Context for Tutorial Users

### Origins and Timeline

These tutorials are based on Jeremy Kun's blog articles **written in 2023** during his time at Google. While MLIR APIs evolve, the **fundamental concepts remain valid**. These tutorials have been enhanced with pedagogical narrative from those original articles and will be **updated as APIs change** to reflect 2025+ MLIR patterns as they emerge through practical use.

### Understanding the Tutorial's Scope and Bias

**Critical perspective:** Many of these tutorials carry a **subtle tensor processing bias** reflecting their origins in Google's machine learning infrastructure work. While tensor operations are important, they represent only **one domain** among many that MLIR serves.

**The Fidelity Framework context:** These tutorials are hosted within the mlir-tutorial repository to support the **Fidelity Framework** and its **Firefly compiler**—an F# compiler targeting the full spectrum of LLVM backends **and beyond**:

- **LLVM-supported targets:** CPU (x86, ARM, RISC-V), GPU (CUDA, ROCm, Vulkan), specialized accelerators
- **Beyond LLVM:** IoT microcontrollers, FPGA fabric, CGRA (Coarse-Grained Reconfigurable Architectures), neuromorphic processors
- **Future expansion:** Custom silicon, domain-specific hardware, emerging compute paradigms

**The lesson:** View these tutorials as teaching **core MLIR infrastructure patterns**—dialect design, transformation passes, progressive lowering, analysis frameworks—that apply across all compilation targets. Do not over-index on tensor operations as the primary use case.

### Compilation Philosophy: Correct by Construction

**A subtle but crucial insight from the tutorials:** Many examples address challenges arising from **dynamic and gradually-typed languages** (Python, etc.) where:
- Type information is incomplete or arrives late
- IR must be reconstructed through multiple passes
- Recursive compilation and re-lowering occur
- Optimization passes spend significant effort "fixing" structural problems introduced by permissive source languages

You'll notice throughout tutorials 7-11 that considerable pass complexity addresses **inserting structure that wasn't present semantically**—normalization, canonicalization, verification, type conversion, bufferization.

**The Fidelity Framework difference:** F# is a **strongly-typed functional language** following the **"correct by construction"** philosophy:
- Type correctness enforced at source level by design-time LSP/compiler services
- Rich static type information propagates through compilation
- Structural correctness guaranteed before lowering begins
- Pattern matching and algebraic types map naturally to MLIR dialects

**What this means for tutorial interpretation:** While the tutorials demonstrate comprehensive pass pipelines with many transformation stages, the Firefly compiler aims for **fewer passes** and **less churn** in lowering pathways. When a tutorial shows 5-7 passes to achieve a lowering, consider it demonstrative of MLIR's *capabilities*, not necessarily the *minimal path* for strongly-typed source languages.

The high-level takeaway: **These tutorials teach essential MLIR infrastructure, but your actual compilation pipelines may be simpler and more direct** when working with languages that provide strong static guarantees.

## Tutorial Series

### Core Tutorials (Available Now)

1. **[Getting Started](01-getting-started.md)**
   - What is MLIR and why use it?
   - Setting up MSYS2/MinGW64 on Windows
   - Building the tutorial with CMake
   - Your first MLIR program
   - Understanding dialects and progressive lowering

2. **[Running and Testing a Lowering](02-running-and-testing.md)**
   - Understanding MLIR dialects and lowering passes
   - Testing with lit and FileCheck
   - Writing test files with RUN: and CHECK: directives
   - Running code with mlir-cpu-runner
   - CMake test infrastructure

3. **[Writing Your First Pass](03-writing-first-pass.md)**
   - What is a pass?
   - Implementing pattern rewriting
   - Walking the IR tree
   - Building and testing passes
   - Debugging techniques

4. **[Using TableGen for Passes](04-using-tablegen.md)**
   - What TableGen is and why it's used
   - Writing `.td` files to define passes
   - CMake integration with `mlir_tablegen()`
   - Understanding generated code
   - Pass options and statistics

5. **[Defining a New Dialect](05-defining-dialect.md)**
   - Dialect architecture and design decisions
   - Writing TableGen definitions for dialects
   - Defining parameterized types with storage classes
   - Creating operations with custom syntax
   - CMake build integration

6. **[Using Traits](06-using-traits.md)**
   - Understanding operation traits
   - Using built-in traits (Pure, ElementwiseMappable)
   - Memory effect modeling
   - Enabling compiler optimizations automatically
   - Creating custom reusable traits

7. **[Folders and Constant Propagation](07-folders-constant-propagation.md)**
   - Constant propagation vs canonicalization
   - Implementing folder methods for operations
   - Creating constant operations
   - Writing constant materializers
   - Using SCCP pass

8. **[Verifiers](08-verifiers.md)**
   - Understanding verification in MLIR
   - Using built-in verification traits
   - Implementing custom operation verifiers
   - Creating reusable verification traits
   - Writing good error messages
   - Testing verifiers

9. **[Canonicalizers and Declarative Rewrite Patterns](09-canonicalizers.md)**
   - Understanding canonicalization vs folding
   - Implementing C++ canonicalization patterns
   - Writing declarative rewrite rules (DRR) in TableGen
   - Using pattern constraints and variable binding
   - CMake integration for DRR patterns
   - Testing canonicalization passes

10. **[Dialect Conversion](10-dialect-conversion.md)**
    - Understanding the dialect conversion framework
    - Implementing type converters
    - Writing conversion patterns with ConversionTarget
    - Handling partial vs full conversion
    - Using materialization hooks for type conflicts
    - Converting structural operations (func, scf, etc.)

11. **[Lowering through LLVM](11-lowering-through-llvm.md)**
    - Understanding the LLVM dialect as exit dialect
    - Building complete lowering pipelines
    - Handling bufferization (tensor → memref)
    - Converting func operations to LLVM
    - Translating MLIR to LLVM IR with mlir-translate
    - JIT compilation and execution on Windows

12. **[A Global Optimization and Dataflow Analysis](12-dataflow-analysis.md)**
    - Understanding dataflow analysis fundamentals
    - Using MLIR's dataflow analysis framework
    - Implementing lattice structures
    - Writing transfer functions
    - Creating custom analyses (noise propagation example)
    - Building optimization passes using analysis results

13. **[Defining Patterns with PDLL](13-pdll-patterns.md)**
    - Understanding PDLL vs TableGen DRR
    - Writing PDLL pattern files (.pdll)
    - Using advanced pattern matching features
    - Implementing constraints and native code integration
    - Compiling PDLL with mlir-pdll on Windows
    - CMake integration for PDLL patterns

## Pedagogical Enhancement

These tutorials go **beyond platform adaptation**. Eleven tutorials (01, 04-13) have been **pedagogically enhanced** with deep conceptual narrative extracted from Jeremy Kun's original 2023 blog articles:

- **Philosophical depth** - Why features exist, design trade-offs, architectural insights
- **Honest assessments** - Limitations, documentation gaps, learning curve realities, evolution status
- **Contextual connections** - How features compose, when to use different approaches, why multiple mechanisms exist

**Word count:** Enhanced tutorials average ~3,685 words vs ~2,500 in technical-only versions, providing rich learning experiences that explain **why** design decisions were made, **when** to apply techniques, and **what limitations** exist in practice.

See [TUTORIAL_COMPLETION_SUMMARY.md](../TUTORIAL_COMPLETION_SUMMARY.md) for complete enhancement methodology and verification details.

## Original Articles

All tutorials are based on Jeremy Kun's original articles at [jeremykun.com](https://jeremykun.com):
- [Original tutorial index](https://jeremykun.com/2023/08/10/mlir-getting-started/)
- [GitHub repository](https://github.com/j2kun/mlir-tutorial)

**Attribution:** Jeremy Kun's pedagogical insights are preserved throughout these tutorials while maintaining professional clarity appropriate for technical education.

## What's Different in These Tutorials?

### Original Tutorials
- ❌ Bazel build system (Google-centric)
- ❌ Build LLVM from source (2-4 hours)
- ❌ macOS/Linux focused
- ❌ Workspace and dependency complexity

### Windows-Native Tutorials
- ✅ CMake build system (Windows-friendly)
- ✅ Pre-built LLVM/MLIR via MSYS2 (5 minutes)
- ✅ Windows-first with PowerShell automation
- ✅ Simpler setup, focus on MLIR concepts

## How to Use These Tutorials

### Recommended Path

1. **Complete setup** from main [README.md](../../README.md) or [QUICKSTART.md](../../QUICKSTART.md)
2. **Start with Tutorial 01** and work sequentially
3. **Read original articles** for additional context and explanations
4. **Run the examples** in the `tests/` directory as you go
5. **Experiment** - modify code and see what happens!

### Prerequisites

Before starting:
- ✅ MSYS2 installed with LLVM/MLIR packages
- ✅ Repository cloned and built successfully
- ✅ `tutorial-opt.exe` in `build/bin/` directory

Verify setup:
```powershell
.\scripts\verify-setup.ps1
```

### Getting Help

- **Tutorial questions:** Read the [original article](https://jeremykun.com) for that tutorial
- **Windows setup issues:** See [WINDOWS_SETUP.md](../../WINDOWS_SETUP.md)
- **MLIR concepts:** Check [mlir.llvm.org](https://mlir.llvm.org/)
- **Build problems:** See [troubleshooting](../../WINDOWS_SETUP.md#troubleshooting)

## Tutorial Contents Overview

### Beginner (Tutorials 1-3)

Learn MLIR basics:
- What MLIR is and how it works
- Running transformations
- Writing simple passes
- Testing your code

**Time commitment:** 2-4 hours

### Intermediate (Tutorials 4-9)

Build custom dialects:
- TableGen for code generation
- Defining operations and types
- Adding traits and verifiers
- Optimization patterns

**Time commitment:** 6-10 hours

### Advanced (Tutorials 10-13)

Production-ready features:
- Systematic dialect conversion
- LLVM IR generation
- Dataflow analysis
- Advanced pattern languages

**Time commitment:** 8-12 hours

## Code Examples

All code examples in these tutorials can be found in the repository:

- **Tutorial code:** `lib/Dialect/`, `lib/Transform/`, `lib/Conversion/`
- **Test files:** `tests/*.mlir`
- **Main tool:** `tools/tutorial-opt.cpp`

## Building and Testing

```powershell
# Build everything
.\scripts\build-windows.ps1

# Run specific test
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir

# Run all tests
cd build
ninja check-mlir-tutorial
```

## Contributing

Found an error or have a suggestion? These tutorials are part of the WinOS-CMake branch. Please:
1. Check if the issue is with the tutorial content or Windows setup
2. Open an issue describing the problem
3. Include your Windows version, MSYS2 version, and error messages

### Future Tutorial Expansion

The current 13 tutorials cover **core MLIR infrastructure**. As the Fidelity Framework and Firefly compiler evolve, **additional tutorials may be added** addressing:

- **Non-tensor domains:** DSP pipelines, control flow-heavy applications, embedded systems patterns
- **Alternative lowering paths:** Direct-to-hardware mappings bypassing LLVM, FPGA synthesis patterns
- **Functional language patterns:** Algebraic data types, pattern matching compilation, tail recursion optimization
- **Performance-critical paths:** Zero-copy transformations, minimal-pass pipelines, "correct by construction" dialect design
- **Domain-specific targets:** Neuromorphic computing abstractions, CGRA configuration, custom accelerator integration

These potential additions would complement the foundational knowledge established in the current tutorial series.

## Additional Resources

### MLIR Documentation
- [MLIR Website](https://mlir.llvm.org/)
- [Getting Started](https://mlir.llvm.org/getting_started/)
- [Toy Tutorial](https://mlir.llvm.org/docs/Tutorials/Toy/)
- [Language Reference](https://mlir.llvm.org/docs/LangRef/)

### LLVM Documentation
- [LLVM Website](https://llvm.org/)
- [Programmer's Manual](https://llvm.org/docs/ProgrammersManual.html)

### Community
- [LLVM Discourse](https://llvm.discourse.group/)
- [MLIR Discord](https://discord.gg/xS7Z362) - #mlir channel

### Windows Development
- [MSYS2 Website](https://www.msys2.org/)
- [MinGW-w64](https://www.mingw-w64.org/)
- [CMake Documentation](https://cmake.org/documentation/)

## License

Same as the main repository: Apache 2.0 with LLVM Exceptions

## Credits

- **Original Tutorials:** Jeremy Kun ([@j2kun](https://github.com/j2kun))
  - Original blog articles (2023) at [jeremykun.com](https://jeremykun.com)
  - Pedagogical insights integrated throughout these enhanced tutorials
- **Windows Adaptation & Enhancement:** WinOS-CMake branch maintainers
  - Platform adaptation for Windows/MSYS2/CMake
  - Pedagogical narrative extraction and integration
  - Fidelity Framework contextualization
- **MLIR/LLVM:** LLVM Foundation and contributors
- **Target Framework:** Fidelity Framework & Firefly Compiler (F# to diverse hardware targets)

---

**Start Learning:** [Tutorial 01: Getting Started →](01-getting-started.md)

**For complete context:** [TUTORIAL_COMPLETION_SUMMARY.md](../TUTORIAL_COMPLETION_SUMMARY.md)
