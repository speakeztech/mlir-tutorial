# Tutorial 04: Using Tablegen for Passes

**Original Article:** [MLIR — Using Tablegen for Passes](https://jeremykun.com/2023/08/10/mlir-using-tablegen-for-passes/) by Jeremy Kun

**Windows Adaptation:** Focus on TableGen integration with CMake instead of Bazel.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 The "I'm Not Smart Enough" Con

Here's an uncomfortable truth about software development: **boilerplate exists because we're not smart enough to remember all the details**.

When Jeremy Kun wrote about TableGen, he opened with this disarming confession: he's not clever enough to correctly implement all the required methods for MLIR passes from memory. He forgets which virtual methods need overriding. He misspells function names. He gets parameter types wrong.

This isn't weakness—it's **honesty about how humans actually work**.

And it leads to a crucial realization: if you're going to forget things anyway, you might as well have a tool generate the boilerplate for you. That tool, in MLIR, is **TableGen**.

But here's where things get interesting (and where I initially stumbled): TableGen isn't the magical abstraction layer it first appears to be. It's something both simpler and more powerful—a **transparent code generator** that trades "hiding complexity" for "making repetition mechanical".

## 💡 What You'll Learn

- Why **boilerplate matters** and how TableGen addresses it
- The **mental model shift** from "abstraction" to "transparent generation"
- Writing **`.td` files** to define passes declaratively
- Integrating TableGen with **CMake** builds (Windows-native approach)
- Understanding **generated code** (and why reading it is essential)
- The **philosophy** of white-box code generation
- Real-world tradeoffs and when TableGen helps vs. frustrates

## 📖 The Problem TableGen Solves

Let me show you the problem before we discuss the solution.

### Every MLIR Pass Needs This Boilerplate

```cpp
// A minimal pass implementation - look at all this ceremony!
struct MyPass : public PassWrapper<MyPass, OperationPass<>> {
  // Command-line name
  StringRef getArgument() const override {
    return "my-pass";
  }

  // Help text
  StringRef getDescription() const override {
    return "Does something useful";
  }

  // Which dialects does this pass need loaded?
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<arith::ArithDialect>();
    registry.insert<func::FuncDialect>();
  }

  // The actual transformation
  void runOnOperation() override {
    // Your logic here - maybe 10 lines
  }
};

// Manual registration ceremony
void registerMyPass() {
  PassRegistration<MyPass>();
}
```

Notice the pattern? **Out of ~20 lines, maybe 10 contain actual transformation logic**. The rest is infrastructure—critical infrastructure that must be exactly right, but also mechanical and repetitive.

### The Scaling Problem

Now imagine you're building a real compiler with 50 passes:
- 50 `getArgument()` implementations (each must be unique)
- 50 `getDescription()` implementations
- 50 dependency lists
- 50 registration functions
- Thousands of lines of boilerplate

And every time you add a new pass, you copy-paste-modify this ceremony, hoping you didn't introduce a subtle bug (like forgetting to register a dependent dialect, which fails at runtime with cryptic errors).

**This is where TableGen enters.**

## 📖 What is TableGen?

**TableGen** is a domain-specific language and code generator used throughout LLVM/MLIR. Instead of writing repetitive C++ boilerplate, you write a declarative `.td` file and let `mlir-tblgen` generate the code.

But let me be clear about something crucial—something that took me time to understand:

### The Critical Mental Model Shift

❌ **Wrong:** "TableGen is an abstraction layer I don't need to understand"

✅ **Right:** "TableGen is transparent code generation. I should read the generated `.h.inc` files to understand what it creates."

This distinction matters enormously.

### Black-Box vs White-Box Code Generation

**Black-box abstraction** (what I initially thought TableGen was):
- You write high-level specs
- Magic happens
- Usable code appears
- You never look at the generated output
- Errors are explained in terms of your input
- Example: A good DSL, a well-designed code generator

**White-box code generation** (what TableGen actually is):
- You write declarative definitions
- Predictable generation happens (you can trace it)
- Generated code is meant to be read
- You often inspect the output to understand behavior
- Errors may come from generated code, requiring you to understand the generation pattern
- Example: TableGen, C preprocessor macros

### Why This Distinction Matters

When you treat TableGen as a black box, you get frustrated. The error messages reference generated code you've never seen. The contracts between your code and the base classes are implicit. You're left guessing what methods you need to implement.

When you treat TableGen as a white-box generator, you gain clarity. You read the `.h.inc` file once, understand the pattern, and know exactly what's being generated. The tool becomes predictable rather than magical.

This tutorial will show you both: the declarative `.td` syntax (what you write) and the generated C++ code (what you need to understand).

### What TableGen Generates for Passes

For each pass definition in a `.td` file, TableGen generates:

1. **Factory functions** - `std::unique_ptr<Pass> createMyPass()`
2. **Base class with CRTP** - Pre-implemented `getArgument()`, `getDescription()`, `getDependentDialects()`
3. **Registration helpers** - Functions to register passes with the pass manager
4. **Option/statistic members** - If you declare them in the `.td` file

The generated code uses the Curiously Recurring Template Pattern (CRTP), which allows the base class to know about your derived class at compile time without virtual function overhead.

## 🔬 The Transformation: Before and After

Let's see the same pass implemented manually versus with TableGen.

### Before TableGen: Manual Implementation

```cpp
// Manual pass implementation - notice the repetitive structure
struct AffineFullUnroll : public PassWrapper<AffineFullUnroll, OperationPass<>> {
  StringRef getArgument() const override { return "affine-full-unroll"; }
  StringRef getDescription() const override { return "Fully unroll affine loops"; }

  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<affine::AffineDialect>();
  }

  void runOnOperation() override {
    // Actual pass logic here
  }
};

// Manual registration
void registerAffineFullUnrollPass() {
  PassRegistration<AffineFullUnroll>();
}
```

### After TableGen: Declarative + Generated

With TableGen, the same pass splits into two parts: a declarative specification and a minimal implementation.

**File: `lib/Transform/Affine/Passes.td`**

```tablegen
include "mlir/Pass/PassBase.td"

def AffineFullUnroll : Pass<"affine-full-unroll"> {
  let summary = "Fully unroll all affine loops";

  let description = [{
    This pass completely unrolls all affine.for loops by generating
    a copy of the loop body for each iteration.
  }];

  let dependentDialects = ["mlir::affine::AffineDialect"];
}
```

**File: `lib/Transform/Affine/AffineFullUnroll.cpp`**

```cpp
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Pass/Pass.h"

namespace mlir {
namespace tutorial {

#define GEN_PASS_DEF_AFFINEFULLUNROLL
#include "Transform/Affine/Passes.h.inc"

struct AffineFullUnroll : impl::AffineFullUnrollBase<AffineFullUnroll> {
  using AffineFullUnrollBase::AffineFullUnrollBase;

  void runOnOperation() override {
    // Only the transformation logic - boilerplate is generated
    getOperation()->walk([&](affine::AffineForOp op) {
      // Unroll logic here
    });
  }
};

} // namespace tutorial
} // namespace mlir
```

### What Changed?

The metadata moved from C++ to the `.td` file:
- Pass name: now in `Pass<"affine-full-unroll">`
- Description: now in `let summary` and `let description`
- Dependencies: now in `let dependentDialects`

The C++ implementation only contains the unique logic: `runOnOperation()`. Everything mechanical is generated.

**Trade-off:** You now have two files to maintain instead of one. But for a codebase with dozens of passes, this declarative approach scales better and reduces errors.

## 🔬 TableGen Syntax for Passes

### Basic Pass Definition

```tablegen
// Import base definitions
include "mlir/Pass/PassBase.td"

def MyPass : Pass<"my-pass-name"> {
  let summary = "Short one-line description";
  let description = [{
    Longer description with details.
    Can span multiple lines.
  }];
}
```

### Specifying Dependent Dialects

```tablegen
def MyPass : Pass<"my-pass"> {
  let summary = "...";
  let dependentDialects = [
    "mlir::arith::ArithDialect",
    "mlir::func::FuncDialect"
  ];
}
```

This ensures dialects are loaded before the pass runs.

### Targeting Specific Operations

```tablegen
// Pass runs only on func::FuncOp
def MyFuncPass : Pass<"my-pass", "func::FuncOp"> {
  let summary = "...";
}

// Pass runs on entire module (default)
def MyModulePass : Pass<"my-pass"> {
  let summary = "...";
}
```

### Pass Options (Command-Line Arguments)

```tablegen
def MyPass : Pass<"my-pass"> {
  let summary = "...";

  let options = [
    Option<"threshold", "threshold", "int64_t", /*default=*/"10",
           "Threshold value for optimization">,

    ListOption<"targetOps", "target-ops", "std::string",
               "List of operation names to target">
  ];
}
```

Usage:

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
.\build\bin\tutorial-opt.exe input.mlir --my-pass="threshold=20 target-ops=arith.addi,arith.muli"
```

### Pass Statistics

```tablegen
def MyPass : Pass<"my-pass"> {
  let summary = "...";

  let statistics = [
    Statistic<"numOpsReplaced", "num-ops-replaced",
              "Number of operations replaced">
  ];
}
```

In C++:
```cpp
void runOnOperation() override {
  // ...
  ++numOpsReplaced;  // Auto-generated statistic
}
```

## 👉 CMake Integration

### Step 1: Create Passes.td File

**`lib/Transform/Affine/Passes.td`:**

```tablegen
include "mlir/Pass/PassBase.td"

def AffineFullUnroll : Pass<"affine-full-unroll"> {
  let summary = "Fully unroll all affine loops";
  let dependentDialects = ["mlir::affine::AffineDialect"];
}

def AffineFullUnrollPatternRewrite : Pass<"affine-full-unroll-pattern-rewrite"> {
  let summary = "Fully unroll affine loops using pattern rewriting";
  let dependentDialects = ["mlir::affine::AffineDialect"];
}
```

### Step 2: Add TableGen Target to CMakeLists.txt

**`lib/Transform/Affine/CMakeLists.txt`:**

```cmake
# Generate header from TableGen
set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Affine)
mlir_tablegen(Passes.capi.h.inc -gen-pass-capi-header --prefix Affine)
mlir_tablegen(Passes.capi.cpp.inc -gen-pass-capi-impl --prefix Affine)
add_public_tablegen_target(MLIRAffinePassIncGen)

