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

### Fidelity Philosophy

**A subtle but crucial insight from the tutorials:** Many examples address challenges arising from **dynamic and gradually-typed languages** (Python, etc.) where:
- Type information is incomplete or must be reconstructed
- IR must be reformulated through multiple passes
- Recursive compilation and re-lowering can be triggered
- Optimization passes spend significant effort "fixing" structural problems introduced by permissive source languages

You'll notice throughout tutorials 7-11 that considerable pass complexity addresses **inserting structure that wasn't present semantically**—normalization, canonicalization, verification, type conversion, bufferization.

**The Fidelity Framework difference:** F# is a **strongly-typed functional language** making a good faith effort to embrace a **"correct by construction"** principle:
- Type correctness enforced at source level by design-time LSP/compiler services
- Rich static type information propagates through compilation
- Structural correctness guaranteed before lowering begins
- Pattern matching and algebraic types map naturally to MLIR dialects

**What this means for tutorial interpretation:** While the tutorials demonstrate comprehensive pass pipelines with many transformation stages, the Firefly compiler aims for **fewer passes** and **less churn** in lowering pathways. When a tutorial shows 5-7 passes to achieve a lowering, consider it demonstrative of MLIR's *capabilities*, not necessarily the *minimal path* for strongly-typed source languages.

The high-level takeaway: **These tutorials teach essential MLIR infrastructure, but your actual compilation pipelines may be simpler and more direct** when working with languages that provide strong static guarantees. This is still useful to know for understanding the Fidelity Framework's compilation pathway, though.

**Important context on other strongly-typed languages:** Haskell, Rust, and Swift all use LLVM and could fall into the "correct by construction" category with similar benefits. However, **these languages target LLVM directly, not MLIR**. While experimental bindings exist (mlir-hs for Haskell), **F# via the Fidelity Framework may be the first general-purpose language making general-purpose use of MLIR for compilation**. This pioneering position means the Firefly compiler may be the first to demonstrate how MLIR's multi-level IR capabilities can significantly enhance compilation pathways for strongly-typed functional languages.

Given these tutorials' tensor-processing focus and Python-centric bias, the challenges addressed here are a subset of the full gamut of F#'s needs. **As the Fidelity Framework matures, these tutorials may shift significantly**—new concerns specific to F#/MLIR/LLVM pathways may require deeper scrutiny, while issues emphasized here may prove less pertinent. Consider this tutorial series a living document that will evolve as real-world experience reveals the true friction points.

