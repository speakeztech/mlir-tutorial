# Tutorial 01: Getting Started with MLIR on Windows

**Original Article:** [MLIR ,  Build System (Getting Started)](https://jeremykun.com/2023/08/10/mlir-getting-started/) by Jeremy Kun

**Windows Adaptation:** This tutorial replaces Bazel workspace setup with MSYS2/CMake for native Windows development.

---

## What is MLIR? (And Why Should You Care?)

MLIR (Multi-Level Intermediate Representation) emerged from a recognition by Chris Lattner and the compiler community that LLVM, despite its tremendous success, had "painted itself into a corner" in certain fundamental ways. Understanding what MLIR addresses helps us see why it matters for modern compiler construction.

### The LLVM Success Story and Its Limits

LLVM revolutionized compiler infrastructure when it emerged in the early 2000s. Its clean IR design, modular architecture, and permissive licensing made it the foundation for countless projects from Clang to Swift to CUDA. But as Chris Lattner observed, LLVM's single-level IR approach created constraints that became increasingly apparent:

**The abstraction mismatch:** LLVM IR was designed for general-purpose CPU code generation. It operates at a relatively low abstraction level with pointers, registers, and basic blocks. This works beautifully for C-like languages targeting CPUs, but creates challenges for:
- Machine learning workloads that need tensor-level reasoning
- Polyhedral loop optimizations that require structured loop representations
- Domain-specific accelerators (GPUs, TPUs, FPGAs, neuromorphic processors)
- High-level algebraic transformations before lowering to machine operations

**The core tension:** Modern compilers need to optimize at multiple abstraction levels simultaneously. When compiling a neural network, you want to:
- Reason about tensor shapes and dimensions (high-level)
- Apply algebraic simplifications (mid-level)
- Generate efficient SIMD code (low-level)
- Target diverse hardware (CPUs, GPUs, custom accelerators)

Traditional compilers, including LLVM-based ones, force an immediate descent to a single IR. You start with high-level source code, lower to the IR, optimize there, and emit machine code. But once you've lowered to that IR, you've discarded the high-level structure you need for sophisticated domain-specific optimizations. As Jeremy Kun notes, "the rigid for loop structure had been discarded" by the time code reaches traditional optimizers. You can't optimize what you can no longer see.

### Enter MLIR: A Philosophy, Not Just a Tool

MLIR (Multi-Level Intermediate Representation) isn't just a compiler infrastructure, it's a **design philosophy**: break large compilers into lots of small compilers between sub-languages. Each intermediate representation (called a "dialect" in MLIR) is designed to make a particular kind of optimization natural to express.

Think of it like this:
- Traditional compiler: One giant leap from source code to assembly
- MLIR compiler: A series of small, understandable steps through different representations

**Why does this matter?**

Consider polyhedral loop optimizations (automatic parallelization, tiling, fusion). These work best when you can reason about loop structure explicitly. In traditional compilers, by the time code reaches the optimizer, "the rigid for loop structure had been discarded." You can't optimize what you can't see.

MLIR solves this by maintaining syntactic structure through multiple dialect layers. You keep the high-level loop structure, optimize there, and only discard it when you lower to simpler dialects. This "progressive lowering" is MLIR's killer feature.

### Key Concepts: Dialects as Mini-Languages

Think of dialects as **Lego blocks for compiler construction**. Each dialect is a small, focused language for a specific domain:

**`arith`** - Basic arithmetic operations
- Addition, subtraction, multiplication, division
- Integer and floating-point variants
- Comparison operations

**`func`** - Functions and calls
- Function definitions and declarations
- Call operations
- Return statements

**`scf`** - Structured control flow (if, for, while)
- High-level loop constructs
- Preserves loop structure for optimization
- Conditional branching

**`affine`** - Loop transformations and optimizations
- Polyhedral analysis and transformation
- Perfect loop nests
- Automatic parallelization

**`tensor`** - Tensor operations for ML
- Multi-dimensional arrays
- Shape inference
- Broadcasting semantics

**`llvm`** - LLVM IR dialect
- Low-level operations mapping to LLVM
- Pointers, memory operations
- Gateway to native code generation

And here's the insight: **you can mix these dialects in a single program**. Your function might use `tensor` ops for high-level computation, `affine` loops for iteration, `arith` for scalars, and `func` for structure, all at once.

### Progressive Lowering: The MLIR Way

Instead of one monolithic transformation, MLIR uses **incremental lowering**:

```
Your Custom Dialect → Standard Dialects → LLVM Dialect → Machine Code
     (yesterday)         (semantically       (today)        (hardware)
                          rich, optimizable)
```

Each arrow is a **pass**, a small, focused transformation. This approach has profound implications:

1. **Debuggability**: If something breaks, you know which pass caused it
2. **Reusability**: A pass that lowers `tensor` to `linalg` works for everyone
3. **Flexibility**: You can insert your custom optimization at the right level
4. **Testability**: Each pass can be tested independently

This is why MLIR matters: it's not about replacing your entire compiler, it's about giving you the right abstractions to build compilers **compositionally**.

### Why Choose MLIR Over Building From Scratch?

When I talk to compiler engineers, I hear the same objection: "I could just write this myself." And technically, yes, you could. But ask yourself:

- Do you want to write a parser? IR printer? SSA construction? Dominator tree analysis? Memory management for IR nodes?
- Do you want to debug all of that before you even start on your actual problem?

MLIR gives you:
- **Infrastructure**: Parsing, printing, verification, pass management, all solved
- **Reusable passes**: CSE, DCE, inlining, canonicalization, hundreds of optimizations ready to use
- **Ecosystem**: Tools, debuggers, visualizers that work with any MLIR dialect
- **Community**: Thousands of engineers at Google, Meta, Apple, Microsoft using and improving MLIR

But here's the real win: **you can focus on your domain**. If you're building a quantum compiler, you write quantum operations. MLIR handles the rest. If you're building a machine learning compiler, you define tensor operations. The infrastructure is already there.

### The Honest Truth About MLIR's Complexity

I won't sugarcoat this: MLIR has a steep learning curve. The ecosystem is:
- **Fast-moving**: APIs change, patterns evolve
- **Sparsely documented**: Many features lack comprehensive guides
- **LLVM-centric**: Documentation assumes you know LLVM internals

This tutorial series exists because I hit these barriers. I want people interested in advanced compilation (like Fully Homomorphic Encryption at Google) to contribute without spending months deciphering documentation written by experts for experts.

My promise: I'll show you the journey, mistakes included. When something is confusing, I'll say so. When there's a "just because" answer, I'll tell you. Learning MLIR is hard enough without pretending it's easy.

## Prerequisites: Why This Tutorial Uses Windows

Before we dive in, let me address the elephant in the room: **why a Windows-focused MLIR tutorial?**

Most MLIR resources assume you're on Linux or macOS. The official documentation uses Bazel or CMake with Unix assumptions. But here's reality: **many developers work on Windows**, especially in industrial and enterprise settings. Microsoft uses MLIR for DirectX compilation. Game engine developers use Windows. Financial technology often runs on Windows.

Yet Windows MLIR tutorials are nearly non-existent. So this series exists to fill that gap, using tools that work naturally on Windows: MSYS2 for UNIX-like utilities, CMake for builds, and PowerShell for scripting.

### What You Need

Before starting, ensure you have completed the setup from the main README:

1. **MSYS2 installed** with LLVM/MLIR packages
2. **Windows PATH configured** to include MSYS2 tools
3. **This repository cloned** and ready

If not, run the setup script:
```powershell
.\scripts\setup-msys2.ps1
```

This script automates what would otherwise be a painful manual process:
- Installing MSYS2 (a Unix-like environment for Windows)
- Installing pre-compiled LLVM/MLIR packages (saving 2-4 hours of compilation)
- Configuring PATH variables so tools are accessible
- Verifying that everything works

The script approach reflects a key lesson I learned: **setup friction kills learning momentum**. If someone has to spend 3 hours debugging build issues before writing their first line of code, they'll give up. So we automate the pain away.

## Verify Your Environment

Let's confirm MLIR is working:

```powershell
# Check MLIR version
mlir-opt --version

# Should show something like:
# MLIR (http://mlir.llvm.org/):
#   MLIR version 18.1.8
```

Check available dialects:
```powershell
mlir-opt --show-dialects
```

You should see a long list including: `affine`, `arith`, `func`, `llvm`, `math`, `scf`, and many more.

## Understanding the Repository Structure: A Guided Tour

When you clone this repository, you're not just getting code, you're getting a **working MLIR compiler project** structured following LLVM/MLIR conventions. Let's understand the philosophy behind this organization.

```
mlir-tutorial/
├── lib/                    # Custom dialect implementations
│   ├── Dialect/           # Dialect definitions (Poly, Noisy)
│   ├── Transform/         # Transformation passes
│   └── Conversion/        # Dialect conversion passes
├── tools/                  # Executables
│   └── tutorial-opt.cpp   # Our mlir-opt equivalent
├── tests/                  # Test files (.mlir)
└── CMakeLists.txt         # Build configuration
```

### The Philosophy of Separation

Notice how the structure separates **concerns**:
- `lib/Dialect/` defines **what operations exist** (the vocabulary)
- `lib/Transform/` defines **how to optimize** within a dialect
- `lib/Conversion/` defines **how to lower** between dialects
- `tools/` defines **how users interact** with the compiler
- `tests/` defines **expected behavior**

This isn't arbitrary. It reflects MLIR's compositional design: dialects are independent, passes are independent, tools compose them. You could add a new dialect without changing any passes. You could add a new pass without changing dialects. This loose coupling is intentional.

### Key Files and Their Roles

#### `tools/tutorial-opt.cpp` - The User-Facing Tool

This is your **custom `mlir-opt`**. Why build our own instead of using the standard `mlir-opt`?

```cpp
int main(int argc, char **argv) {
  // Register custom dialects
  mlir::DialectRegistry registry;
  registry.insert<mlir::tutorial::poly::PolyDialect>();
  registry.insert<mlir::tutorial::noisy::NoisyDialect>();

  // Register custom passes
  mlir::tutorial::registerPolyPasses();

  // Run the tool
  return mlir::MlirOptMain(argc, argv, "Tutorial Pass Driver\n");
}
```

**The reason:** `mlir-opt` only knows about standard MLIR dialects. Your custom `Poly` dialect? Not registered. Your custom passes? Unknown. By building `tutorial-opt`, you create a **custom compilation pipeline** that includes your extensions.

This is a key MLIR pattern: **don't modify MLIR itself; extend it through your own tools**. When you build a real compiler, you'll have `yourcompany-opt` that registers your proprietary dialects and passes. This keeps your code separate from upstream MLIR.

#### `lib/Dialect/Poly/` - A Complete Dialect Implementation

Let's look inside this directory:
```
Poly/
├── PolyDialect.h       # Dialect declaration
├── PolyDialect.cpp     # Dialect implementation
├── PolyDialect.td      # TableGen dialect definition
├── PolyOps.h           # Operation declarations
├── PolyOps.cpp         # Operation implementations
├── PolyOps.td          # TableGen operation definitions
└── CMakeLists.txt      # Build configuration
```

This structure follows MLIR convention:
- **`.h` files** declare the C++ API
- **`.cpp` files** implement behavior
- **`.td` files** describe structure declaratively (we'll learn TableGen in Tutorial 04)
- **`CMakeLists.txt`** tells the build system how to compile this

The `Poly` dialect implements **polynomial arithmetic**, operations like `poly.add`, `poly.mul`, `poly.from_tensor`. It's a complete example you can study and imitate when building your own dialects.

**Why polynomials?** They're complex enough to demonstrate real dialect features (custom types, attributes, operations) but simple enough to understand without domain expertise. They're the "Hello, World" of custom MLIR dialects.

#### `lib/Transform/` - Optimization Passes

This directory contains **dialect-agnostic optimizations** and **dialect-specific transformations**:

```
Transform/
├── Arith/
│   ├── MulToAdd.cpp      # Example: multiplication to addition
│   └── ...
└── Affine/
    └── ...               # Loop transformations
```

The separation matters. **Arith passes** work on arithmetic operations from the `arith` dialect. **Affine passes** work on loop nests from the `affine` dialect. This mirrors LLVM's structure: passes are organized by what they transform.

When you build your own compiler, you'll add `Transform/YourDialect/` with your custom optimizations.

#### `lib/Conversion/` - Lowering Passes

Conversion passes **translate between dialects**. They're distinct from transform passes:
- **Transform pass**: Optimizes within one dialect (`arith` → better `arith`)
- **Conversion pass**: Translates between dialects (`math` → `arith` + `scf`)

Why the separation? Because conversions have special requirements:
- They must handle **partial conversion** (some ops convert, others don't)
- They must maintain **type consistency** across dialect boundaries
- They use MLIR's **conversion framework** with pattern rewriting

MLIR provides infrastructure specifically for conversions (`ConversionPattern`, `TypeConverter`, `DialectConversion`). By isolating conversions in `lib/Conversion/`, we keep concerns separate.

#### `tests/*.mlir` - Literate Testing

Open any test file, and you'll see this pattern:
```mlir
// RUN: tutorial-opt %s --some-pass | FileCheck %s

func.func @test() {
  // ... MLIR code ...
}

// CHECK-LABEL: func.func @test
// CHECK: expected output
```

This is **literate testing**: test intent lives alongside the code being tested. The `RUN:` line says "how to run this," and `CHECK:` lines say "what to expect."

Why embed tests in source files instead of separate test files? Because when a transformation changes, you want to update the test immediately. Co-location reduces friction.

This pattern comes from LLVM, where it's been battle-tested on millions of lines of test code. It's verbose but scales well.

### The Build System Integration

Notice each subdirectory has its own `CMakeLists.txt`:
- `lib/Dialect/Poly/CMakeLists.txt` - Builds the Poly dialect
- `lib/Transform/Arith/CMakeLists.txt` - Builds arithmetic passes
- `tools/CMakeLists.txt` - Builds tutorial-opt

This **modular build structure** mirrors the code structure. Each component declares its dependencies:

```cmake
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp

  LINK_LIBS PUBLIC
  MLIRArithDialect
  MLIRIR
)
```

When you run `ninja tutorial-opt`, CMake:
1. Figures out tutorial-opt depends on MLIRPoly
2. Figures out MLIRPoly depends on MLIRArithDialect
3. Builds in correct dependency order
4. Links everything together

You rarely need to think about this, it just works. But understanding the structure helps when you add new dialects or passes.

### How This Structure Supports Learning

The repository is organized to **teach by example**:
- Want to define a dialect? Study `lib/Dialect/Poly/`
- Want to write a pass? Study `lib/Transform/Arith/MulToAdd.cpp`
- Want to test something? Study `tests/*.mlir`

Each component is **complete and working**. You're not reading fragments; you're reading real, tested, functional code. This is intentional, learning from working examples beats reading documentation.

## Building the Tutorial

### Quick Build

```powershell
# Using the automated script
.\scripts\build-windows.ps1
```

This will:
1. Configure CMake with correct MLIR/LLVM paths
2. Build with Ninja
3. Run tests
4. Create `build\bin\tutorial-opt.exe`

### Manual Build (Understanding the Process)

If you want to understand what's happening:

```powershell
# 1. Create build directory
mkdir build
cd build

# 2. Configure CMake
cmake -G Ninja `
      -DCMAKE_BUILD_TYPE=Debug `
      -DMLIR_DIR="C:\msys64\clang64\lib\cmake\mlir" `
      -DLLVM_DIR="C:\msys64\clang64\lib\cmake\llvm" `
      ..

# 3. Build
ninja

# 4. Verify it worked
.\bin\tutorial-opt.exe --help
```

### What CMake Does

The `CMakeLists.txt` file:
1. **Finds MLIR/LLVM** - Locates the installed packages
2. **Includes MLIR macros** - `AddMLIR.cmake` provides build helpers
3. **Processes subdirectories**:
   - `lib/` - Builds custom dialect libraries
   - `tools/` - Builds tutorial-opt executable
   - `tests/` - Sets up test infrastructure

### Understanding CMake vs Bazel: A Design Decision

This is the most significant departure from Jeremy Kun's original tutorial, so let me explain the reasoning.

**Original Tutorial (Bazel):**
```python
# WORKSPACE file
llvm_configure(
    name = "llvm-project",
    repo_mapping = {...},
)
```

**This Tutorial (CMake):**
```cmake
# CMakeLists.txt
find_package(MLIR REQUIRED CONFIG)
find_package(LLVM REQUIRED CONFIG)
```

#### Why Did Jeremy Choose Bazel?

Jeremy's reasoning was sound for his context:
1. **Google's infrastructure**: Bazel is Google's build tool, with on-call engineers maintaining MLIR compatibility
2. **Hermetic builds**: Bazel ensures reproducible builds across machines
3. **Monorepo philosophy**: Bazel excels at managing large codebases with many dependencies

For a production project at Google (like HEIR, the FHE compiler), these factors matter immensely.

#### Why Do We Choose CMake?

For **learning** MLIR on Windows, the calculus changes:

**Time to first build:**
- **Bazel**: 2-4 hours (downloads and compiles all of LLVM/MLIR from source)
- **CMake + MSYS2**: 5 minutes (uses pre-compiled packages)

**Cognitive overhead:**
- **Bazel**: Learn Bazel's syntax, workspace setup, target dependencies, runfiles, hermetic build concepts
- **CMake**: Use familiar `find_package`, `add_library`, `target_link_libraries` patterns

**Windows ecosystem fit:**
- **Bazel**: Requires extensive configuration for Windows paths and toolchains
- **CMake**: Native Windows support with MSYS2 integration

**Debugging workflow:**
- **Bazel**: Complex relationship between source files, build outputs, and runfiles directories
- **CMake**: Straightforward `build/` directory with familiar structure

#### The Honest Tradeoff

We're making a pedagogical tradeoff. Bazel's hermetic builds mean "it works the same everywhere." CMake with system packages means "it works if you installed packages correctly." We mitigate this with automated setup scripts.

If you're building a production MLIR compiler, consider Bazel once you understand the concepts. For learning? CMake gets you writing code faster, and that's what matters.

**The Philosophy Behind This Choice:**

I believe tutorials should minimize friction **orthogonal to the learning goal**. Your goal is to understand MLIR concepts, dialects, passes, operations, lowering. The build system is infrastructure. Spending hours debugging Bazel configurations doesn't teach you MLIR; it teaches you Bazel. We choose CMake so you can focus on what matters.

---

## 🧭 Navigation Guide

All of these tutorials use emojis to help you find your way:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 👉 Your First MLIR Program: Understanding SSA and Dialects

Let's create a simple MLIR program. But before you type it in, I want to highlight what makes MLIR syntax feel alien if you're coming from traditional programming languages.

Create `hello.mlir`:

```mlir
// hello.mlir - A simple function that adds two numbers

module {
  func.func @add(%arg0: i32, %arg1: i32) -> i32 {
    %result = arith.addi %arg0, %arg1 : i32
    return %result : i32
  }
}
```

### Why Does MLIR Look Like This?

When I first saw MLIR code, I thought: "Why is everything prefixed with `%`? Why do we write `: i32` everywhere? This looks verbose!"

Here's what I learned: MLIR's syntax reflects **compiler needs**, not human convenience. Let's break down the design decisions:

**`module { ... }`** - Top-level container for code

Every MLIR program starts with a `module`. Why? Because compilers need a **scope root** for symbol resolution. When you reference `@add` from another file, MLIR needs to know where to look. Modules provide that boundary.

**`func.func @add(...)`** - Function from the `func` dialect:
- `@add` - Function name (**@ prefix for symbols**)
- `%arg0: i32` - Arguments with **SSA names and types**
- `-> i32` - Return type

The `@` prefix isn't arbitrary. It distinguishes **symbols** (global names like functions) from **SSA values** (local values like `%result`). This matters during linking and optimization. The parser needs to know: "Is this a local value or a global reference?"

The `func.func` part might seem redundant, why not just `func`? Because **operations** are namespaced by dialect. This lets different dialects define their own operations without collisions. One dialect's `func` might mean "function definition" while another's might mean "function pointer."

**`%result = arith.addi %arg0, %arg1 : i32`** - Arithmetic from `arith` dialect:
- `%result` - **SSA value** (like a variable, but immutable)
- `arith.addi` - Integer addition operation
- `: i32` - Type constraint (32-bit integer)

This line embodies **Static Single Assignment (SSA)** form, the foundation of modern compiler IRs. In SSA:
- Every value is assigned exactly once
- Values are immutable after assignment
- Control flow merges use special Phi nodes

Why SSA? Because it makes **dataflow analysis trivial**. Want to know where `%result` is used? Follow the edges. Want to know if two computations are the same? Compare their definitions. SSA eliminates whole classes of bugs that plague mutable-variable IRs.

The `: i32` type annotation is **redundant by design**. MLIR could infer it from `arith.addi`'s signature. But explicit types make the IR self-documenting and enable better error messages. When something fails, you see types immediately, no need to trace back through inference chains.

**`return %result : i32`** - Return the value

Again, we redundantly specify the type. This isn't inefficiency, it's **verification**. MLIR can check that return types match function signatures without complex inference. Fast verification enables rapid development.

### The Mental Model Shift: IR is Not Source Code

Here's the crucial insight: **MLIR is not meant to be written by humans**. It's meant to be:
- Generated by frontends (your language's parser produces MLIR)
- Read by humans (for debugging and understanding)
- Processed by tools (parsers, verifiers, optimizers)

The syntax prioritizes **mechanical correctness** over human aesthetics. Every redundancy has a purpose: enabling local verification, simplifying parsing, or preventing ambiguity.

When you write MLIR by hand (as we'll do in tutorials), you're doing what compiler developers do: working at the IR level to understand transformations. It's not the end-user experience; it's the compiler developer experience.

### Running MLIR Transformations

```powershell
# Pretty-print (parse and print back)
mlir-opt hello.mlir

# Apply canonicalization (simplify)
mlir-opt hello.mlir --canonicalize

# Convert to LLVM dialect
mlir-opt hello.mlir --convert-func-to-llvm --convert-arith-to-llvm

# See all available passes
mlir-opt --show-dialects
mlir-opt --help | Select-String "pass"
```

## 🔬 Exploring the Tutorial Examples

The repository includes several example MLIR files in `tests/`:

### Example 1: Polynomial Syntax
```powershell
.\build\bin\tutorial-opt.exe .\tests\poly_syntax.mlir
```

This demonstrates the custom `poly` dialect defined in `lib/Dialect/Poly/`.

### Example 2: CSE (Common Subexpression Elimination)
```powershell
mlir-opt .\tests\cse.mlir --cse
```

Watch how repeated computations are eliminated.

### Example 3: Affine Loop Unrolling
```powershell
.\build\bin\tutorial-opt.exe .\tests\affine_loop_unroll.mlir --affine-full-unroll
```

See how loops are transformed.

## 📖 Understanding MLIR Tools

### mlir-opt

The main tool for running transformations:

```powershell
mlir-opt [options] input.mlir
```

**Common options:**
- `--show-dialects` - List available dialects
- `--help` - Show all passes
- `--<pass-name>` - Run a specific pass
- `--pass-pipeline="..."` - Run multiple passes
- `--mlir-print-ir-after-all` - Debug output

### mlir-translate

Converts between MLIR and other formats:

```powershell
# MLIR to LLVM IR
mlir-translate --mlir-to-llvmir input.mlir -o output.ll

# LLVM IR to MLIR
mlir-translate --import-llvm input.ll -o output.mlir
```

### tutorial-opt

Our custom tool (in `tools/tutorial-opt.cpp`):
- Like `mlir-opt` but with custom dialects registered
- Includes the `poly` and `noisy` dialects
- Includes custom transformation passes

```powershell
.\build\bin\tutorial-opt.exe --help
```

## 🔍 Development Workflow: The Reality of MLIR Development

Now that you understand the structure, let's talk about the **actual workflow** you'll use when developing MLIR code. This isn't the idealized "write-compile-run" of textbooks, it's the messy reality of compiler development.

### The Iterative Cycle

MLIR development is fundamentally iterative. You'll rarely get something right on the first try. Here's the real workflow:

1. **Write some code** (dialect definition, pass, or transformation)
2. **Try to compile** → Get TableGen errors
3. **Fix TableGen** → Get C++ compilation errors
4. **Fix C++** → Get linking errors
5. **Fix linking** → Program compiles but crashes
6. **Debug crash** → Find logic error
7. **Fix logic** → Test fails
8. **Fix test** → Discover edge case
9. **Handle edge case** → Finally works!

This isn't failure, it's normal. Compiler development involves many moving pieces: TableGen generation, C++ templates, type systems, pattern matching, IR verification. Each layer can fail independently.

### 1. Edit Code: Where to Start?

The hardest part of MLIR development is knowing **what file to edit**. Here's my mental model:

**Want to add an operation?**
1. Edit `lib/Dialect/YourDialect/YourDialectOps.td` (TableGen definition)
2. Rebuild → TableGen generates `YourDialectOps.h.inc` and `YourDialectOps.cpp.inc`
3. Include generated headers in `YourDialectOps.cpp`
4. Implement any custom methods

**Want to add a pass?**
1. Edit `lib/Transform/YourPass.td` (TableGen pass definition)
2. Edit `lib/Transform/YourPass.cpp` (C++ implementation)
3. Register pass in `tools/tutorial-opt.cpp`
4. Rebuild and test

**Want to add a custom type?**
1. Edit `lib/Dialect/YourDialect/YourDialectTypes.td` (TableGen definition)
2. Implement parsing/printing in `YourDialectTypes.cpp`
3. Update dialect to register the type

The pattern: **TableGen describes structure, C++ implements behavior**.

### 2. Rebuild: Fast Iteration is Key

The speed of your edit-compile-test cycle determines productivity. Here's how to minimize rebuild time:

```powershell
# DON'T: Rebuild everything
cmake --build build

# DO: Rebuild specific target
cd build
ninja tutorial-opt
```

**Why this matters:** Rebuilding `tutorial-opt` after changing one file takes 5-10 seconds. Rebuilding everything takes minutes. Ninja's incremental builds are smart, use them.

**Pro tip:** Keep a terminal open in the `build/` directory. Your workflow becomes:
```powershell
# Terminal 1: Edit files
nvim lib/Transform/MyPass.cpp

# Terminal 2: Rapid rebuild
ninja tutorial-opt  # Takes seconds
```

### 3. Test: Beyond Pass/Fail

Testing MLIR isn't just "does it work?" It's "does it transform correctly?"

```powershell
# Quick smoke test: Does it parse?
.\build\bin\tutorial-opt.exe .\tests\example.mlir

# Transformation test: What changed?
.\build\bin\tutorial-opt.exe .\tests\example.mlir --my-pass

# Diff test: Is it what I expected?
.\build\bin\tutorial-opt.exe .\tests\example.mlir --my-pass | FileCheck .\tests\example.mlir
```

**The FileCheck workflow:**

When developing a new pass, I don't write CHECK directives first. I:
1. Run the pass manually: `tutorial-opt input.mlir --my-pass > output.mlir`
2. Inspect `output.mlir` visually
3. If correct, copy output patterns to CHECK directives
4. If wrong, debug and repeat

This "inspect first, formalize later" approach is faster than guessing at CHECK patterns.

### 4. Debug: Print Debugging vs Real Debugging

Let's be honest: most MLIR debugging is print statements.

**Print debugging (fast, dirty):**
```cpp
void runOnOperation() override {
  llvm::errs() << "Pass started\n";
  getOperation()->dump();  // Print entire IR

  getOperation()->walk([](arith::MulIOp op) {
    llvm::errs() << "Found mul: " << op << "\n";
  });

  llvm::errs() << "Pass finished\n";
}
```

**Why this works:** MLIR operations have excellent print methods. Dumping IR at various stages shows exactly what's happening.

**Real debugging (slow, precise):**

Use VSCode with the provided configuration:
1. Set breakpoint in your pass code
2. Edit `.vscode/launch.json` to pass your test file:
   ```json
   "args": ["${workspaceFolder}/tests/example.mlir", "--my-pass"]
   ```
3. Press **F5** → GDB attaches
4. Step through code, inspect SSA values, examine the IR

**When to use each:**
- **Print debugging**: Understanding dataflow, seeing transformations, quick iteration
- **Real debugging**: Crashes, segfaults, complex logic errors, verifier failures

### The Debugging Mindset: Layers of Verification

MLIR has multiple verification layers:
1. **TableGen**: Catches structural errors at code generation
2. **C++ compiler**: Catches type errors at compile time
3. **IR verifier**: Catches semantic errors at runtime
4. **FileCheck**: Catches transformation errors in tests

When something fails, identify **which layer** failed:
- TableGen error? Check `.td` files
- C++ error? Check includes and types
- Verifier error? Check IR structure (types, operands, blocks)
- FileCheck error? Check transformation logic

Each layer has different debugging techniques. Mixing them wastes time.

### The Reality: You'll Spend More Time Understanding Than Writing

Here's what they don't tell you: in MLIR development, **reading code takes longer than writing it**. You'll spend hours:
- Reading existing dialect definitions to understand patterns
- Reading MLIR source to figure out APIs
- Reading TableGen documentation to understand syntax
- Reading test files to see how features are used

This is normal. MLIR is a large framework with many abstractions. The investment pays off, once you understand the patterns, development accelerates. But the initial learning curve is steep.

### My Workflow (Real Example)

When I add a new operation, here's my actual process:

1. **Find similar operation**: Search for existing operation that's close to what I need
2. **Copy-paste-modify**: Copy its TableGen definition, modify for my needs
3. **Build**: `ninja tutorial-opt` → TableGen errors
4. **Fix syntax**: Adjust TableGen until it compiles
5. **Write test**: Create `.mlir` file with example usage
6. **Run manually**: `tutorial-opt test.mlir` → See if it parses
7. **Add checks**: If it works, add FileCheck directives
8. **Run test suite**: `ninja check-mlir-tutorial` → Verify no regressions

Notice: I don't write perfect code. I iterate rapidly, using the compiler as a guide. This is pragmatic MLIR development.

## 👉 Common Build Issues

### "Could not find MLIR"

**Problem:** CMake can't find MLIR config files.

**Solution:**
```powershell
# Verify MLIR is installed
ls C:\msys64\clang64\lib\cmake\mlir

# If missing, reinstall
# NOTE: pacman commands require the CLANG64 terminal, not PowerShell
# In CLANG64 terminal:
pacman -S mingw-w64-clang-x86_64-mlir --force
```

**When to use which terminal:**
- **PowerShell**: Building, running tools (`mlir-opt`, `tutorial-opt`, etc.), development work
- **CLANG64 terminal**: Only for `pacman` package management commands

### "ninja: command not found"

**Problem:** Ninja not in PATH.

**Solution:**
```powershell
# Add to current session
$env:Path += ";C:\msys64\clang64\bin"

# Or use the build script which handles this
.\scripts\build-windows.ps1
```

### or-tools Download Fails

**Problem:** Network issues downloading or-tools dependency.

**Solution:**
```powershell
# Disable or-tools (only needed for one tutorial)
.\scripts\build-windows.ps1 -DisableOrTools
```

## 🔍 Common Pitfalls and Gotchas

Let me save you from the mistakes I made when starting with MLIR.

### Pitfall 1: Forgetting to Load Dialects

**The Error:**
```
error: unregistered dialect 'arith'
```

**What Happened:**
MLIR doesn't automatically load all dialects. When you use `tutorial-opt`, it only knows about dialects that were explicitly registered in `tools/tutorial-opt.cpp`.

**The Fix:**
Make sure your tool registers the dialects you need:
```cpp
registry.insert<arith::ArithDialect>();
registry.insert<func::FuncDialect>();
```

For `mlir-opt`, most standard dialects are pre-registered. For `tutorial-opt`, you control what's available.

### Pitfall 2: Type Mismatches in SSA

**The Error:**
```
error: 'arith.addi' op operand #0 must be integer-like, but got 'f32'
```

**What Happened:**
You tried to use integer addition (`addi`) on floating-point values. MLIR operations are strict about types.

**The Lesson:**
MLIR won't coerce types for you. Use `arith.addf` for floating-point, `arith.addi` for integers. This strictness prevents subtle bugs at the cost of verbosity.

### Pitfall 3: Assuming Default Passes

**The Error:**
Your optimization didn't work, and you're not sure why.

**What Happened:**
MLIR passes don't run automatically. When you write `tutorial-opt input.mlir`, it just parses and prints. You must explicitly request passes: `tutorial-opt input.mlir --cse --canonicalize`.

**The Lesson:**
MLIR is a **toolkit**, not a compiler. You compose the passes you want. This gives you control but requires knowing what's available.

### Pitfall 4: Build vs Source Directories

**The Error:**
```
FileCheck: file not found
```

**What Happened:**
You're running tests from the wrong directory. CMake generates build artifacts in `build/`, but tests reference files in the source tree.

**The Fix:**
Run tests from the build directory:
```powershell
cd build
ninja check-mlir-tutorial
```

Or use absolute paths when running tools manually.

### Pitfall 5: MSYS2 Path Confusion

**The Error:**
```
error: could not find mlir_runner_utils.dll
```

**What Happened:**
Windows uses backslashes (`\`) for paths, but MSYS2 tools expect Unix paths (`/`). PowerShell and MSYS2 bash have different working directory conventions.

**The Fix:**
Use forward slashes or escape backslashes in PowerShell:
```powershell
# Good
--shared-libs=C:/msys64/clang64/bin/mlir_runner_utils.dll

# Or
--shared-libs="C:\msys64\clang64\bin\mlir_runner_utils.dll"
```

### Design Decision: Why These Pitfalls Exist

You might ask: "Why doesn't MLIR auto-load dialects? Why not coerce types? Why not run basic optimizations by default?"

The answer is **MLIR's philosophy of explicitness**. It's designed for compiler engineers who need:
- Control over every transformation
- Visibility into what's happening
- Ability to compose custom pipelines

This makes MLIR powerful but not beginner-friendly. The tradeoff is intentional: MLIR prioritizes **correctness and control** over convenience. As you build real compilers, you'll appreciate this design.

## 🔍 Comparing to Original Tutorial

### What's Different?

**Build System:**
- Original: Bazel WORKSPACE with LLVM git repository
- This Tutorial: CMake with pre-built MSYS2 packages

**Build Time:**
- Original: 30-60 minutes (first build, includes compiling LLVM)
- This Tutorial: 2-5 minutes (uses pre-compiled LLVM)

**Platform:**
- Original: Linux/macOS focus with Bazel
- This Tutorial: Windows-native with MSYS2

**Complexity:**
- Original: Learn Bazel, manage git submodules, configure hermetic builds
- This Tutorial: Familiar CMake, package manager, standard Windows workflows

**Philosophy:**
- Original: Production-ready setup matching Google's infrastructure
- This Tutorial: Learner-friendly setup minimizing friction

### What's the Same?

**MLIR Concepts:** Everything about dialects, operations, passes, and transformations remains identical

**Code:** The actual C++ and TableGen code is the same, we just build it differently

**Examples:** All `.mlir` test files work identically

**Learning Path:** The progression through concepts matches Jeremy's pedagogical approach

### When to Use Which Approach?

**Use CMake (this tutorial) if:**
- You're learning MLIR concepts
- You're on Windows
- You want fast iteration
- You're prototyping or experimenting

**Use Bazel (original tutorial) if:**
- You're building production compilers
- You need hermetic, reproducible builds
- You're in a monorepo environment
- You're contributing to Google's MLIR projects

Both approaches teach the same MLIR concepts. The build system is infrastructure, choose what lets you focus on learning.

## 👉 Next Steps

Now that you have MLIR building and running, you're ready to:

1. **[Tutorial 02: Running and Testing a Lowering](02-running-and-testing.md)** - Learn about lit/FileCheck testing
2. **[Tutorial 03: Writing Your First Pass](03-writing-first-pass.md)** - Create custom transformations
3. **Explore the code** - Look at `lib/Dialect/Poly/` to see a complete dialect

## Key Takeaways: What You've Really Learned

Beyond the mechanics of installing packages and running commands, here's what you should internalize from this tutorial:

### 1. MLIR is a Philosophy, Not Just a Framework

MLIR isn't "LLVM but with extra features." It's a **fundamental rethinking** of compiler architecture. The core insight: splitting compilation into many small, focused transformations across multiple intermediate representations is more powerful than one giant transformation across a single IR.

When you encounter a compilation problem, don't think: "How do I map my language to LLVM?" Think: "What intermediate representations would make my optimizations natural?"

### 2. Dialects Enable Compositional Compiler Design

Traditional compilers are monolithic: one frontend, one IR, one backend. MLIR compilers are compositional: mix dialects, chain passes, reuse components. This fundamentally changes how we build compilers.

You're not building "a TensorFlow compiler" or "a quantum compiler." You're building a **pipeline of transformations** through dialects, many of which already exist and work out of the box.

### 3. Windows Development is First-Class (With the Right Tools)

For too long, Windows was treated as a second-class platform for compiler development. MSYS2 + CMake changes that. You get Unix-like tooling on Windows without abandoning the Windows ecosystem. This tutorial proves it's viable.

### 4. Build Systems Are Infrastructure, Not Learning Goals

The original tutorial used Bazel because that's what production MLIR projects at Google use. This tutorial uses CMake because that's what gets you writing code faster on Windows. Neither choice affects your understanding of MLIR concepts.

Don't confuse infrastructure with understanding. The build system is scaffolding. The concepts—dialects, passes, SSA, transformations—are the building.

### 5. SSA Form is Non-Negotiable

Every modern compiler IR uses Static Single Assignment. Understanding why—and what it enables—is crucial. MLIR's syntax might look verbose, but that verbosity enables the mechanical verification and optimization that makes MLIR powerful.

### 6. Explicitness Over Magic

MLIR doesn't auto-load dialects. It doesn't coerce types. It doesn't run passes automatically. This explicit design feels tedious at first, but it prevents entire classes of bugs. In production compilers, magic breaks in surprising ways. Explicitness scales.

### 7. The Learning Curve is Real, But Worth It

If you found this tutorial challenging, that's normal. MLIR is professional-grade compiler infrastructure. It assumes you understand SSA, type systems, and compiler passes. But here's the promise: **every concept you learn compounds**.

Understanding dialects helps you understand passes. Understanding passes helps you understand pattern rewriting. Understanding pattern rewriting helps you build custom transformations. The early investment pays exponential dividends.

## Additional Resources

- **MLIR Documentation:** [mlir.llvm.org](https://mlir.llvm.org/)
- **Toy Tutorial:** [mlir.llvm.org/docs/Tutorials/Toy/](https://mlir.llvm.org/docs/Tutorials/Toy/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/08/10/mlir-getting-started/)
- **MLIR Discourse:** [llvm.discourse.group/c/mlir](https://llvm.discourse.group/c/mlir/)

---

**Next:** [Tutorial 02: Running and Testing a Lowering →](02-running-and-testing.md)