# Build the library
add_mlir_library(MLIRAffineFullUnrollPasses
  AffineFullUnroll.cpp
  AffineFullUnrollPatternRewrite.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/lib/Transform/Affine

  DEPENDS
  MLIRAffinePassIncGen

  LINK_LIBS PUBLIC
  MLIRAffineDialect
  MLIRPass
  MLIRTransforms
)
```

### Step 3: Build

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
cd build
ninja MLIRAffinePassIncGen      # Generate headers
ninja MLIRAffineFullUnrollPasses  # Build library
```

### What Gets Generated

**`build/lib/Transform/Affine/Passes.h.inc`:**

This file contains three guarded sections.

## Understanding Generated Code

### Section 1: GEN_PASS_DECL - Factory Functions

```cpp
#define GEN_PASS_DECL_AFFINEFULLUNROLL
#include "Passes.h.inc"
```

Generates:
```cpp
std::unique_ptr<::mlir::Pass> createAffineFullUnroll();
```

### Section 2: GEN_PASS_DEF - Base Class

```cpp
#define GEN_PASS_DEF_AFFINEFULLUNROLL
#include "Passes.h.inc"
```

Generates:
```cpp
namespace impl {
  template <typename DerivedT>
  class AffineFullUnrollBase : public ::mlir::OperationPass<> {
  public:
    using Base = AffineFullUnrollBase;

    ::llvm::StringRef getArgument() const override { return "affine-full-unroll"; }
    ::llvm::StringRef getDescription() const override { return "Fully unroll all affine loops"; }

    void getDependentDialects(::mlir::DialectRegistry &registry) const override {
      registry.insert<::mlir::affine::AffineDialect>();
    }

  protected:
    AffineFullUnrollBase() = default;
  };
} // namespace impl
```

