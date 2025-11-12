# Tutorial 07: Folders and Constant Propagation

**Original Article:** [MLIR ,  Folders](https://jeremykun.com/2023/09/11/mlir-folders/) by Jeremy Kun

**Windows Adaptation:** Focus on constant folding mechanisms with CMake build integration.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 💡 What You'll Learn

- Understanding **constant propagation** vs **canonicalization**
- Implementing **folder methods** for operations
- Creating **constant operations** for your dialect
- Writing **constant materializers** at the dialect level
- Using **SCCP** (Sparse Conditional Constant Propagation) pass
- Integrating folders with **CMake**

## The Philosophy of Compile-Time Evaluation

Here's a fundamental question: **why wait until runtime to compute something you already know at compile time?**

Consider this code:

```mlir
%c2 = arith.constant 2 : i32
%c3 = arith.constant 3 : i32
%result = arith.addi %c2, %c3 : i32
```

At runtime, this generates instructions: load 2, load 3, add them, store result. But the compiler already knows the answer is 5. Why generate instructions at all?

**Constant folding** is the optimization that eliminates this waste. It's not just an optimization, it's a **fundamental principle** of compilation: **do at compile time whatever you can, so runtime does less**.

### The Economic Argument

Every instruction you execute at runtime:
- Costs CPU cycles
- Consumes power
- Generates heat
- Takes time
- Blocks other work

Every computation you do at compile time:
- Happens once (during compilation)
- Costs nothing at runtime
- Makes programs smaller
- Makes programs faster
- Reduces energy consumption

In performance-critical code, constant propagation can eliminate entire functions, simplify control flow, and unlock further optimizations. **It's leverage, one compile-time computation saves millions of runtime executions.**

### What Are Folders?

**Folders** are MLIR's mechanism for implementing this principle. They're hooks that let operations say: "When all my inputs are constants, here's how to compute my output at compile time."

### The Transformation in Detail

**Before folding:**
```mlir
%c2 = arith.constant 2 : i32
%c3 = arith.constant 3 : i32
%result = arith.addi %c2, %c3 : i32  // Computed at runtime
```

**After folding:**
```mlir
%result = arith.constant 5 : i32 // Computed at compile time!
```

Notice what disappeared: the intermediate constants `%c2` and `%c3`, and the addition operation itself. The program is simpler, smaller, and faster.

The folding process:
1. **Recognition** - Identify that both operands are constants
2. **Evaluation** - Compute 2 + 3 = 5 using the operation's folder method
3. **Materialization** - Create a new constant operation with value 5
4. **Replacement** - Replace the original operation with the constant
5. **Propagation** - Let other operations fold using this new constant

This isn't just local optimization, it's a **cascade**. One folded operation creates new constant operands for other operations, which fold in turn, which creates more constants, etc. The program progressively simplifies.

## Local vs Global Optimization: SCCP and Canonicalization

MLIR provides two strategies for constant propagation, each with different trade-offs between power and complexity.

### The Architectural Distinction

**Local optimization** examines operations in isolation:
```
Operation → Check operands → Fold if constant → Done
```

**Global optimization** examines the entire program structure:
```
Program → Build dataflow graph → Propagate constants through edges → Fold operations
```

This isn't just a performance difference, it's a fundamental difference in what each approach can discover.

### SCCP: Sparse Conditional Constant Propagation

**SCCP** (`--sccp`) implements a sophisticated global analysis algorithm based on abstract interpretation.

**"Sparse"** means it only processes operations reachable through constant values, avoiding work on irrelevant code.

**"Conditional"** means it understands control flow:

```mlir
func.func @branching(%cond: i1) -> i32 {
  %c10 = arith.constant 10 : i32
  %c20 = arith.constant 20 : i32
  %result = arith.select %cond, %c10, %c20 : i32
  return %result : i32
}
```

If SCCP determines `%cond` is always true, it knows `%result` is always 10, even though there's a conditional. Local analysis can't do this; it doesn't track which branch executes.

**SCCP characteristics:**
- **Global dataflow analysis** - Builds a lattice of constant values across the entire function
- **Handles control flow** - Understands branches, loops, conditionals
- **Discovers more constants** - Finds constants that local analysis misses
- **More expensive** - Requires fixed-point iteration over the program
- **Interprocedural capable** - Can analyze across function boundaries (in principle)

**When SCCP excels:**
- Constants depend on control flow decisions
- Values propagate through multiple operations
- Dead code elimination opportunities exist (unreachable branches)

### Canonicalize: Local Pattern Matching

**Canonicalize** (`--canonicalize`) applies local rewrite patterns to individual operations.

```mlir
func.func @simple() -> i32 {
  %c2 = arith.constant 2 : i32
  %c3 = arith.constant 3 : i32
  %result = arith.addi %c2, %c3 : i32
  return %result : i32
}
```

Canonicalize looks at `arith.addi`, sees both operands are constants, calls the folder, and replaces the operation. No global analysis needed.

**Canonicalize characteristics:**
- **Local pattern matching** - Examines each operation independently
- **Fast** - O(n) pass over operations
- **Predictable** - Deterministic pattern application
- **Composable** - Often run multiple times in optimization pipelines
- **Limited scope** - Can't discover constants that require dataflow reasoning

**When Canonicalize excels:**
- Simple constant folding (direct constant operands)
- Algebraic simplifications (x + 0 = x, x * 1 = x)
- Quick cleanup after other transformations
- Iterative optimization pipelines (run after every major pass)

### Why Both Exist: The Trade-Off

This isn't redundancy, it's deliberate architectural choice.

**SCCP is powerful but expensive.** You run it once or twice in an optimization pipeline, at carefully chosen points where you expect to discover many constants.

**Canonicalize is cheap but limited.** You run it frequently, after every major transformation, to clean up and expose new optimization opportunities.

**Typical pipeline:**
```
Parse → Canonicalize → Dialect Lowering → Canonicalize →
SCCP → Canonicalize → More Lowering → Canonicalize → ...
```

Canonicalize between passes catches low-hanging fruit. SCCP runs when you need the heavy machinery.

### Both Depend on Folders

Crucially, **both passes rely on folder implementations**. Whether canonicalize or SCCP discovers that an operation has constant operands, the folder method does the actual evaluation.

This separation is elegant:
- **Folders** encode domain-specific constant evaluation (how to compute results)
- **Passes** encode search strategies (how to discover opportunities)

You implement folders once; they work with both local and global strategies.

## Implementing Folders: Three Components

A complete constant folding implementation requires three pieces:

```
1. Constant Operation
   ↓ (creates constant values in IR)
2. Folder Methods
   ↓ (compute results from constant inputs)
3. Constant Materializer
   ↓ (converts computed results back to IR)
```

Let's implement these for the Poly dialect.

## Component 1: Constant Operation

First, we need an operation to represent polynomial constants.

### Design: Before and After

**Before (multi-step):**
```mlir
// Step 1: Create integer tensor
%coeffs = arith.constant dense<[1, 2, 3]> : tensor<3xi32>

// Step 2: Convert to polynomial
%poly = poly.from_tensor %coeffs : tensor<3xi32> -> !poly.poly<10>
```

**After (single step):**
```mlir
// One operation!
%poly = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
```

### TableGen Definition

**File: `lib/Dialect/Poly/PolyOps.td`**

```tablegen
def Poly_ConstantOp : Poly_Op<"constant", [Pure, ConstantLike]> {
  let summary = "Define a constant polynomial";

  let description = [{
    Creates a polynomial constant from an array of integer coefficients.

    The coefficients are specified in order from lowest degree to highest:
      coeffs[0] + coeffs[1]*x + coeffs[2]*x^2 + ...

    Example:
      // p(x) = 1 + 2x + 3x^2
      %p = poly.constant dense<[1, 2, 3]> : !poly.poly<10>

      // p(x) = 5 (constant polynomial)
      %c = poly.constant dense<[5]> : !poly.poly<10>
  }];

  let arguments = (ins DenseIntElementsAttr:$coefficients);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $coefficients attr-dict `:` type($output)
  }];

  // Enable folding (trivial - just returns the attribute)
  let hasFolder = 1;
}
```

### Key Elements

**`DenseIntElementsAttr`:**
- Compact representation of integer arrays
- Stored as `dense<[1, 2, 3]>` in text format
- Efficient storage for constants

**`ConstantLike` trait:**
- Marks this as a constant-producing operation
- Enables certain optimizations
- Documents intent

**`hasFolder = 1`:**
- Tells TableGen to generate folder hook
- We'll implement the actual logic in C++

### C++ Implementation

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
#include "Dialect/Poly/PolyOps.h"
#include "Dialect/Poly/PolyDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;
using namespace mlir::tutorial::poly;

//===----------------------------------------------------------------------===//
// ConstantOp
//===----------------------------------------------------------------------===//

OpFoldResult ConstantOp::fold(ConstantOp::FoldAdaptor adaptor) {
  // A constant operation always folds to its own attribute
  return adaptor.getCoefficients();
}
```

**Why this works:**
- Constants fold to themselves
- The attribute is already the "computed" value
- No actual computation needed

## Component 2: Folder Methods

Now implement folders for arithmetic operations.

### The Folder Hook

TableGen generates this signature:

```cpp
OpFoldResult YourOp::fold(YourOp::FoldAdaptor adaptor);
```

**Return value options:**
1. **Attribute** - A constant result
2. **Value** - An existing SSA value (for identity operations)
3. **nullptr** - Cannot fold

**FoldAdaptor:**
- Provides access to operands
- If operand is constant → returns Attribute
- If operand is not constant → returns nullptr

### Example: Addition Folder

**File: `lib/Dialect/Poly/PolyOps.td`**

```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure, Commutative, ElementwiseMappable]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];

  // Enable folding
  let hasFolder = 1;
}
```

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
OpFoldResult AddOp::fold(AddOp::FoldAdaptor adaptor) {
  // Get constant operands (nullptr if not constant)
  auto lhs = adaptor.getLhs();
  auto rhs = adaptor.getRhs();

  // Check if both operands are constants
  if (!lhs || !rhs)
    return nullptr;

  // Cast to dense integer arrays
  auto lhsAttr = lhs.dyn_cast<DenseIntElementsAttr>();
  auto rhsAttr = rhs.dyn_cast<DenseIntElementsAttr>();

  if (!lhsAttr || !rhsAttr)
    return nullptr;

  // Use MLIR's built-in helper for elementwise binary operations
  auto result = constFoldBinaryOp<IntegerAttr>(
      lhsAttr, rhsAttr,
      [](APInt a, APInt b) { return a + b; });

  return result;
}
```

