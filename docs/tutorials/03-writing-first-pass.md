# Tutorial 03: Writing Your First Pass

**Original Article:** [MLIR — Writing Our First Pass](https://jeremykun.com/2023/08/10/mlir-writing-our-first-pass/) by Jeremy Kun

**Windows Adaptation:** Focus on C++ pass implementation with CMake build integration.

---

## 📖 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Advanced features and detailed analysis
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 What You'll Learn

- What an MLIR **pass** is and how it transforms IR
- Implementing a pass by **walking** the IR tree
- Using **pattern matching** on operations
- **Registering** passes with MLIR
- Building and testing passes on Windows

## 📖 What is a Pass? (And Why This is the Heart of MLIR)

If Tutorial 01 was about infrastructure and Tutorial 02 was about testing, Tutorial 03 is where you **become an MLIR developer**. Writing passes is the main work in MLIR. It's where optimizations happen, where lowering happens, where your compiler's intelligence lives.

A **pass** is a transformation that:
1. Reads MLIR IR as input
2. Analyzes or modifies it
3. Produces transformed IR as output

But this simple definition hides a crucial insight: **passes are how MLIR achieves composability**. Instead of one monolithic "compile" function, you build a pipeline of small, focused passes. Each pass does one thing well.

###The Philosophy: Small, Composable Transformations

Traditional compilers often have giant "optimizer" functions:

```cpp
void optimize(Program* program) {
  // 5000 lines of optimization logic
  // Inline functions
  // Eliminate dead code
  // Constant fold
  // Common subexpression elimination
  // Loop optimizations
  // ... and 50 more things
}
```

This approach has problems:
- **Testing**: How do you test optimization #37 without running all 50?
- **Debugging**: When output is wrong, which optimization broke?
- **Reuse**: Can't reuse "just the inliner" in another compiler
- **Ordering**: Dependencies between optimizations are implicit and fragile

MLIR's philosophy: **one pass, one transformation**:

```cpp
class InlinerPass : public PassWrapper<...> {
  void runOnOperation() override {
    // Only inline functions, nothing else
  }
};

class CSEPass : public PassWrapper<...> {
  void runOnOperation() override {
    // Only eliminate common subexpressions
  }
};

class ConstantFoldPass : public PassWrapper<...> {
  void runOnOperation() override {
    // Only fold constants
  }
};
```

Now you can:
- Test each pass independently
- Run them in different orders
- Reuse individual passes across compilers
- Debug by disabling individual passes
- Understand what each pass does (it's focused!)

This is **composition over monoliths**.

### The Walk vs Pattern Rewrite Tradeoff

Jeremy Kun highlights two approaches for implementing passes, and understanding when to use each is crucial.

**Walk Approach:**
```cpp
getOperation()->walk([](Operation *op) {
  // Manually inspect and modify operations
});
```

**Pattern Rewrite Approach:**
```cpp
RewritePatternSet patterns(&getContext());
patterns.add<MyPattern>(&getContext());
applyPatternsAndFoldGreedily(getOperation(), std::move(patterns));
```

The tradeoff isn't about "which is better"—it's about **what kind of transformation you're doing**.

**Use Walking when:**
- You need full dataflow analysis (like CSE, which must track all definitions)
- You're collecting information (counting operations, building graphs)
- Your transformation logic involves complex global state
- You need complete control over traversal order

**Use Pattern Rewriting when:**
- You're doing local transformations (change operation X to Y)
- Multiple patterns might apply (MLIR will try them all)
- You want automatic fixed-point iteration (apply until nothing changes)
- You can express logic as "match this, replace with that"

Most MLIR passes use **pattern rewriting** because it's higher-level and handles common cases automatically. But walking is always available when you need low-level control.

### Examples of Different Pass Types

**Optimization Passes:**
- **CSE (Common Subexpression Elimination):** Removes redundant computations
- **DCE (Dead Code Elimination):** Removes unused operations
- **Constant Folding:** Evaluates constants at compile time
- **Inlining:** Replaces function calls with function bodies

**Lowering Passes:**
- **math → arith + scf:** Lowers high-level math ops to basic arithmetic and control flow
- **tensor → linalg:** Lowers tensor operations to linear algebra
- **linalg → loops:** Lowers linear algebra to explicit loops

**Analysis Passes:**
- **Operation Counter:** Counts how many operations of each type exist
- **Dominance Analysis:** Computes dominator trees for control flow
- **Alias Analysis:** Determines which memory operations might overlap

**Cleanup/Normalization Passes:**
- **Canonicalization:** Transforms IR to canonical form (e.g., sorts operands, simplifies patterns)
- **Symbol DCE:** Removes unused functions and globals
- **Strip Debug Info:** Removes debug metadata

The pattern: **small, focused, composable**. You build complex compilers by chaining simple passes.

## 🔬 Example Pass: MulToAdd

Let's implement a simple optimization that converts multiplication by a constant to repeated addition:

```
%result = arith.muli %x, 3   →   %1 = arith.addi %x, %x
                                  %result = arith.addi %1, %x
```

This is in `lib/Transform/Arith/MulToAdd.cpp`.

### The Complete Pass

```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

namespace mlir {
namespace tutorial {

#define GEN_PASS_DECL_MULTOADD
#define GEN_PASS_DEF_MULTOADD
#include "Transform/Arith/Passes.h.inc"

struct MulToAdd : impl::MulToAddBase<MulToAdd> {
  using MulToAddBase::MulToAddBase;

  void runOnOperation() override {
    mlir::RewritePatternSet patterns(&getContext());
    patterns.add<MulToAddPattern>(&getContext());
    (void)applyPatternsAndFoldGreedily(getOperation(), std::move(patterns));
  }
};

} // namespace tutorial
} // namespace mlir
```

### Breaking It Down

**1. Includes:**
```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"   // arith dialect ops
#include "mlir/IR/PatternMatch.h"          // Pattern matching
#include "mlir/Pass/Pass.h"                // Pass infrastructure
```

**2. Pass Definition:**
```cpp
struct MulToAdd : impl::MulToAddBase<MulToAdd> {
```

`MulToAddBase` is generated from TableGen (we'll see this in Tutorial 04).

**3. runOnOperation():**
```cpp
void runOnOperation() override {
  mlir::RewritePatternSet patterns(&getContext());
  patterns.add<MulToAddPattern>(&getContext());
  (void)applyPatternsAndFoldGreedily(getOperation(), std::move(patterns));
}
```

- Create a pattern set
- Add our rewrite pattern
- Apply patterns until no more changes (greedy)

## Implementing the Rewrite Pattern

```cpp
struct MulToAddPattern : public OpRewritePattern<arith::MulIOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(arith::MulIOp op,
                                PatternRewriter &rewriter) const override {
    // Get the constant operand
    auto lhs = op.getLhs();
    auto rhs = op.getRhs();

    // Check if RHS is a constant
    auto rhsDefOp = rhs.getDefiningOp<arith::ConstantOp>();
    if (!rhsDefOp) return failure();

    // Get constant value
    auto rhsAttr = rhsDefOp.getValue().dyn_cast<IntegerAttr>();
    if (!rhsAttr) return failure();

    int64_t rhsValue = rhsAttr.getInt();
    if (rhsValue <= 0 || rhsValue > 10) return failure();  // Only small values

    // Build replacement: repeated addition
    Value result = lhs;
    for (int i = 1; i < rhsValue; ++i) {
      result = rewriter.create<arith::AddIOp>(op.getLoc(), result, lhs);
    }

    rewriter.replaceOp(op, result);
    return success();
  }
};
```

### Pattern Matching Details

**1. Pattern Template:**
```cpp
struct MulToAddPattern : public OpRewritePattern<arith::MulIOp>
```

This pattern matches `arith.muli` operations.

**2. matchAndRewrite Signature:**
```cpp
LogicalResult matchAndRewrite(arith::MulIOp op,
                              PatternRewriter &rewriter) const
```

- **`op`** - The matched `arith.muli` operation
- **`rewriter`** - Builder for creating new operations
- **Return** - `success()` if pattern applied, `failure()` otherwise

**3. Checking Constraints:**
```cpp
auto rhsDefOp = rhs.getDefiningOp<arith::ConstantOp>();
if (!rhsDefOp) return failure();
```

Only match if RHS is a constant (not a variable).

**4. Building Replacement:**
```cpp
for (int i = 1; i < rhsValue; ++i) {
  result = rewriter.create<arith::AddIOp>(op.getLoc(), result, lhs);
}
```

Create a chain of additions.

**5. Replacing the Operation:**
```cpp
rewriter.replaceOp(op, result);
return success();
```

Replace `arith.muli` with the final addition result.

## Walking the IR

Sometimes you need to visit operations without pattern matching. Use **walkers**:

```cpp
void runOnOperation() override {
  getOperation()->walk([](arith::MulIOp mulOp) {
    llvm::errs() << "Found multiplication: " << mulOp << "\n";
  });
}
```

**Walk methods:**
- `walk([](OpType op) { ... })` - Visit all operations of type
- `walk<WalkOrder::PreOrder>([](Operation *op) { ... })` - Visit all ops
- Early termination:
  ```cpp
  getOperation()->walk([](Operation *op) {
    if (/* condition */) return WalkResult::interrupt();
    return WalkResult::advance();
  });
  ```

## 👉 Building the Pass on Windows

### 1. Add to CMakeLists.txt

`lib/Transform/Arith/CMakeLists.txt`:

```cmake
add_mlir_library(MLIRMulToAddPasses
  MulToAdd.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/lib/Transform/Arith

  DEPENDS
  MLIRArithPassIncGen

  LINK_LIBS PUBLIC
  MLIRArithDialect
  MLIRPass
  MLIRTransforms
)
```

### 2. Build

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
cd build
ninja MLIRMulToAddPasses
```

### 3. Register with tutorial-opt

In `tools/tutorial-opt.cpp`:

```cpp
#include "Transform/Arith/Passes.h"

int main(int argc, char **argv) {
  // Register passes
  mlir::tutorial::registerMulToAddPass();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Tutorial Pass Driver\n"));
}
```

### 4. Rebuild tutorial-opt

**Working directory:** Build directory (such as `D:\repos\mlir-tutorial\build\`)

```powershell
ninja tutorial-opt
```

## 👉 Testing the Pass

Create `tests/mul_to_add.mlir`:

```mlir
// RUN: tutorial-opt %s --mul-to-add | FileCheck %s

func.func @test_mul_to_add(%arg0: i32) -> i32 {
  %c3 = arith.constant 3 : i32
  %result = arith.muli %arg0, %c3 : i32
  return %result : i32
}

// CHECK-LABEL: func.func @test_mul_to_add
// CHECK-NOT: arith.muli
// CHECK: %[[ADD1:.*]] = arith.addi %arg0, %arg0
// CHECK: %[[RESULT:.*]] = arith.addi %[[ADD1]], %arg0
// CHECK: return %[[RESULT]]
```

### Run the test:

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
# Run transformation
.\build\bin\tutorial-opt.exe .\tests\mul_to_add.mlir --mul-to-add

# Run with FileCheck
.\build\bin\tutorial-opt.exe .\tests\mul_to_add.mlir --mul-to-add | FileCheck .\tests\mul_to_add.mlir

# Run all tests
cd build
ninja check-mlir-tutorial
```

## 🔍 Common Pattern Rewriting Idioms

### 1. Replace with Single Value

```cpp
rewriter.replaceOp(op, newValue);
```

### 2. Replace with Multiple Values

```cpp
SmallVector<Value> newValues = {val1, val2, val3};
rewriter.replaceOp(op, newValues);
```

### 3. Erase Operation

```cpp
rewriter.eraseOp(op);
```

### 4. Modify in Place

```cpp
rewriter.startRootUpdate(op);
op.setOperand(0, newOperand);
rewriter.finalizeRootUpdate(op);
```

### 5. Insert New Operation

```cpp
rewriter.setInsertionPoint(op);
auto newOp = rewriter.create<SomeOp>(op.getLoc(), ...);
```

## 🔍 Pattern Matching Features

### Matching Attributes

```cpp
auto constOp = op.getOperand(0).getDefiningOp<arith::ConstantOp>();
if (!constOp) return failure();

auto intAttr = constOp.getValue().dyn_cast<IntegerAttr>();
if (intAttr && intAttr.getInt() == 42) {
  // Match constant 42
}
```

### Matching Types

```cpp
auto intType = op.getType().dyn_cast<IntegerType>();
if (intType && intType.getWidth() == 32) {
  // Match i32 type
}
```

### Matching Nested Operations

```cpp
auto funcOp = op->getParentOfType<func::FuncOp>();
if (!funcOp) return failure();  // Not inside a function
```

## 👉 Debugging Passes

### 1. Print Debug Info

```cpp
LogicalResult matchAndRewrite(arith::MulIOp op,
                              PatternRewriter &rewriter) const override {
  llvm::errs() << "Matching: " << op << "\n";
  // ... rest of pattern
}
```

### 2. Dump IR

```cpp
op.dump();              // Print operation
op.getOperation()->dump();  // Verbose print
getOperation()->dump();     // Dump entire module
```

### 3. Verify IR

```cpp
if (failed(verify(getOperation()))) {
  getOperation()->emitError("IR verification failed");
  signalPassFailure();
}
```

### 4. Use VSCode Debugger

Set breakpoint in `matchAndRewrite()`, then press **F5**:

`.vscode/launch.json` is already configured for debugging tutorial-opt.

## 📖 Pass Ordering and Pipelines

### Running Multiple Passes

**Working directory:** Repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
# Run passes sequentially
.\build\bin\tutorial-opt.exe input.mlir --pass1 --pass2 --pass3

# Use pass pipeline syntax
.\build\bin\tutorial-opt.exe input.mlir --pass-pipeline="builtin.module(func.func(pass1,pass2))"
```

### Pass Dependencies

Some passes require others to run first:

```cpp
void getDependentDialects(DialectRegistry &registry) const override {
  registry.insert<arith::ArithDialect>();
  registry.insert<func::FuncDialect>();
}
```

## 📖 Best Practices

### 1. Return failure() Early

```cpp
LogicalResult matchAndRewrite(...) const override {
  // Check all conditions first
  if (!condition1) return failure();
  if (!condition2) return failure();
  if (!condition3) return failure();

  // Then do transformation
  // ...
  return success();
}
```

### 2. Preserve Location Info

```cpp
rewriter.create<SomeOp>(op.getLoc(), ...);  // Use original location
```

### 3. Check for Null

```cpp
auto defOp = value.getDefiningOp();
if (!defOp) return failure();  // Value might be block argument
```

### 4. Use Type-Safe Casts

```cpp
auto intType = type.dyn_cast<IntegerType>();  // Returns null if wrong type
if (!intType) return failure();
```

## Design Decisions: Why MLIR Passes Work This Way

Before we wrap up, let's discuss some important design decisions that Jeremy Kun highlighted.

### Why Passes Anchor to Operations

You might notice that passes specify which operation they run on:

```cpp
struct MyPass : impl::MyPassBase<MyPass> {
  void runOnOperation() override {
    // Operates on getOperation()
  }
};
```

In the `.td` file, you might see:

```tablegen
def MyPass : Pass<"my-pass", "func::FuncOp"> {
  // Anchored to FuncOp
}
```

**Why anchor passes?** Because MLIR runs passes **in parallel** when safe. If a pass is anchored to `FuncOp`, MLIR can run it on different functions simultaneously. But this means:

- The pass **can't modify operations outside its anchor** (e.g., can't modify global state from a FuncOp pass)
- The pass **must be safe to run in parallel**
- Memory modifications (stores, loads) inside the function body are OK because the **operation within the loop can modify stuff outside its body**

This is a **deliberate constraint** to enable parallelism. Understanding this helps you design passes correctly.

### The Implicit Dependency: Canonicalization

Our `MulToAdd` pass relied on something subtle: **MLIR's canonicalization infrastructure**. The pass assumes:

1. Constants appear in **consistent positions** (RHS of mul)
2. Trivial patterns are **already simplified** (e.g., `mul x, 1` → `x`)
3. Dead code has been **eliminated**

Without these assumptions, our pass would need to handle cases like:
- `%result = arith.muli %c3, %x` (constant on LHS instead of RHS)
- `%result = arith.muli %x, %c1` (should just return %x)
- `%unused = arith.muli %x, %c3` (dead code)

MLIR's convention: **canonicalization passes run frequently**. You can assume your input is in canonical form. This lets you write simpler passes.

**The tradeoff:** Your pass depends on other passes running first. This isn't a bug—it's **intentional layering**. MLIR's pass infrastructure manages these dependencies.

### Pattern Rewriting is Declarative

When you write:

```cpp
patterns.add<MulToAddPattern>(&getContext());
applyPatternsAndFoldGreedily(getOperation(), std::move(patterns));
```

You're not saying "run this pattern once." You're saying:

> "Here's a transformation. Apply it wherever it matches, repeatedly, until nothing changes."

This **fixed-point iteration** is automatic. MLIR keeps applying your pattern until:
- No more operations match, OR
- The pattern returns `failure()`, OR
- A maximum iteration limit is reached (to prevent infinite loops)

This is **declarative programming**: you describe what to do, not how to orchestrate it. MLIR figures out the orchestration.

### The Philosophy: Trust the Infrastructure

Writing MLIR passes requires trusting that:
- **Canonicalization** will normalize your input
- **Pattern rewriting** will iterate to fixpoint
- **Verification** will catch structural errors
- **Pass manager** will run passes in the right order

This trust is earned: MLIR's infrastructure has been battle-tested on massive codebases at Google, Meta, Apple, and others. But it requires a **mental shift** from "I control everything" to "I compose with the infrastructure."

## Key Takeaways: What You've Really Learned

### 1. Passes Are MLIR's Fundamental Abstraction

Everything meaningful in MLIR happens through passes. Optimizations, lowering, analysis—all implemented as passes. Mastering passes means mastering MLIR.

### 2. Small, Focused Transformations Scale

One pass, one transformation. This seems constraining at first, but it enables:
- Independent testing
- Precise debugging
- Reusable components
- Clear dependencies

### 3. Pattern Rewriting is Powerful

Most local transformations fit the pattern-rewriting model. Learning to think in terms of "match and rewrite" makes pass development dramatically faster.

### 4. Walking is for Complex Analysis

When pattern rewriting isn't enough—when you need global dataflow analysis or complex state—walking gives you full control.

### 5. CMake Integration is Straightforward

Adding passes to the build is mechanical: `add_mlir_library`, link dependencies, register in tool. The infrastructure handles the rest.

### 6. FileCheck Tests Document Behavior

Tests aren't just verification—they're executable documentation showing what your pass does. Write them early, refer to them often.

### 7. MLIR's Design Enables Parallelism

Anchoring passes to operations enables parallel execution. Understanding this constraint helps you design passes that cooperate with MLIR's infrastructure.

### 8. You're Building on Proven Patterns

The pass infrastructure, pattern rewriting, and testing approach have scaled to Google-sized codebases. Trust the patterns, adapt them to your needs.

## Next Steps

1. **[Tutorial 04: Using Tablegen for Passes](04-using-tablegen.md)** - Generate boilerplate automatically
2. **Explore existing passes** - Look at `lib/Transform/` for more examples
3. **Write your own pass** - Start with simple transformations

## Additional Resources

- **MLIR Pass Infrastructure:** [mlir.llvm.org/docs/PassManagement/](https://mlir.llvm.org/docs/PassManagement/)
- **Pattern Rewriting:** [mlir.llvm.org/docs/PatternRewriter/](https://mlir.llvm.org/docs/PatternRewriter/)
- **Operation Walkers:** [mlir.llvm.org/docs/Tutorials/UnderstandingTheIRStructure/](https://mlir.llvm.org/docs/Tutorials/UnderstandingTheIRStructure/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/08/10/mlir-writing-our-first-pass/)

---

**Previous:** [← Tutorial 02: Running and Testing](02-running-and-testing.md)
**Next:** [Tutorial 04: Using Tablegen for Passes →](04-using-tablegen.md)