### Section 3: GEN_PASS_REGISTRATION - Registration

```cpp
#define GEN_PASS_REGISTRATION
#include "Passes.h.inc"
```

Generates:
```cpp
inline void registerAffinePasses() {
  registerAffineFullUnroll();
  registerAffineFullUnrollPatternRewrite();
}
```

## Using the Generated Code

### In Your Pass Implementation

**`lib/Transform/Affine/AffineFullUnroll.cpp`:**

```cpp
#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Pass/Pass.h"

namespace mlir {
namespace tutorial {

// Include factory function declaration
#define GEN_PASS_DECL_AFFINEFULLUNROLL
// Include base class definition
#define GEN_PASS_DEF_AFFINEFULLUNROLL
#include "Transform/Affine/Passes.h.inc"

// Implement pass by inheriting from generated base
struct AffineFullUnroll : impl::AffineFullUnrollBase<AffineFullUnroll> {
  using AffineFullUnrollBase::AffineFullUnrollBase;

  void runOnOperation() override {
    // Your transformation logic
  }
};

} // namespace tutorial
} // namespace mlir
```

### In Your Header File

**`lib/Transform/Affine/Passes.h`:**

```cpp
#ifndef LIB_TRANSFORM_AFFINE_PASSES_H
#define LIB_TRANSFORM_AFFINE_PASSES_H

#include "mlir/Pass/Pass.h"

namespace mlir {
namespace tutorial {

// Declare factory functions
#define GEN_PASS_DECL
#include "Transform/Affine/Passes.h.inc"

// Declare registration function
#define GEN_PASS_REGISTRATION
#include "Transform/Affine/Passes.h.inc"

} // namespace tutorial
} // namespace mlir

#endif
```