### Understanding constFoldBinaryOp

MLIR provides helpers for common folding patterns:

```cpp
template <typename AttrT, typename BinaryOp>
Attribute constFoldBinaryOp(Attribute lhs, Attribute rhs, BinaryOp &&op);
```

**What it does:**
1. Iterates over corresponding elements from `lhs` and `rhs`
2. Applies the lambda function (`a + b`)
3. Creates a new `DenseIntElementsAttr` with results

**Works for:**
- Addition: `[&](APInt a, APInt b) { return a + b; }`
- Subtraction: `[&](APInt a, APInt b) { return a - b; }`
- Multiplication: (needs custom logic - see below)

### Example: Subtraction Folder

```cpp
OpFoldResult SubOp::fold(SubOp::FoldAdaptor adaptor) {
  auto lhs = adaptor.getLhs();
  auto rhs = adaptor.getRhs();

  if (!lhs || !rhs)
    return nullptr;

  auto lhsAttr = lhs.dyn_cast<DenseIntElementsAttr>();
  auto rhsAttr = rhs.dyn_cast<DenseIntElementsAttr>();

  if (!lhsAttr || !rhsAttr)
    return nullptr;

  // Subtract coefficients element-wise
  return constFoldBinaryOp<IntegerAttr>(
      lhsAttr, rhsAttr,
      [](APInt a, APInt b) { return a - b; });
}
```

