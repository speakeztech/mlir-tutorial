# Tutorial 12: Global Optimization and Dataflow Analysis

**Original Article:** [MLIR — A Global Optimization and Dataflow Analysis](https://jeremykun.com/2023/11/15/mlir-a-global-optimization-and-dataflow-analysis/) by Jeremy Kun

**Windows Adaptation:** Focus on MLIR's dataflow analysis framework with practical examples using CMake build integration.

---

## 📖 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Advanced features and detailed analysis
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 What You'll Learn

- Understanding **dataflow analysis** fundamentals
- Using MLIR's **dataflow analysis framework**
- Implementing **lattice structures** for analysis values
- Writing **transfer functions** for operations
- Creating **custom analyses** (noise propagation example)
- Building **optimization passes** using analysis results
- Integrating **IntegerRangeAnalysis** for range tracking
- **CMake integration** for analysis passes

## Dataflow Analysis: Reasoning Without Execution

Here's a fundamental compiler problem: **you want to optimize code, but you can't run it**.

You need to answer questions like:
- "Is this variable always constant?"
- "Is this expression already computed somewhere?"
- "Could this pointer alias that one?"

But you can't just execute the program and observe—the compiler runs at compile time, before the program has inputs.

**Dataflow analysis** solves this by **propagating abstract information** through the program's control flow graph. Instead of executing with concrete values, you reason with abstract properties that hold across all possible executions.

### The Core Insight

Dataflow analysis combines two essential components:

**1. Transfer Functions** - How operations transform information
```
If x = y + z, and we know y ∈ [1,10] and z ∈ [5,15],
then x ∈ [6,25]
```

**2. Join Operations** - How to merge information from different paths
```
If one branch sets x = 5 and another sets x = 10,
then after the merge, x ∈ [5,10]
```

Together, these let you **propagate facts** through arbitrary control flow—loops, branches, function calls—arriving at safe approximations of program behavior.

### From Theory to Practice: The Noise Example

Jeremy Kun's tutorial uses a concrete example: tracking "noise" in homomorphic encryption operations. The question: "At this program point, how many bits of noise could this ciphertext contain?"

This isn't constant propagation (concrete values) or type checking (static types). It's **abstract interpretation**—tracking a property (noise bounds) that affects correctness but isn't directly represented in the IR.

**Why this example matters:**
- Shows analysis for a domain-specific property
- Demonstrates global optimization (where to insert noise reduction ops)
- Illustrates analysis-to-transformation pipeline
- Uses MLIR's extensibility (custom transfer functions via interfaces)

### Classic Dataflow Problems

For context, here are traditional analyses:

**Reaching definitions:** "Which assignments might reach this use?"
- Application: Dead code elimination, register allocation

**Live variable:** "Is this variable's value used later?"
- Application: Dead store elimination

**Constant propagation:** "Is this variable always constant?"
- Application: Compile-time evaluation (SCCP from Tutorial 07)

**Available expressions:** "Has this expression been computed already?"
- Application: Common subexpression elimination

MLIR's framework generalizes these patterns, letting you implement domain-specific analyses without reinventing the propagation machinery.

## Dataflow Analysis Theory

### Core Components

Every dataflow analysis needs three things:

**1. Lattice (Value Domain)**

A partially-ordered set with:
- **Bottom (⊥)**: Uninitialized/Unknown
- **Top (⊤)**: Could be anything/Overdefined
- **Join operation (∨)**: Combines values from multiple paths
- **Partial order (≤)**: Represents information refinement

**Example: Constant propagation lattice**
```
        ⊤ (overdefined - not constant)
       / | \
      /  |  \
    -1   0   1   2   3   ... (concrete values)
      \  |  /
       \ | /
        ⊥ (uninitialized)
```

**2. Transfer Function**

Describes how an operation transforms input values to outputs.

```
transfer: (Operation × InputLatticeValues) → OutputLatticeValues
```

**Example: Addition transfer function**
```
transfer(add, [Constant(2), Constant(3)]) = Constant(5)
transfer(add, [Constant(2), ⊥]) = ⊥
transfer(add, [Constant(2), ⊤]) = ⊤
```

**3. Join Operation**

Combines values when control flow merges.

```
join: (LatticeValue × LatticeValue) → LatticeValue
```

**Properties (must be satisfied):**
- **Associative**: `(a ∨ b) ∨ c = a ∨ (b ∨ c)`
- **Commutative**: `a ∨ b = b ∨ a`
- **Idempotent**: `a ∨ a = a`

**Example: Constant propagation join**
```
Constant(5) ∨ Constant(5) = Constant(5)
Constant(5) ∨ Constant(7) = ⊤ (not constant!)
Constant(5) ∨ ⊥ = Constant(5)
⊤ ∨ anything = ⊤
```

### Fixed-Point Iteration (Kildall's Algorithm)

Analysis runs iteratively:

```
1. Initialize all values to ⊥ (bottom)
2. Repeat:
   a. For each operation:
      - Apply transfer function
      - Join with existing output values
   b. Propagate to successor operations
3. Until no values change (fixed point reached)
```

**Termination guarantee:** Lattice is finite and values only move upward (toward ⊤).

## MLIR's Dataflow Framework

MLIR provides infrastructure so you only implement domain-specific logic.

### Framework Architecture

```
┌─────────────────────────────────┐
│   DataflowSolver                │  ← Orchestrates analysis
│   - Fixed-point iteration      │
│   - Dependency tracking         │
│   - Lattice management          │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│   AbstractDenseLattice          │  ← Base class for lattices
│   - join() operation            │
│   - Value domain                │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│   Your Custom Lattice           │  ← You implement this
│   - Specific value type         │
│   - Domain-specific join        │
└─────────────────────────────────┘
           ↓
┌─────────────────────────────────┐
│   Transfer Functions            │  ← You implement these
│   - Per operation logic         │
│   - InferIntRangeInterface etc. │
└─────────────────────────────────┘
```

### Key Classes

**`DataflowSolver`:**
- Manages fixed-point iteration
- Tracks analysis state
- Provides query interface

**`AbstractDenseLattice<T>`:**
- Base class for lattice values
- Templated on value type `T`
- Provides join operation

**`IntegerValueRange`:**
- Built-in lattice for integer ranges
- Tracks minimum and maximum values
- Used by `IntegerRangeAnalysis`

## Example: Noise Propagation Analysis

Let's build a custom analysis for a "noisy arithmetic" dialect where operations accumulate bounded random noise.

### Problem Domain

**Noisy operations:**
- `noisy.add %x, %y` - Adds values plus ±1 bit of noise
- `noisy.mul %x, %y` - Multiplies values, doubles noise
- `noisy.reduce_noise %x` - Reduces noise by half (expensive!)

**Goal:** Track noise bounds through the program and optimize placement of `reduce_noise` operations.

### Step 1: Define the Lattice

**File: `lib/Analysis/NoiseAnalysis.h`**

```cpp
#ifndef NOISE_ANALYSIS_H
#define NOISE_ANALYSIS_H

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Value.h"

namespace mlir {
namespace tutorial {

//===----------------------------------------------------------------------===//
// NoiseBound - Represents noise level bounds
//===----------------------------------------------------------------------===//

class NoiseBound {
public:
  NoiseBound() : min(0), max(0), isUninitialized(true) {}

  NoiseBound(int minNoise, int maxNoise)
      : min(minNoise), max(maxNoise), isUninitialized(false) {}

  // Check if value is bottom (uninitialized)
  bool isBottom() const { return isUninitialized; }

  // Get noise bounds
  int getMin() const { return min; }
  int getMax() const { return max; }

  // Join operation - combines two noise bounds
  static NoiseBound join(const NoiseBound &lhs, const NoiseBound &rhs) {
    // Bottom ∨ x = x
    if (lhs.isBottom())
      return rhs;
    if (rhs.isBottom())
      return lhs;

    // Take conservative estimate (maximum range)
    int newMin = std::min(lhs.min, rhs.min);
    int newMax = std::max(lhs.max, rhs.max);
    return NoiseBound(newMin, newMax);
  }

  bool operator==(const NoiseBound &other) const {
    if (isUninitialized != other.isUninitialized)
      return false;
    if (isUninitialized)
      return true;
    return min == other.min && max == other.max;
  }

  bool operator!=(const NoiseBound &other) const {
    return !(*this == other);
  }

private:
  int min;
  int max;
  bool isUninitialized;
};

//===----------------------------------------------------------------------===//
// NoiseLattice - Lattice wrapper for dataflow framework
//===----------------------------------------------------------------------===//

class NoiseLattice : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;

  // Get current noise bound
  const NoiseBound &getValue() const { return value; }

  // Join operation for the lattice
  ChangeResult join(const NoiseLattice &other) {
    NoiseBound newValue = NoiseBound::join(value, other.value);
    if (newValue != value) {
      value = newValue;
      return ChangeResult::Change;
    }
    return ChangeResult::NoChange;
  }

  // Print for debugging
  void print(raw_ostream &os) const override {
    if (value.isBottom()) {
      os << "⊥";
    } else {
      os << "[" << value.getMin() << ", " << value.getMax() << "]";
    }
  }

private:
  NoiseBound value;
};

} // namespace tutorial
} // namespace mlir

#endif // NOISE_ANALYSIS_H
```

### Step 2: Implement Transfer Functions

**File: `lib/Analysis/NoiseAnalysis.cpp`**

```cpp
#include "NoiseAnalysis.h"
#include "Dialect/Noisy/NoisyOps.h"
#include "mlir/Analysis/DataFlowFramework.h"

using namespace mlir;
using namespace mlir::tutorial;
using namespace mlir::tutorial::noisy;

//===----------------------------------------------------------------------===//
// NoiseAnalysis - Main analysis implementation
//===----------------------------------------------------------------------===//

class NoiseAnalysis : public dataflow::DenseForwardDataFlowAnalysis<NoiseLattice> {
public:
  using DenseForwardDataFlowAnalysis::DenseForwardDataFlowAnalysis;

  // Visit an operation and compute output noise bounds
  void visitOperation(Operation *op,
                     ArrayRef<const NoiseLattice *> operands,
                     ArrayRef<NoiseLattice *> results) override {

    // Handle noisy.add: adds ±1 bit of noise
    if (auto addOp = dyn_cast<AddOp>(op)) {
      if (operands[0]->getValue().isBottom() ||
          operands[1]->getValue().isBottom()) {
        // Uninitialized input
        return;
      }

      NoiseBound lhs = operands[0]->getValue();
      NoiseBound rhs = operands[1]->getValue();

      // Noise combines additively, plus ±1 from operation
      int newMin = lhs.getMin() + rhs.getMin() - 1;
      int newMax = lhs.getMax() + rhs.getMax() + 1;

      propagateIfChanged(results[0],
                        results[0]->join(NoiseLattice(NoiseBound(newMin, newMax))));
      return;
    }

    // Handle noisy.mul: doubles noise
    if (auto mulOp = dyn_cast<MulOp>(op)) {
      if (operands[0]->getValue().isBottom() ||
          operands[1]->getValue().isBottom()) {
        return;
      }

      NoiseBound lhs = operands[0]->getValue();
      NoiseBound rhs = operands[1]->getValue();

      // Noise doubles during multiplication
      int newMin = (lhs.getMin() + rhs.getMin()) * 2;
      int newMax = (lhs.getMax() + rhs.getMax()) * 2;

      propagateIfChanged(results[0],
                        results[0]->join(NoiseLattice(NoiseBound(newMin, newMax))));
      return;
    }

    // Handle noisy.reduce_noise: halves noise
    if (auto reduceOp = dyn_cast<ReduceNoiseOp>(op)) {
      if (operands[0]->getValue().isBottom()) {
        return;
      }

      NoiseBound input = operands[0]->getValue();

      // Noise reduced by half
      int newMin = input.getMin() / 2;
      int newMax = input.getMax() / 2;

      propagateIfChanged(results[0],
                        results[0]->join(NoiseLattice(NoiseBound(newMin, newMax))));
      return;
    }

    // Handle noisy.constant: zero noise
    if (auto constOp = dyn_cast<ConstantOp>(op)) {
      propagateIfChanged(results[0],
                        results[0]->join(NoiseLattice(NoiseBound(0, 0))));
      return;
    }

    // Default: propagate input noise unchanged
    setAllToEntryStates(results);
  }

  // Set initial state for block arguments
  void setToEntryState(NoiseLattice *lattice) override {
    // Function arguments start with zero noise
    lattice->join(NoiseLattice(NoiseBound(0, 0)));
  }
};
```

### Step 3: Create Analysis Pass

**File: `lib/Analysis/NoiseAnalysisPass.cpp`**

```cpp
#include "NoiseAnalysis.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Analysis/DataFlowFramework.h"

using namespace mlir;
using namespace mlir::tutorial;

namespace {
struct NoiseAnalysisPass
    : public PassWrapper<NoiseAnalysisPass, OperationPass<func::FuncOp>> {

  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NoiseAnalysisPass)

  StringRef getArgument() const final { return "noise-analysis"; }
  StringRef getDescription() const final {
    return "Analyze noise propagation in noisy arithmetic";
  }

  void runOnOperation() override {
    Operation *op = getOperation();

    // Create dataflow solver
    DataFlowSolver solver;

    // Load the noise analysis
    solver.load<NoiseAnalysis>();

    // Initialize with entry points
    if (failed(solver.initializeAndRun(op))) {
      signalPassFailure();
      return;
    }

    // Query and print results
    op->walk([&](Operation *innerOp) {
      for (Value result : innerOp->getResults()) {
        const NoiseLattice *lattice = solver.lookupState<NoiseLattice>(result);
        if (!lattice) {
          continue;
        }

        llvm::outs() << "Value: ";
        result.print(llvm::outs());
        llvm::outs() << " -> Noise: ";
        lattice->print(llvm::outs());
        llvm::outs() << "\n";
      }
    });
  }
};
} // namespace

void registerNoiseAnalysisPass() {
  PassRegistration<NoiseAnalysisPass>();
}
```

### Step 4: Test the Analysis

**File: `tests/noise_analysis.mlir`**

```mlir
// RUN: tutorial-opt %s --noise-analysis | FileCheck %s

func.func @example() {
  // CHECK: Value: %{{.*}} -> Noise: [0, 0]
  %c1 = noisy.constant 5 : i32

  // CHECK: Value: %{{.*}} -> Noise: [0, 0]
  %c2 = noisy.constant 10 : i32

  // CHECK: Value: %{{.*}} -> Noise: [-1, 1]
  %sum = noisy.add %c1, %c2 : i32

  // CHECK: Value: %{{.*}} -> Noise: [-2, 2]
  %product = noisy.mul %sum, %sum : i32

  // CHECK: Value: %{{.*}} -> Noise: [-1, 1]
  %reduced = noisy.reduce_noise %product : i32

  return
}
```

## Using IntegerRangeAnalysis

MLIR provides built-in **integer range analysis** - tracks min/max values for integer operations.

### What Is IntegerRangeAnalysis?

Tracks possible value ranges for integers:

```mlir
%c5 = arith.constant 5 : i32          // Range: [5, 5]
%c10 = arith.constant 10 : i32        // Range: [10, 10]
%sum = arith.addi %c5, %c10 : i32     // Range: [15, 15]

// After control flow merge:
%x = some_unknown_op : i32            // Range: [-∞, +∞]
%bounded = arith.andi %x, 0xFF : i32  // Range: [0, 255]
```

### Implementing InferIntRangeInterface

To enable range analysis for your operations:

**File: `lib/Dialect/Noisy/NoisyOps.td`**

```tablegen
def Noisy_AddOp : Noisy_Op<"add", [Pure, Commutative]> {
  let summary = "Noisy addition with random error";
  let arguments = (ins I32:$lhs, I32:$rhs);
  let results = (outs I32:$result);

  // Enable integer range inference
  let extraClassDeclaration = [{
    void inferResultRanges(ArrayRef<ConstantIntRanges> argRanges,
                          SetIntRangeFn setResultRange);
  }];
}
```

**File: `lib/Dialect/Noisy/NoisyOps.cpp`**

```cpp
#include "mlir/Interfaces/InferIntRangeInterface.h"

void AddOp::inferResultRanges(ArrayRef<ConstantIntRanges> argRanges,
                             SetIntRangeFn setResultRange) {
  // Get input ranges
  const ConstantIntRanges &lhs = argRanges[0];
  const ConstantIntRanges &rhs = argRanges[1];

  // Compute output range: lhs + rhs ± noise
  // For simplicity, assume ±1 noise
  APInt minValue = lhs.smin() + rhs.smin() - 1;  // Worst case: -1 noise
  APInt maxValue = lhs.smax() + rhs.smax() + 1;  // Worst case: +1 noise

  // Set result range
  setResultRange(getResult(), ConstantIntRanges::range(minValue, maxValue));
}
```

### Using Range Analysis

**File: `tests/range_analysis.mlir`**

```mlir
// RUN: tutorial-opt %s --int-range-analysis | FileCheck %s

func.func @ranges(%arg: i32) -> i32 {
  // Known ranges
  %c5 = arith.constant 5 : i32
  %c10 = arith.constant 10 : i32

  // Range: [15, 15]
  %sum = arith.addi %c5, %c10 : i32

  // Multiply by bounded value
  // Range: [0, 15 * max(%arg)]
  %result = arith.muli %sum, %arg : i32

  return %result : i32
}
```

## Building Optimizations from Analysis

Analysis results enable powerful optimizations.

### Example: Optimal Noise Reduction Placement

Use analysis results to insert `reduce_noise` operations optimally.

**File: `lib/Transform/OptimizeNoise.cpp`**

```cpp
#include "Analysis/NoiseAnalysis.h"
#include "mlir/Pass/Pass.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace mlir::tutorial;

namespace {

// Pattern: Insert reduce_noise when noise exceeds threshold
struct InsertNoiseReduction : public OpRewritePattern<noisy::AddOp> {
  InsertNoiseReduction(MLIRContext *context, DataFlowSolver &solver, int threshold)
      : OpRewritePattern<noisy::AddOp>(context), solver(solver), threshold(threshold) {}

  LogicalResult matchAndRewrite(noisy::AddOp op,
                               PatternRewriter &rewriter) const override {
    // Query noise analysis
    const NoiseLattice *lattice = solver.lookupState<NoiseLattice>(op.getResult());
    if (!lattice || lattice->getValue().isBottom()) {
      return failure();
    }

    NoiseBound noise = lattice->getValue();

    // Check if noise exceeds threshold
    if (noise.getMax() <= threshold) {
      return failure();  // Within acceptable bounds
    }

    // Insert reduce_noise operation after this add
    rewriter.setInsertionPointAfter(op);
    Value reduced = rewriter.create<noisy::ReduceNoiseOp>(
        op.getLoc(), op.getResult().getType(), op.getResult());

    // Replace uses (except the reduce_noise op itself)
    op.getResult().replaceAllUsesExcept(reduced, {reduced.getDefiningOp()});

    return success();
  }

private:
  DataFlowSolver &solver;
  int threshold;
};

//===----------------------------------------------------------------------===//
// Pass implementation
//===----------------------------------------------------------------------===//

struct OptimizeNoisePass
    : public PassWrapper<OptimizeNoisePass, OperationPass<func::FuncOp>> {

  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(OptimizeNoisePass)

  StringRef getArgument() const final { return "optimize-noise"; }
  StringRef getDescription() const final {
    return "Insert noise reduction operations optimally";
  }

  Option<int> threshold{*this, "threshold",
                       llvm::cl::desc("Maximum acceptable noise level"),
                       llvm::cl::init(4)};

  void runOnOperation() override {
    func::FuncOp func = getOperation();

    // Run analysis
    DataFlowSolver solver;
    solver.load<NoiseAnalysis>();

    if (failed(solver.initializeAndRun(func))) {
      signalPassFailure();
      return;
    }

    // Apply optimization patterns
    RewritePatternSet patterns(&getContext());
    patterns.add<InsertNoiseReduction>(&getContext(), solver, threshold);

    if (failed(applyPatternsAndFoldGreedily(func, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};

} // namespace

void registerOptimizeNoisePass() {
  PassRegistration<OptimizeNoisePass>();
}
```

### Test Optimization

**File: `tests/optimize_noise.mlir`**

```mlir
// RUN: tutorial-opt %s --optimize-noise --threshold=2 | FileCheck %s

func.func @excessive_noise() -> i32 {
  %c1 = noisy.constant 5 : i32
  %c2 = noisy.constant 10 : i32

  // Noise: [-1, 1]
  %sum1 = noisy.add %c1, %c2 : i32

  // Noise: [-2, 2]
  // CHECK: noisy.mul
  // CHECK-NEXT: noisy.reduce_noise
  %product = noisy.mul %sum1, %sum1 : i32

  // Noise: [-3, 3] - exceeds threshold!
  // CHECK: noisy.add
  // CHECK-NEXT: noisy.reduce_noise
  %sum2 = noisy.add %product, %c1 : i32

  return %sum2 : i32
}
```

## Advanced: Interprocedural Analysis

Dataflow analysis can work across function boundaries.

### Call Graph Analysis

```cpp
class InterproceduralNoiseAnalysis : public CallGraphAnalysis<NoiseLattice> {
public:
  using CallGraphAnalysis::CallGraphAnalysis;

  // Handle function calls
  void visitCall(CallOpInterface call,
                ArrayRef<const NoiseLattice *> arguments,
                ArrayRef<NoiseLattice *> results) override {
    // Propagate noise through function call
    Operation *callee = call.resolveCallable();
    if (!callee) {
      // Unknown callee - conservative estimate
      setAllToEntryStates(results);
      return;
    }

    // Analyze callee with given argument lattices
    // ... implementation details ...
  }
};
```

## CMake Integration

### File: `lib/Analysis/CMakeLists.txt`

```cmake
add_mlir_library(MLIRNoiseAnalysis
  NoiseAnalysis.cpp
  NoiseAnalysisPass.cpp

  DEPENDS
  MLIRNoisyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRAnalysis
  MLIRDataFlowFramework
  MLIRInferIntRangeInterface
  MLIRNoisyDialect
)
```

### File: `lib/Transform/CMakeLists.txt`

```cmake
add_mlir_library(MLIRNoiseOptimization
  OptimizeNoise.cpp

  DEPENDS
  MLIRNoisyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRTransforms
  MLIRNoiseAnalysis
  MLIRNoisyDialect
)
```

### Build and Test

```powershell
cd D:\repos\mlir-tutorial\build
ninja MLIRNoiseAnalysis MLIRNoiseOptimization

# Run analysis
.\bin\tutorial-opt.exe ..\tests\noise_analysis.mlir --noise-analysis

# Run optimization
.\bin\tutorial-opt.exe ..\tests\optimize_noise.mlir --optimize-noise
```

## Debugging Dataflow Analysis

### Enable Debug Output

```powershell
# Show dataflow iterations
.\build\bin\tutorial-opt.exe test.mlir --noise-analysis `
  --debug-only=dataflow

# Show lattice values at each step
.\build\bin\tutorial-opt.exe test.mlir --noise-analysis `
  --mlir-print-ir-after-all
```

### Add Diagnostic Output

```cpp
void NoiseAnalysis::visitOperation(Operation *op, ...) {
  llvm::errs() << "Visiting: ";
  op->print(llvm::errs());
  llvm::errs() << "\n";

  // ... analysis logic ...

  llvm::errs() << "Result lattice: ";
  results[0]->print(llvm::errs());
  llvm::errs() << "\n";
}
```

### Verify Analysis Results

```cpp
void NoiseAnalysisPass::runOnOperation() {
  // ... run analysis ...

  // Verify all values have valid lattices
  getOperation()->walk([&](Operation *op) {
    for (Value result : op->getResults()) {
      const NoiseLattice *lattice = solver.lookupState<NoiseLattice>(result);
      assert(lattice && "Missing lattice for value");
      assert(!lattice->getValue().isBottom() && "Uninitialized lattice");
    }
  });
}
```

## Performance Considerations

### Analysis Complexity

**Time complexity:** O(N × H)
- N = number of operations
- H = height of lattice (⊥ to ⊤)

**For finite lattices:**
- Guaranteed termination
- Polynomial time complexity

**For infinite lattices:**
- May not terminate
- Need widening operators

### Optimization Tips

**1. Use sparse analysis:**
```cpp
// Only analyze relevant operations
if (!isa<AddOp, MulOp, ReduceNoiseOp>(op)) {
  return;  // Skip analysis
}
```

**2. Cache results:**
```cpp
// Store computed lattices
DenseMap<Value, NoiseLattice> cache;
```

**3. Limit lattice height:**
```cpp
// Cap maximum noise level
if (noise.getMax() > MAX_NOISE) {
  return NoiseBound::top();  // Over-approximation
}
```

## Real-World MLIR Analyses

### IntegerRangeAnalysis

**Location:** `mlir/lib/Analysis/DataFlow/IntegerRangeAnalysis.cpp`

**Purpose:** Track integer value ranges

**Usage:**
```cpp
#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"

DataFlowSolver solver;
solver.load<IntegerRangeAnalysis>();
solver.initializeAndRun(op);

// Query ranges
const IntegerValueRange *range = solver.lookupState<IntegerValueRange>(value);
```

### DeadCodeAnalysis

**Location:** `mlir/lib/Analysis/DataFlow/DeadCodeAnalysis.cpp`

**Purpose:** Identify unreachable code

**Usage:**
```cpp
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"

DataFlowSolver solver;
solver.load<DeadCodeAnalysis>();
```

### SparseConstantPropagation

**Location:** `mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp`

**Purpose:** Propagate constant values

## Key Takeaways

**Conceptual:**

✅ **Lattice theory is a practical tool, not just math:** A semilattice—values with a "join" operation that merges information—provides the theoretical guarantee that your analysis will terminate. The join operation naturally expresses "what we know when we merge two control flow paths."

✅ **Separation of analysis from transformation:** The dataflow framework computes facts about your program without modifying it. Optimization passes then consume these facts to perform safe transformations. This separation means you can reuse analyses across multiple optimization contexts.

✅ **Abstract interpretation enables domain reasoning:** Instead of tracking concrete values (which explodes exponentially), track abstract properties—ranges, constants, types, nullability. The lattice structure ensures your approximations remain sound even when information flows through complex control flow.

✅ **Fixed-point iteration has guarantees:** Kildall's method repeatedly propagates information until nothing changes. The lattice's finite height guarantees this process terminates. Your only responsibility is defining a sound join operation and transfer functions.

✅ **The framework is the real deliverable:** MLIR's dataflow infrastructure handles worklists, state management, and interprocedural coordination. You focus on domain logic: "What properties matter?" and "How do operations transform those properties?" This is profound reuse—write 50 lines instead of 500.

**Practical:**

✅ **IntegerRangeAnalysis** tracks value ranges as intervals with join-as-union semantics, demonstrating the pattern for custom analyses

✅ **Custom analyses** extend base classes (`DataFlowAnalysis`, `AbstractDenseLattice`) and implement domain-specific join/transfer logic

✅ **Interprocedural analysis** crosses function boundaries when call graph information is available

✅ **CMake integration** follows standard pass patterns with dataflow framework linkage

## Next Steps

1. **[Tutorial 13: PDLL Patterns](13-pdll-patterns.md)** - Advanced pattern description language
2. **Implement custom analysis** for your dialect
3. **Study MLIR analyses** in `mlir/lib/Analysis/DataFlow/`
4. **Build optimization passes** using analysis results
5. **Experiment with lattice designs** for different domains
6. **Profile analysis performance** and optimize hot paths

## Additional Resources

- **Dataflow Framework:** [mlir.llvm.org/docs/DataFlowAnalysis/](https://mlir.llvm.org/docs/DataFlowAnalysis/)
- **IntegerRangeAnalysis:** Check `mlir/include/mlir/Analysis/DataFlow/IntegerRangeAnalysis.h`
- **Classic Dataflow:** "Compilers: Principles, Techniques, and Tools" (Dragon Book)
- **Kildall's Algorithm:** "A Unified Approach to Global Program Optimization" (1973)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/11/15/mlir-a-global-optimization-and-dataflow-analysis/)

---

**Previous:** [← Tutorial 11: Lowering through LLVM](11-lowering-through-llvm.md)
**Next:** [Tutorial 13: PDLL Patterns →](13-pdll-patterns.md)