### Registering with tutorial-opt

**`tools/tutorial-opt.cpp`:**

```cpp
#include "Transform/Affine/Passes.h"
#include "Transform/Arith/Passes.h"

int main(int argc, char **argv) {
  // Register all tutorial passes
  mlir::tutorial::registerAffinePasses();
  mlir::tutorial::registerArithPasses();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Tutorial Pass Driver\n"));
}
```

## Advanced TableGen Features

### Pass with Options

**Passes.td:**
```tablegen
def MyOptimization : Pass<"my-opt"> {
  let summary = "My optimization pass";

  let options = [
    Option<"aggressiveness", "aggr", "int", /*default=*/"1",
           "Optimization aggressiveness (0-3)">,

    Option<"enableDebug", "debug", "bool", /*default=*/"false",
           "Enable debug output">
  ];
}
```

**In C++:**
```cpp
struct MyOptimization : impl::MyOptimizationBase<MyOptimization> {
  using MyOptimizationBase::MyOptimizationBase;

  void runOnOperation() override {
    if (enableDebug) {  // Access option
      llvm::errs() << "Aggressiveness: " << aggressiveness << "\n";
    }
    // ...
  }
};
```

**Usage:**

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
.\build\bin\tutorial-opt.exe input.mlir --my-opt="aggr=3 debug=true"
```

### Pass with Statistics

**Passes.td:**
```tablegen
def CSE : Pass<"my-cse"> {
  let summary = "Common subexpression elimination";

  let statistics = [
    Statistic<"numCSE", "num-cse",
              "Number of operations eliminated">,
    Statistic<"numFolded", "num-folded",
              "Number of operations folded">
  ];
}
```

**In C++:**
```cpp
void runOnOperation() override {
  getOperation()->walk([&](Operation *op) {
    if (/* can eliminate */) {
      ++numCSE;
      op->erase();
    }
  });
}
```

**Output:**
```
===-------------------------------------------------------------------------===
                         ... Statistics Collected ...
===-------------------------------------------------------------------------===

1 my-cse - Number of operations eliminated
5 my-cse - Number of operations folded
```

## The Generation Pattern: Understanding the Mechanism

TableGen uses a clever pattern with C preprocessor macros to give you control over what gets generated. Understanding this pattern is essential for effective use.

### The Three-Section Generated File

When `mlir-tblgen` processes your `.td` file, it creates a single `.h.inc` file with three guarded sections:

```cpp
// Section 1: Factory function declarations
#ifdef GEN_PASS_DECL_AFFINEFULLUNROLL
std::unique_ptr<::mlir::Pass> createAffineFullUnroll();
#undef GEN_PASS_DECL_AFFINEFULLUNROLL
#endif