### Example: Multiplication Folder (Complex)

Polynomial multiplication requires convolution with modular reduction.

```cpp
OpFoldResult MulOp::fold(MulOp::FoldAdaptor adaptor) {
  auto lhs = adaptor.getLhs();
  auto rhs = adaptor.getRhs();

  if (!lhs || !rhs)
    return nullptr;

  auto lhsAttr = lhs.dyn_cast<DenseIntElementsAttr>();
  auto rhsAttr = rhs.dyn_cast<DenseIntElementsAttr>();

  if (!lhsAttr || !rhsAttr)
    return nullptr;

  // Get degree bound from result type
  auto resultType = getOutput().getType().cast<PolynomialType>();
  int degreeBound = resultType.getDegreeBound();

  // Extract coefficients
  SmallVector<APInt> lhsCoeffs(lhsAttr.getValues<APInt>());
  SmallVector<APInt> rhsCoeffs(rhsAttr.getValues<APInt>());

  // Initialize result with zeros
  SmallVector<APInt> resultCoeffs(degreeBound, APInt(32, 0));

  // Polynomial multiplication with modular reduction
  // (a_0 + a_1*x + ...) * (b_0 + b_1*x + ...)
  for (size_t i = 0; i < lhsCoeffs.size(); ++i) {
    for (size_t j = 0; j < rhsCoeffs.size(); ++j) {
      // Degree of this term: i + j
      int degree = (i + j) % degreeBound; // Reduce modulo x^D = 1

      // Accumulate coefficient
      resultCoeffs[degree] = resultCoeffs[degree] + (lhsCoeffs[i] * rhsCoeffs[j]);
    }
  }

  // Create result attribute
  auto elementType = IntegerType::get(getContext(), 32);
  return DenseIntElementsAttr::get(
      RankedTensorType::get({degreeBound}, elementType),
      resultCoeffs);
}
```