**For technical details about how the Fidelity Framework achieves this efficiency, see the [Technical Addendum](#technical-addendum-fidelity-frameworks-compilation-pathway) below.**

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
- **Performance-critical paths:** Zero-copy transformations, minimal-pass pipelines
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

## Technical Addendum: Fidelity Framework's Compilation Pathway

This section provides technical depth on how the Fidelity Framework achieves the "fewer passes, less churn" efficiency mentioned in the compilation philosophy above.

### The FCS Foundation: Type-Checked AST as Starting Point

Most compilation tutorials—including these MLIR tutorials—begin from **raw source text** or **loosely-typed ASTs** that require extensive analysis passes to establish semantic correctness. The Fidelity Framework starts differently.

**F# Compiler Services (FCS)** provides:
- **Fully type-checked Abstract Syntax Tree** - Complete type information for every expression, function, and binding
- **Semantic resolution** - All symbols resolved, overloads determined, type inference completed
- **Design-time correctness** - The same infrastructure powering your IDE's autocompletion and error squiggles guarantees correctness before compilation begins

This means when Firefly begins lowering to MLIR, **structural correctness is already guaranteed**. No reconstruction needed.

### Program Hypergraph (PHG): The Architectural Map

Between FCS and MLIR sits the **Program Hypergraph (PHG)**—a symbolic/semantic representation that preserves:

**Reachability and Tree Shaking:**
- **Type-aware pruning** - Starting from entry points (main, exports), traverse only reachable code
- **Dead code elimination at source** - Unused functions, types, and bindings never enter the compilation pipeline
- **Zero-cost abstractions enforced** - Abstractions that compile away are verified to compile away *before* lowering

**Natural Compilation Boundaries:**
- **Coupling and cohesion analysis** - Measures inter-module dependencies to identify natural compilation units
- **Modular compilation** - Strongly-bounded modules compile independently, avoiding whole-program overhead
- **MLIR module organization** - PHG boundaries map to MLIR module boundaries, enabling parallel compilation

### Program Hypergraph (PHG): Supporting Heterogeneous Targets

The **Program Hypergraph (PHG)** is PHG's evolution for modern compilation challenges:

**Multi-way Relationships:**
- **Hyperedges** preserve relationships involving 3+ entities (not just binary call graphs)
- **Supports control-flow** - Traditional CPU architectures with sequential execution
- **Supports dataflow** - Emerging architectures (FPGA, CGRA, neuromorphic) where computation is inherently parallel

**Architectural Flexibility:**
- **Recursion schemes and bidirectional zippers** - Efficient traversal patterns for different optimization passes
- **Hypergraph partitioning** - Natural splits for heterogeneous compilation (CPU kernel + GPU kernel + FPGA fabric)
- **Temporal learning** - Future vision: compiler learns optimal patterns across compilations, storing knowledge in the hypergraph

### The Direct Pathway: Fewer Passes, Less Churn

Putting it together—the Firefly compilation pipeline:

```
F# Source Code
    ↓
F# Compiler Services (FCS)
    ├─ Type checking
    ├─ Symbol resolution
    └─ Semantic analysis
    ↓
Fully Type-Checked AST
    ↓
Program Hypergraph (PHG)
    ├─ Reachability analysis (tree shaking)
    ├─ Coupling/cohesion boundaries
    └─ Architecture mapping
    ↓
Type-Preserved Hypergraph
    ↓
MLIR High-Level Dialects
    ├─ Domain-specific operations
    ├─ Algebraic types preserved
    └─ Pattern matching lowered
    ↓
Progressive Optimization
    └─ Minimal passes (already structured)
    ↓
LLVM Dialect
    ↓
Native Binary / Hardware Configuration
```

**Why this is more direct than tutorial examples:**

1. **No type reconstruction** - Types flow from FCS through PHG to MLIR, never needing inference or recovery
2. **No structural normalization** - F#'s algebraic types and pattern matching map naturally to MLIR's SSA form
3. **No verification by discovery** - Verifiers check contracts, not discover semantic problems (already impossible in well-typed F#)
4. **No canonicalization churn** - FCS ensures canonical representations at source level (no `x + 0`, no `x * 1`)
5. **No whole-program bufferization** - Explicit control over allocation strategy via effect types and region analysis

### Comparison: Dynamic vs Strongly-Typed Pathways

**Python/Dynamic Language Path (as seen in tutorials):**
```
Python Source → Parsing → Type Inference → Reconstruction →
Canonicalization → Verification → Type Conversion → Bufferization →
Dialect Lowering → More Canonicalization → LLVM → Binary
```
*Many passes reconstructing semantic information that was never explicit.*

**F# via Firefly Path:**
```
F# Source → FCS (Type-Checked AST) → PHG (Hypergraph) →
MLIR High-Level → Targeted Lowering → LLVM → Binary
```
*Semantic information preserved through compilation, not reconstructed.*

### Proof-Aware Compilation: Optimization Through Verification

What truly distinguishes the Fidelity Framework from traditional compilation approaches is **proof-aware compilation**—treating formal verification not as a constraint on optimization, but as an *enabler* of it.

**The traditional false choice:** Safety checks impose runtime overhead, or trust the optimizer won't break invariants. Proof assistants generate conservative code. Verification and optimization oppose each other.

**The Fidelity Framework approach:** Proofs are first-class hyperedges in the PHG that *guide aggressive optimization*. When the compiler understands what properties must be preserved, it can transform everything else with confidence. The proofs themselves reveal optimization opportunities.

**Proofs as optimization enablers:**
- **Array bounds elimination** - Proof hyperedges showing all accesses use the same pattern enable check hoisting outside loops
- **Check fusion** - Multiple checks with shared preconditions combine into one when proof hyperedges reveal the relationship
- **Zero-cost safety** - Memory layouts defined at F# level, verified through F* annotations, lowered to MLIR SMT dialect with verification preserved but runtime checks eliminated
- **Performance guarantees** - Proofs of bounded loop iteration enable full unrolling; proofs of cache-aligned access enable confident SIMD usage

**The three-layer strategy:**

1. **PHG layer** - Complete visibility into structure and proof obligations. Most aggressive optimizations occur here: proof-guided fusion, algebraic simplification validated by proofs, abstraction elimination where proofs show semantic transparency.

2. **MLIR layer with SMT dialect** - Proof constraints travel as operations in the MLIR SMT dialect (based on "First-Class Verification Dialects for MLIR" PLDI 2025). Optimizations are *translation-validated*: transformations are checked to ensure they preserve verified properties. Found 5 upstream MLIR bugs through this approach.

3. **LLVM layer** - Architecture-specific tuning within boundaries established by proof metadata. LLVM isn't asked to preserve high-level properties it can't understand; it receives pre-optimized code with clear boundaries.

**Opt-in verification with graduated formalism:** Developers write standard F# with optional verification annotations. The hypergraph automatically derives and maintains proof obligations. No separate verification languages required. Proofs can be applied to specific functions or code sections—not all-or-nothing.

**Safety standards as reusable proof libraries:** MISRA-C, DO-178C, and similar patterns become instantiable proof hyperedges. A MISRA Rule 17.1 (pointer arithmetic) hyperedge doesn't just check compliance—it carries optimization knowledge about safe transformations.

**Patent-pending innovation:** SpeakEZ has patent pending (US 63/786,264) for "Verification-Preserving Compilation Using Formal Certificate Guided Optimization"—maintaining verification properties across aggressive optimizations targeting heterogeneous hardware.

### The Alloy Library: Zero-Allocation Runtime

Complementing the compilation pathway, the **Alloy library** provides:
- **BCL shadow** - Zero-allocation alternatives to Base Class Library operations
- **Stack allocation patterns** - Structs, spans, and stack-only types for performance-critical paths
- **Fidelity-aware APIs** - Library functions designed to preserve semantic information through compilation

This ensures that even at the runtime, the "correct by construction" philosophy extends through execution.

### Key Takeaway

**These MLIR tutorials teach essential infrastructure knowledge**—dialect design, pass mechanisms, analysis frameworks, lowering strategies. This knowledge remains critical for understanding how MLIR works and how to extend it.

**But the Fidelity Framework demonstrates** that with strong static types, functional programming principles, and careful semantic preservation through FCS and PHG, many of the reconstruction passes shown in tutorials become unnecessary or significantly simplified.

The tutorials show what's *possible*. The Fidelity Framework shows what's *efficient* for F#: a strongly-typed, functional-first source language.

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