// Section 2: Base class definition
#ifdef GEN_PASS_DEF_AFFINEFULLUNROLL
namespace impl {
  template <typename DerivedT>
  class AffineFullUnrollBase : public ::mlir::OperationPass<> {
    // Generated methods here
  };
}
#undef GEN_PASS_DEF_AFFINEFULLUNROLL
#endif

// Section 3: Registration functions
#ifdef GEN_PASS_REGISTRATION
inline void registerAffinePasses() {
  // Registration code here
}
#undef GEN_PASS_REGISTRATION
#endif
```

### Why This Pattern?

This approach lets you include the same `.h.inc` file multiple times in different contexts:

1. **In your header** (`Passes.h`): Include with `GEN_PASS_DECL` to get factory declarations
2. **In your implementation** (`AffineFullUnroll.cpp`): Include with `GEN_PASS_DEF` to get the base class
3. **In your registration** (`InitAllPasses.cpp`): Include with `GEN_PASS_REGISTRATION` to get registration helpers

Each `#define` before `#include` selectively enables one section.

### The CRTP Base Class

The generated base class uses CRTP (Curiously Recurring Template Pattern):

```cpp
template <typename DerivedT>
class AffineFullUnrollBase : public ::mlir::OperationPass<> {
  // ...
};
```

This allows the base class to call methods on your derived class at compile time without virtual dispatch overhead. When you write:

```cpp
struct AffineFullUnroll : impl::AffineFullUnrollBase<AffineFullUnroll> {
  // Your implementation
};
```

The base class knows about `AffineFullUnroll` as `DerivedT`, enabling static polymorphism.

## 👉 CMake Integration: The Windows-Native Build

On Windows with CMake, TableGen integration is more straightforward than on Linux with Bazel. Let's see how it works.

## Generating Documentation

TableGen can auto-generate markdown documentation:

```cmake
# In CMakeLists.txt
mlir_tablegen(Passes.md -gen-pass-doc)
```

Creates:
```markdown
### `--affine-full-unroll` (AffineFullUnroll)

Fully unroll all affine loops

This pass completely unrolls all affine.for loops by generating
a copy of the loop body for each iteration.
```

## Debugging TableGen

### View Generated Code

```powershell
# Check what was generated
cat .\build\lib\Transform\Affine\Passes.h.inc
```

### TableGen Errors

**Common error:**
```
error: couldn't locate file 'mlir/Pass/PassBase.td'
```

**Solution:**
Ensure CMakeLists.txt includes:
```cmake
include_directories(${MLIR_INCLUDE_DIRS})
```

### Compilation Errors After TableGen

If you get undefined references, check:
1. Did you `#define GEN_PASS_DEF_YOURPASS`?
2. Did you inherit from `impl::YourPassBase<YourPass>`?
3. Did you implement `runOnOperation()`?

## Practical Wisdom: When TableGen Helps and When It Frustrates

TableGen is a tool with clear strengths and limitations. Understanding both helps you use it effectively.

### When TableGen Excels

1. **Consistent metadata across many passes** - When you have 20+ passes, declaring them consistently in `.td` files prevents typos and ensures uniform documentation

2. **Pass options and statistics** - The declarative syntax for command-line options is cleaner than manually implementing them with `PassOptions<>`

3. **Generated documentation** - TableGen can generate markdown docs automatically from your pass descriptions

4. **Refactoring** - When the pass base class interface changes (rare, but happens), you update the TableGen backend once rather than manually updating dozens of passes

### When TableGen Frustrates

1. **Learning curve** - You need to learn both TableGen syntax and understand the generated code patterns

2. **Debugging challenges** - Error messages may reference generated code, requiring you to trace back to your `.td` definitions

3. **Limited expressiveness** - You can only generate what the TableGen backends support; custom boilerplate may still require manual code

4. **Build complexity** - Adding another code generation step means more build dependencies and longer builds (though this is minimal on Windows with Ninja)

### The Honest Assessment

TableGen is not a silver bullet. It trades one form of complexity (repetitive boilerplate) for another (code generation machinery). For small projects with 2-3 passes, manual implementation might be simpler. For larger projects with dozens of passes, TableGen pays off by ensuring consistency and reducing maintenance burden.