**Key points:**
1. **Convolution** - Multiply all coefficient pairs
2. **Modular reduction** - Degree wraps via `(i + j) % degreeBound`
3. **Result construction** - Create new `DenseIntElementsAttr`

## Component 3: Constant Materializer

The materializer converts computed attributes back into IR operations.

### Why Materializers Are Needed

**Problem:** Folders compute attributes, but IR needs operations.

**Folding process:**
```
1. fold() returns Attribute
   ↓
2. MLIR needs to insert this into IR
   ↓
3. materializeConstant() creates Operation
   ↓
4. Operation is inserted into IR
```

### Dialect-Level Hook

**File: `lib/Dialect/Poly/PolyDialect.h`**

```cpp
class PolyDialect : public ::mlir::Dialect {
public:
  // ... other methods ...

  // Materializer hook
  Operation *materializeConstant(OpBuilder &builder, Attribute value,
                                Type type, Location loc) override;
};
```

**File: `lib/Dialect/Poly/PolyDialect.cpp`**

```cpp
Operation *PolyDialect::materializeConstant(
    OpBuilder &builder, Attribute value, Type type, Location loc) {

  // Verify the value is a dense integer attribute
  auto denseAttr = value.dyn_cast<DenseIntElementsAttr>();
  if (!denseAttr)
    return nullptr;

  // Verify the type is a polynomial type
  auto polyType = type.dyn_cast<PolynomialType>();
  if (!polyType)
    return nullptr;

  // Create a poly.constant operation
  return builder.create<ConstantOp>(loc, polyType, denseAttr);
}
```

### How It's Used

When SCCP or canonicalize wants to replace an operation:

```cpp
// Before
%result = poly.add %const1, %const2 : (!poly.poly<10>, !poly.poly<10>)
                                   -> !poly.poly<10>

// Folder computes result as DenseIntElementsAttr: dense<[3, 5, 7]>

// Materializer creates:
%result = poly.constant dense<[3, 5, 7]> : !poly.poly<10>
```

## Complete Working Example

Let's put it all together with a complete example.

### File: `test_folding.mlir`

```mlir
// Test constant folding

module {
  func.func @test_add_fold() -> !poly.poly<10> {
    // These are constants
    %lhs = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
    %rhs = poly.constant dense<[4, 5, 6]> : !poly.poly<10>

    // Should fold to poly.constant dense<[5, 7, 9]>
    %result = poly.add %lhs, %rhs : (!poly.poly<10>, !poly.poly<10>)
                                 -> !poly.poly<10>

    return %result : !poly.poly<10>
  }

  func.func @test_mul_fold() -> !poly.poly<4> {
    // p(x) = 1 + x
    %lhs = poly.constant dense<[1, 1, 0, 0]> : !poly.poly<4>

    // q(x) = 2 + 3x
    %rhs = poly.constant dense<[2, 3, 0, 0]> : !poly.poly<4>

    // p*q = 2 + 5x + 3x^2
    // Should fold to dense<[2, 5, 3, 0]>
    %result = poly.mul %lhs, %rhs : (!poly.poly<4>, !poly.poly<4>)
                                 -> !poly.poly<4>

    return %result : !poly.poly<4>
  }

  func.func @test_propagation() -> !poly.poly<10> {
    %c1 = poly.constant dense<[1, 0, 0]> : !poly.poly<10>
    %c2 = poly.constant dense<[2, 0, 0]> : !poly.poly<10>

    // First add: folds to [3, 0, 0]
    %sum = poly.add %c1, %c2 : (!poly.poly<10>, !poly.poly<10>)
                            -> !poly.poly<10>

    // Second add: propagates the constant
    %result = poly.add %sum, %c1 : (!poly.poly<10>, !poly.poly<10>)
                                -> !poly.poly<10>
    // Should fold to [4, 0, 0]

    return %result : !poly.poly<10>
  }
}
```

### Running SCCP

```powershell
# Before optimization
.\build\bin\tutorial-opt.exe test_folding.mlir

# After SCCP
.\build\bin\tutorial-opt.exe test_folding.mlir --sccp

# With canonicalization
.\build\bin\tutorial-opt.exe test_folding.mlir --canonicalize

# See intermediate steps
.\build\bin\tutorial-opt.exe test_folding.mlir --sccp --mlir-print-ir-after-all
```

### Expected Output (after --sccp)

```mlir
module {
  func.func @test_add_fold() -> !poly.poly<10> {
    %result = poly.constant dense<[5, 7, 9]> : !poly.poly<10>
    return %result : !poly.poly<10>
  }

  func.func @test_mul_fold() -> !poly.poly<4> {
    %result = poly.constant dense<[2, 5, 3, 0]> : !poly.poly<4>
    return %result : !poly.poly<4>
  }

  func.func @test_propagation() -> !poly.poly<10> {
    %result = poly.constant dense<[4, 0, 0]> : !poly.poly<10>
    return %result : !poly.poly<10>
  }
}
```

All computations evaluated at compile time!

## CMake Integration

Folders don't require special CMake configuration beyond standard operation generation.

### File: `lib/Dialect/Poly/CMakeLists.txt`

```cmake
# Generate operations (includes folder hooks)
set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

# Build library with folder implementations
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp  # Contains fold() implementations

  DEPENDS
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRSideEffectInterfaces
)
```

### Build and Test

```powershell
cd D:\repos\mlir-tutorial\build
ninja MLIRPoly

# Test folding
.\bin\tutorial-opt.exe ..\tests\test_folding.mlir --sccp
.\bin\tutorial-opt.exe ..\tests\test_folding.mlir --canonicalize
```

## Advanced Folding Patterns

### Identity Folding

Some operations have identity properties that can be folded:

```cpp
// poly.add(%x, %zero) -> %x
OpFoldResult AddOp::fold(AddOp::FoldAdaptor adaptor) {
  // Check for constant folding first
  if (auto result = foldConstantOps(adaptor))
    return result;

  // Check for identity: x + 0 = x
  if (isZeroPolynomial(adaptor.getRhs()))
    return getLhs(); // Return the SSA value directly

  if (isZeroPolynomial(adaptor.getLhs()))
    return getRhs();

  return nullptr;
}

// Helper function
static bool isZeroPolynomial(Attribute attr) {
  auto denseAttr = attr.dyn_cast_or_null<DenseIntElementsAttr>();
  if (!denseAttr)
    return false;

  // Check if all coefficients are zero
  return llvm::all_of(denseAttr.getValues<APInt>(),
                     [](APInt val) { return val.isZero(); });
}
```

### Canonicalization Patterns

For more complex transformations, use canonicalization patterns:

```cpp
// In PolyOps.td
def Poly_AddOp : Poly_Op<"add", [Pure, Commutative]> {
  let hasFolder = 1;
  let hasCanonicalizer = 1;  // Enable canonicalization patterns
}
```