The key insight: **TableGen doesn't eliminate complexity; it centralizes and mechanizes it**.

## Best Practices for Using TableGen

These practices come from real experience building MLIR-based compilers.

### 1. Always Inspect Generated Code

When you first use TableGen for a pass, immediately look at the generated `.h.inc` file:

```powershell
cat .\build\lib\Transform\Affine\Passes.h.inc | less
```

This demystifies what's happening and helps you debug compilation errors. After seeing the pattern once, you'll understand how all TableGen passes work.

### 2. Use TableGen for Mechanical Boilerplate Only

Don't try to generate complex logic. Use `.td` files for:
- ✅ Pass metadata (name, description, dependencies)
- ✅ Command-line options and statistics
- ✅ Standard lifecycle methods
- ❌ Transformation logic (write in C++)
- ❌ Complex initialization or cleanup code

### 3. Organize Pass Definitions Consistently

Group related passes in the same `.td` file:

```tablegen
// lib/Transform/Affine/Passes.td
include "mlir/Pass/PassBase.td"

def AffineFullUnroll : Pass<"affine-full-unroll"> { /* ... */ }
def AffineLoopFusion : Pass<"affine-loop-fusion"> { /* ... */ }
def AffineVectorize : Pass<"affine-vectorize"> { /* ... */ }
```

This keeps related passes together and generates one `.h.inc` file with all their definitions.

### 4. Follow the Namespace Pattern

Establish a consistent pattern for your namespace and generated code:

```cpp
namespace mlir {
namespace tutorial {

#define GEN_PASS_DEF_MYPASS
#include "Transform/Affine/Passes.h.inc"

struct MyPass : impl::MyPassBase<MyPass> {
  using MyPassBase::MyPassBase;
  void runOnOperation() override { /* ... */ }
};

} // namespace tutorial
} // namespace mlir
```

This pattern appears throughout MLIR and makes code predictable.

### 5. Develop Incrementally

When creating a new pass:

1. Start with minimal `.td` definition (name and summary only)
2. Add CMake integration and generate the `.h.inc` file
3. Implement the minimal C++ pass structure
4. Verify it compiles and registers correctly
5. Add options, statistics, and dependencies as needed

This incremental approach catches errors early when they're easiest to fix.

## The Design Philosophy: Why TableGen Works This Way

Understanding why TableGen uses its particular approach helps you use it more effectively. The design reflects specific choices about what problems to solve and what complexity to accept.

### Historical Context: LLVM's Code Generation Problem

TableGen originated in LLVM's backend code generation, where a single compiler needed to support dozens of target architectures (x86, ARM, RISC-V, etc.). Each target had:
- Hundreds of instruction definitions
- Different register classes
- Complex instruction selection patterns
- Target-specific calling conventions

Manual C++ for all this would be unmaintainable. But a fully generic runtime system would be too slow for production compilers.

TableGen's solution: **generate specialized C++ at build time** from declarative specifications. This gives you:
- Maintainability of declarative specs
- Performance of specialized C++ code
- Compile-time error checking

### The "Record" Abstraction

At its core, TableGen is a database of records with fields. The `.td` syntax lets you define records:

```tablegen
def MyPass : Pass<"my-pass"> {
  let summary = "My transformation";
  let dependentDialects = ["mlir::arith::ArithDialect"];
}
```

This creates a record named `MyPass` of type `Pass`, with fields `summary` and `dependentDialects`. The `mlir-tblgen` tool then queries this database and generates C++ based on what it finds.

### Why Not Just Use C++ Directly?

You might wonder: why not define passes directly in C++ using some registration macro system?

```cpp
// Hypothetical alternative
REGISTER_PASS("my-pass", MyPass)
  .withSummary("My transformation")
  .withDialect<arith::ArithDialect>();
```

This would avoid code generation entirely. But it has downsides:
1. **Limited metaprogramming** - C++ macros and templates can only do so much
2. **No cross-file analysis** - Can't generate global registries spanning multiple files easily
3. **Runtime overhead** - Registration happens at program startup rather than compile time
4. **No documentation generation** - Can't extract structured information to create docs

TableGen's separate compilation step enables capabilities that pure C++ approaches struggle with.