```cpp
// In PolyOps.cpp
void AddOp::getCanonicalizationPatterns(RewritePatternSet &patterns,
                                       MLIRContext *context) {
  patterns.add<SimplifyAddZero, CombineNestedAdds>(context);
}

// Pattern: add(x, 0) -> x
struct SimplifyAddZero : public OpRewritePattern<AddOp> {
  using OpRewritePattern<AddOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(AddOp op,
                               PatternRewriter &rewriter) const override {
    // Check if RHS is zero polynomial
    auto rhsConst = op.getRhs().getDefiningOp<ConstantOp>();
    if (!rhsConst || !isZero(rhsConst))
      return failure();

    // Replace with LHS
    rewriter.replaceOp(op, op.getLhs());
    return success();
  }
};

// Pattern: add(add(x, c1), c2) -> add(x, c1+c2)
struct CombineNestedAdds : public OpRewritePattern<AddOp> {
  using OpRewritePattern<AddOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(AddOp op,
                               PatternRewriter &rewriter) const override {
    // Match pattern: add(add(x, c1), c2)
    auto lhsAdd = op.getLhs().getDefiningOp<AddOp>();
    if (!lhsAdd)
      return failure();

    auto c1 = lhsAdd.getRhs().getDefiningOp<ConstantOp>();
    auto c2 = op.getRhs().getDefiningOp<ConstantOp>();

    if (!c1 || !c2)
      return failure();

    // Compute c1 + c2
    auto sum = addConstants(c1, c2, rewriter);

    // Create add(x, sum)
    rewriter.replaceOpWithNewOp<AddOp>(op, lhsAdd.getLhs(), sum);
    return success();
  }
};
```

## Folder Limitations

**Important:** Folders have strict constraints.

### What Folders CAN Do

✅ Return an attribute (constant result)
✅ Return an existing SSA value
✅ Return nullptr (cannot fold)
✅ Query operation properties
✅ Read constant operands

### What Folders CANNOT Do

❌ Create new operations
❌ Modify the operation being folded
❌ Use OpBuilder
❌ Access the IR beyond immediate operands
❌ Perform complex rewrites

**For complex transformations, use canonicalization patterns instead.**

### Example: Can vs Cannot

```cpp
// ✅ GOOD: Simple fold returning attribute
OpFoldResult AddOp::fold(FoldAdaptor adaptor) {
  return constFoldBinaryOp<IntegerAttr>(
      adaptor.getLhs(), adaptor.getRhs(),
      [](APInt a, APInt b) { return a + b; });
}

// ✅ GOOD: Identity fold returning existing value
OpFoldResult AddOp::fold(FoldAdaptor adaptor) {
  if (isZero(adaptor.getRhs()))
    return getLhs(); // Return SSA value
  return nullptr;
}

// ❌ BAD: Trying to create operations in folder
OpFoldResult AddOp::fold(FoldAdaptor adaptor) {
  OpBuilder builder(getContext());
  auto newOp = builder.create<ConstantOp>(...); // ERROR!
  return newOp.getResult();
}

// ❌ BAD: Trying to modify IR in folder
OpFoldResult AddOp::fold(FoldAdaptor adaptor) {
  getLhs().replaceAllUsesWith(...); // ERROR!
  return nullptr;
}
```

## Debugging Folding

### Enable Verbose Output

```powershell
# See what gets folded
.\build\bin\tutorial-opt.exe test.mlir --sccp --mlir-print-ir-after-all

# Show statistics
.\build\bin\tutorial-opt.exe test.mlir --sccp --mlir-pass-statistics
```

### Add Debug Output

```cpp
OpFoldResult AddOp::fold(AddOp::FoldAdaptor adaptor) {
  llvm::errs() << "Folding AddOp: ";
  this->dump();

  auto lhs = adaptor.getLhs();
  auto rhs = adaptor.getRhs();

  if (!lhs || !rhs) {
    llvm::errs() << "  -> Cannot fold (non-constant operands)\n";
    return nullptr;
  }

  // ... folding logic ...

  llvm::errs() << "  -> Folded successfully\n";
  return result;
}
```

### Test Individual Operations

```powershell
# Create minimal test
echo "func.func @test() {
  %c1 = poly.constant dense<[1]> : !poly.poly<10>
  %c2 = poly.constant dense<[2]> : !poly.poly<10>
  %r = poly.add %c1, %c2 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return
}" > minimal_test.mlir

# Run with SCCP
.\build\bin\tutorial-opt.exe minimal_test.mlir --sccp
```

### Check Generated Code

Verify folder hooks were generated:

```powershell
cat .\build\lib\Dialect\Poly\PolyOps.h.inc | Select-String "fold"
```