### The Preprocessor Guard Pattern: Why Three Sections?

The three-section pattern (`_DECL`, `_DEF`, `_REGISTRATION`) solves a specific problem: you need the same information in different forms in different places.

Consider pass registration. Your header file needs forward declarations:
```cpp
std::unique_ptr<Pass> createMyPass();
```

Your implementation needs the base class definition:
```cpp
class MyPassBase : public OperationPass<> { /* ... */ };
```

Your initialization code needs the registration function:
```cpp
void registerMyPass() { /* ... */ }
```

Rather than generate three separate files (increasing build complexity), TableGen generates one file with three guarded sections. Each consumer includes the same file but activates different sections.

This pattern appears throughout LLVM/MLIR's TableGen usage—once you recognize it, you'll see it everywhere.

### Transparent vs. Opaque Generation

Many code generators aim for complete abstraction—you never see the generated code. TableGen takes the opposite approach: the generated code is meant to be read.

This choice has trade-offs:

**Benefits:**
- Easier debugging (read the generated code to understand errors)
- Educational (you learn MLIR patterns by reading generated examples)
- Transparent (no "magic" to worry about)
- Flexible (you can mix generated and hand-written code)

**Costs:**
- Steeper learning curve (must understand both `.td` syntax and generated patterns)
- More exposed to implementation changes (generated code format may evolve)
- Less "automated" feeling (you're more aware of the machinery)

The MLIR team chose transparency over opacity. This tutorial follows that philosophy—hence the emphasis on reading generated `.h.inc` files.

## Common Pitfalls and How to Avoid Them

### Pitfall 1: Treating TableGen as Black-Box Magic

**Problem:** You write `.td` definitions, get compilation errors, and have no idea why.

**Solution:** Read the generated `.h.inc` file. Understand the pattern once, and all TableGen passes become clear.

### Pitfall 2: Forgetting to `#define` Before `#include`

**Problem:** You include `Passes.h.inc` but get linking errors about undefined methods.

**Solution:** Remember the preprocessor pattern:
```cpp
#define GEN_PASS_DEF_MYPASS
#include "Passes.h.inc"
```

The `#define` must come before the `#include`.

### Pitfall 3: Mismatched Pass Names

**Problem:** Your `.td` file defines `MyPass`, but the generated base class is `MypassBase` (wrong capitalization).

**Solution:** TableGen converts pass names to CamelCase for generated identifiers. If you define `def my_special_pass`, the generated base is `MySpecialPassBase`.

### Pitfall 4: Missing CMake Dependencies

**Problem:** CMake tries to compile your pass before the `.h.inc` file is generated.

**Solution:** Add the TableGen target to your library's dependencies:
```cmake
add_mlir_library(MyPasses
  MyPass.cpp
  DEPENDS
  MLIRMyPassIncGen  # This ensures generation happens first
)
```

## Key Takeaways

This tutorial covered TableGen from both philosophical and practical perspectives. Here are the essential points:

✅ **TableGen is white-box code generation**, not abstraction—you should understand the generated code

✅ **Boilerplate exists because humans forget details**—TableGen mechanizes what we'd otherwise copy-paste-modify

✅ **`.td` files declare pass metadata**—name, description, options, statistics, dependencies

✅ **Generated code uses CRTP** for efficient base class implementation without virtual overhead

✅ **Three preprocessor guards** control what gets included: `_DECL`, `_DEF`, `_REGISTRATION`

✅ **CMake integration is straightforward** on Windows—`mlir_tablegen()` handles code generation

✅ **TableGen trades complexity types**—less boilerplate, but more code generation machinery

✅ **Always read generated `.h.inc` files** when learning—this demystifies the process

## The Learning Journey: From Confusion to Clarity

When you first encounter TableGen, the experience can be disorienting. You're learning MLIR (already complex), and now there's this additional layer of code generation with its own syntax and conventions.

This is normal. Here's what the learning curve typically looks like:

### Stage 1: Confusion (Days 1-2)

You copy-paste `.td` examples, get mysterious compilation errors, and wonder why anyone thought code generation was a good idea. The error messages mention files that don't exist in your source tree.

**What helps:** Stop and read one generated `.h.inc` file completely. Just one. Pick a simple pass and trace through: what you wrote in the `.td`, what got generated, how your C++ code uses it.

### Stage 2: Pattern Recognition (Days 3-5)

You start recognizing the three-section pattern. You understand that `GEN_PASS_DEF_MYPASS` needs to be defined before including the `.h.inc` file. You can write a simple pass without consulting documentation.

**What helps:** Implement 2-3 passes from scratch. Not copy-pasting—actually typing out the `.td` definition, CMake integration, and C++ implementation. Muscle memory matters.

### Stage 3: Competence (Week 2)

TableGen becomes mundane. You know the syntax for options and statistics. You understand when to use TableGen and when manual C++ is simpler. You can debug TableGen-related compilation errors efficiently.

**What helps:** Read MLIR's built-in `.td` files (in `C:\msys64\mingw64\include\mlir\`). See how the professionals structure complex pass definitions.

### Stage 4: Appreciation (Week 3+)

You encounter a scenario where you need to add a new field to 20 pass definitions. In the manual world, this would mean editing 20 C++ files carefully. With TableGen, you add one field to the base class generator and update 20 `.td` files mechanically.

This is when TableGen's value becomes visceral. It's not about eliminating complexity—it's about making certain kinds of changes safe and systematic.

## Windows-Specific Considerations

This tutorial emphasizes Windows development with CMake and MSYS2. A few Windows-specific notes about TableGen:

### Path Handling

CMake on Windows handles TableGen paths correctly, but be aware:
- Generated `.h.inc` files appear in `build\lib\Transform\...` (Windows path separators)
- Include paths in CMake use forward slashes even on Windows (CMake normalizes them)
- When viewing generated files, use PowerShell or a Unix-aware tool like `less`

### Build Performance

TableGen generation is fast (milliseconds), but on Windows with many small files, file system overhead can accumulate. Use Ninja (not Visual Studio MSBuild) for parallel builds:

```powershell
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
ninja -j8  # Parallel build with 8 jobs
```

### IDE Integration

VSCode on Windows can index generated `.h.inc` files if you configure the C++ extension correctly:

```json
{
  "C_Cpp.default.compileCommands": "${workspaceFolder}/build/compile_commands.json"
}
```

This lets IntelliSense understand the generated code, making development more pleasant.

## Closing Thoughts

TableGen represents a specific philosophy in compiler engineering: **make repetitive tasks mechanical rather than manual**. It doesn't eliminate complexity, but it centralizes it in a way that scales.

The key to using TableGen effectively is understanding it as white-box code generation. Read the generated code. Understand the patterns. Treat the `.td` files as structured input to a predictable generator, not as magic incantations.

Once you internalize this mental model, TableGen transforms from a mysterious obstacle into a practical tool. You'll start using it not because you have to, but because it makes certain tasks genuinely easier.

The next tutorial moves beyond passes to defining custom dialects—where TableGen becomes even more valuable.

## Next Steps

1. **[Tutorial 05: Defining a New Dialect](05-defining-dialect.md)** - Create custom MLIR dialects using TableGen
2. **Explore MLIR's built-in pass definitions** - Read `C:\msys64\mingw64\include\mlir\Dialect\*\Passes.td`
3. **Experiment with pass options** - Add command-line arguments to your passes
4. **Read PassBase.td** - Understanding the base definitions helps decode generated code

## Additional Resources

- **TableGen Language Reference:** [llvm.org/docs/TableGen/](https://llvm.org/docs/TableGen/)
- **MLIR Pass Infrastructure:** [mlir.llvm.org/docs/PassManagement/](https://mlir.llvm.org/docs/PassManagement/)
- **PassBase.td Source:** `C:\msys64\mingw64\include\mlir\Pass\PassBase.td`
- **Original Tutorial:** [jeremykun.com](https://jeremykun.com/2023/08/10/mlir-using-tablegen-for-passes/)
- **LLVM TableGen Backend Development:** For those interested in how TableGen itself works

---

**Previous:** [← Tutorial 03: Writing Your First Pass](03-writing-first-pass.md)
**Next:** [Tutorial 05: Defining a New Dialect →](05-defining-dialect.md)