Should show:
```cpp
::mlir::OpFoldResult fold(FoldAdaptor adaptor);
```

## Real-World Examples

### Arithmetic Dialect

MLIR's arithmetic dialect has comprehensive folders:

```cpp
// arith.addi folds addition
OpFoldResult AddIOp::fold(FoldAdaptor adaptor) {
  // Fold constant operands
  if (APInt result = ...)
    return IntegerAttr::get(getType(), result);

  // Identity: x + 0 = x
  if (matchPattern(getRhs(), m_Zero()))
    return getLhs();

  return nullptr;
}
```

### Tensor Dialect

Tensor operations fold shape computations:

```cpp
OpFoldResult tensor::DimOp::fold(FoldAdaptor adaptor) {
  // If dimension is constant and tensor shape is static, fold!
  if (auto index = adaptor.getIndex().dyn_cast_or_null<IntegerAttr>()) {
    auto tensorType = getSource().getType().cast<RankedTensorType>();
    if (tensorType.hasStaticShape()) {
      int64_t dim = tensorType.getDimSize(index.getInt());
      return IntegerAttr::get(getType(), dim);
    }
  }
  return nullptr;
}
```

## Key Takeaways

**Conceptual:**

✅ **Compile-time evaluation is economic leverage** - One compile-time computation saves millions of runtime executions. Every instruction eliminated at compile time reduces power, heat, time, and enables further optimizations

✅ **Constant folding cascades through programs** - One folded operation creates new constant operands for other operations, which fold in turn, creating a progressive simplification effect

✅ **Layered mechanisms address different scopes** - Folders provide local evaluation, canonicalization handles structural patterns, and SCCP bridges control flow. No single mechanism efficiently addresses all optimization scenarios, so the infrastructure provides complementary layers

✅ **Local vs global is an architectural choice** - Canonicalization examines operations in isolation (fast, composable, limited scope). SCCP builds dataflow graphs (slower, powerful, crosses control flow boundaries). Each serves different optimization priorities

✅ **Folders are decidedly local** - Jeremy's key constraint: "Folds may only modify the single operation being folded, use existing SSA values, and may not create new ops." This limitation forces simplicity and composability

✅ **Implementation complexity scales with operations** - Jeremy acknowledges polynomial multiplication requires "the naive textbook polymul algorithm, which could be optimized if one expects people to start compiling programs with large, static polynomials." Folder sophistication must match operation semantics

✅ **Some coupling remains unclear even to experts** - Jeremy's honest uncertainty: "The trait is specifically required, so long as the materialization function is present...it just seems like this check is used for assertions. Perhaps it's just a safeguard." The relationship between `ConstantLike` trait and materialization isn't fully documented

**Practical:**

✅ **Three components required** - Constant operation, folder methods, constant materializer at dialect level

✅ **FoldAdaptor provides constant operands** - Returns attributes for constants, nullptr otherwise, simplifying constant detection

✅ **Folders have strict limitations** - Cannot create operations, modify IR, or use OpBuilder (only return attributes)

✅ **constFoldBinaryOp simplifies implementation** - Helper template for elementwise binary operations on dense tensors

✅ **SCCP discovers constants through control flow** - Finds constants hidden by branches and conditionals that local analysis misses

✅ **Canonicalize runs frequently for cleanup** - Fast, composable, suitable for repeated application in optimization pipelines

## Next Steps

1. **[Tutorial 08: Verifiers](08-verifiers.md)** - Add correctness checking to operations
2. **Implement folders** for remaining Poly operations
3. **Add canonicalization patterns** for complex simplifications
4. **Study** arithmetic dialect folders in MLIR source

## Additional Resources

- **MLIR Canonicalization:** [mlir.llvm.org/docs/Canonicalization/](https://mlir.llvm.org/docs/Canonicalization/)
- **Pattern Rewriting:** [mlir.llvm.org/docs/PatternRewriter/](https://mlir.llvm.org/docs/PatternRewriter/)
- **Arithmetic Dialect Source:** `C:\msys64\mingw64\include\mlir\Dialect\Arith\IR\ArithOps.cpp`
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/09/11/mlir-folders/)

---

**Previous:** [← Tutorial 06: Using Traits](06-using-traits.md)
**Next:** [Tutorial 08: Verifiers →](08-verifiers.md)
