# Tutorial 09: Canonicalizers and Declarative Rewrite Patterns

**Original Article:** [MLIR — Canonicalizers and Declarative Rewrite Patterns](https://jeremykun.com/2023/09/20/mlir-canonicalizers-and-declarative-rewrite-patterns/) by Jeremy Kun

**Windows Adaptation:** Focus on canonicalization patterns using declarative rewrite rules (DRR) with CMake build integration.

---

## 📖 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Advanced features and detailed analysis
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 What You'll Learn

- Understanding **canonicalization** vs **folding**
- Implementing **canonicalizers** with C++ patterns
- Writing **declarative rewrite rules** (DRR) in TableGen
- Using **pattern constraints** and **variable binding**
- Integrating **DRR patterns** with CMake
- Testing **canonicalization passes**

## The Philosophy of Normal Forms

Here's a problem that arises in every compiler: **there are many ways to express the same computation**.

Consider these equivalent expressions:
```
x + x    vs    2 * x
x * 1    vs    x
x - 0    vs    x
(x + y) + z    vs    x + (y + z)
```

Mathematically equivalent, but structurally different in the IR. This creates a combinatorial explosion: every downstream pass must handle all possible equivalent forms.

**Canonicalization solves this** by transforming IR into a **normal form**—a standard representation chosen among equivalent alternatives.

### The Power of Standard Forms

When IR is in canonical form:
- **Pattern matching becomes trivial** - Look for one form, not dozens
- **Optimizations become reliable** - No missing cases due to unexpected structures
- **Analysis becomes simpler** - Don't need to reason about equivalent variations
- **Maintenance becomes manageable** - Fewer code paths to test

This is **reduction of complexity through standardization**. Instead of handling N different ways to express something, you transform to one canonical way and handle that.

### What Makes Canonicalization Different

**Folding (Tutorial 07)** evaluates operations with constant inputs:
```mlir
// Folding: evaluate at compile time
%c2 = arith.constant 2 : i32
%c3 = arith.constant 3 : i32
%result = arith.addi %c2, %c3 : i32
// → %result = arith.constant 5 : i32
```

Folding is limited: it can't create new operations, only return attributes or existing values.

**Canonicalization** restructures IR through **DAG-to-DAG rewriting**:
```mlir
// Canonicalization: restructure computation
%x2 = poly.mul %x, %x : !poly.poly<10>
%y2 = poly.mul %y, %y : !poly.poly<10>
%diff = poly.sub %x2, %y2 : !poly.poly<10>

// → Apply (x² - y²) = (x+y)(x-y)
%sum = poly.add %x, %y : !poly.poly<10>
%diff_temp = poly.sub %x, %y : !poly.poly<10>
%result = poly.mul %sum, %diff_temp : !poly.poly<10>
```

Canonicalization can:
- Create new operations
- Delete old operations
- Restructure computation graphs
- Apply algebraic identities

This is powerful—you're not just simplifying individual operations, you're **reshaping entire subgraphs**.

### Why Canonicalization Enables Optimization

The key insight: **optimizations compose better when IR is canonical**.

**Without canonicalization:**
```
Optimization Pass A sees: x + 0
Optimization Pass B sees: 0 + x
Optimization Pass C sees: x + (0 + 0)
```

Each pass must handle all forms, or miss optimization opportunities.

**With canonicalization:**
```
Canonicalize transforms all to: x
Optimization passes see uniform structure
Optimizations trigger reliably
```

Canonicalization is a **force multiplier**—it makes other passes exponentially more effective by reducing the space of IR structures they must handle.

### Common Canonicalization Patterns

**Algebraic identities:**
- Identity: `x + 0 → x`, `x * 1 → x`
- Idempotence: `abs(abs(x)) → abs(x)`
- Commutativity: Order operands consistently (e.g., constants on right)

**Strength reduction:**
- `x * 2 → x + x` (addition cheaper than multiplication)
- `x / 2 → x >> 1` (shift cheaper than division)

**Structural simplification:**
- `(x + y) + z → x + (y + z)` (associate to expose patterns)
- `x - x → 0` (eliminate redundant computation)
- Double negation: `not(not(x)) → x`

**Dead code elimination:**
- Remove operations whose results are unused
- Collapse chains of no-op operations

## Two Approaches to Canonicalization

MLIR provides two ways to implement canonicalizers.

### Approach 1: C++ Rewrite Patterns

**File: `lib/Dialect/Poly/PolyOps.td`**

```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure, Commutative]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];

  // Enable C++ canonicalization patterns
  let hasCanonicalizer = 1;
}
```

When `hasCanonicalizer = 1`, TableGen generates:

```cpp
// In PolyOps.h.inc
static void getCanonicalizationPatterns(
    ::mlir::RewritePatternSet &results,
    ::mlir::MLIRContext *context);
```

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
#include "Dialect/Poly/PolyOps.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace mlir::tutorial::poly;

//===----------------------------------------------------------------------===//
// Pattern: Simplify add(x, 0) -> x
//===----------------------------------------------------------------------===//

struct SimplifyAddZero : public OpRewritePattern<AddOp> {
  using OpRewritePattern<AddOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(AddOp op,
                               PatternRewriter &rewriter) const override {
    // Check if RHS is zero polynomial
    auto rhsConst = op.getRhs().getDefiningOp<ConstantOp>();
    if (!rhsConst)
      return failure();

    auto coeffs = rhsConst.getCoefficients();
    bool allZeros = llvm::all_of(
        coeffs.getValues<APInt>(),
        [](APInt val) { return val.isZero(); });

    if (!allZeros)
      return failure();

    // Replace with LHS
    rewriter.replaceOp(op, op.getLhs());
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Pattern: Combine add(add(x, c1), c2) -> add(x, c1+c2)
//===----------------------------------------------------------------------===//

struct CombineNestedAdds : public OpRewritePattern<AddOp> {
  using OpRewritePattern<AddOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(AddOp op,
                               PatternRewriter &rewriter) const override {
    // Match: add(add(x, c1), c2)
    auto lhsAdd = op.getLhs().getDefiningOp<AddOp>();
    if (!lhsAdd)
      return failure();

    auto c1 = lhsAdd.getRhs().getDefiningOp<ConstantOp>();
    auto c2 = op.getRhs().getDefiningOp<ConstantOp>();

    if (!c1 || !c2)
      return failure();

    // Compute c1 + c2 at compile time
    auto sum = addConstantPolynomials(c1, c2, rewriter);

    // Create: add(x, sum)
    rewriter.replaceOpWithNewOp<AddOp>(op, lhsAdd.getLhs(), sum);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Register patterns
//===----------------------------------------------------------------------===//

void AddOp::getCanonicalizationPatterns(RewritePatternSet &patterns,
                                       MLIRContext *context) {
  patterns.add<SimplifyAddZero, CombineNestedAdds>(context);
}
```

**Advantages:**
- Full C++ flexibility
- Can use complex logic
- Easy to debug

**Disadvantages:**
- Verbose boilerplate
- Type casting and null checks
- More code to maintain

### Approach 2: Declarative Rewrite Rules (DRR)

**Much simpler!** Write patterns in TableGen, not C++.

**File: `lib/Dialect/Poly/PolyCanonicalize.td`**

```tablegen
#ifndef POLY_CANONICALIZE_TD
#define POLY_CANONICALIZE_TD

include "mlir/IR/PatternBase.td"
include "Dialect/Poly/PolyOps.td"

// Pattern: Lift conjugate through evaluation
// Before: conj(eval(f, z))
// After:  eval(f, conj(z))
def LiftConjThroughEval : Pat<
  (Poly_EvalOp $f, (ConjOp $z)),
  (ConjOp (Poly_EvalOp $f, $z))
>;

#endif // POLY_CANONICALIZE_TD
```

That's it! No C++ code needed.

## Declarative Rewrite Rules: The Basics

### Pattern Syntax

```tablegen
def PatternName : Pat<
  (MatchPattern ...),      // What to match
  (ReplacePattern ...)     // What to replace with
>;
```

### Parenthetical Notation

Operations are represented as S-expressions:

```tablegen
// Matches: %result = poly.add %x, %y
(Poly_AddOp $x, $y)

// Matches: %result = poly.mul %a, %b
(Poly_MulOp $a, $b)

// Matches nested: poly.add(poly.mul(%x, %y), %z)
(Poly_AddOp (Poly_MulOp $x, $y), $z)
```

### Variable Binding

**`$varname`** captures matched values:

```tablegen
// Matches: poly.add %anything, %anything_else
// Binds: $x → first operand, $y → second operand
(Poly_AddOp $x, $y)

// Matches: poly.mul(poly.add(%a, %b), %c)
// Binds: $a, $b, $c individually
(Poly_MulOp (Poly_AddOp $a, $b), $c)
```

**Variables can be reused:**

```tablegen
// Matches: poly.mul %x, %x (same value twice!)
(Poly_MulOp $x, $x)

// Matches: poly.sub(poly.mul(%x, %x), poly.mul(%y, %y))
(Poly_SubOp (Poly_MulOp $x, $x), (Poly_MulOp $y, $y))
```

### Named Results

**`OpName:$name`** binds the operation result:

```tablegen
// Bind the mul operation's result to $lhs
(Poly_MulOp:$lhs $x, $x)

// Use in constraints (see below)
```

### Building Replacement Operations

**Replacement pattern** creates new operations:

```tablegen
// Input pattern
(Poly_SubOp (Poly_MulOp $x, $x), (Poly_MulOp $y, $y))

// Output pattern - creates three new operations:
// 1. %sum = poly.add %x, %y
// 2. %diff = poly.sub %x, %y
// 3. %result = poly.mul %sum, %diff
[
  (Poly_AddOp:$sum $x, $y),
  (Poly_SubOp:$diff $x, $y),
  (Poly_MulOp $sum, $diff)
]
```

**Note:** Array syntax `[...]` chains operations. Last result is the final replacement.

## Simple Patterns: Examples

### Example 1: Lift Operation Through Another

```tablegen
// Pattern: Move conjugate operation inside evaluation
def LiftConjThroughEval : Pat<
  (Poly_EvalOp $f, (ConjOp $z)),
  (ConjOp (Poly_EvalOp $f, $z))
>;
```

**Before:**
```mlir
%z_conj = complex.conj %z : complex<f64>
%result = poly.eval %poly, %z_conj : (!poly.poly<10>, complex<f64>)
```

**After:**
```mlir
%eval = poly.eval %poly, %z : (!poly.poly<10>, complex<f64>)
%result = complex.conj %eval : complex<f64>
```

**Why useful?**
- May enable further optimizations on `%z`
- Reduces intermediate computations
- Simplifies data flow analysis

### Example 2: Commutative Normalization

```tablegen
// Pattern: Ensure constants on right side
def MoveConstantRight : Pat<
  (Poly_AddOp (Poly_ConstantOp:$c $_), $x),
  (Poly_AddOp $x, $c)
>;
```

**Before:**
```mlir
%c = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
%result = poly.add %c, %x : !poly.poly<10>
```

**After:**
```mlir
%c = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
%result = poly.add %x, %c : !poly.poly<10>
```

**Why useful?**
- Canonical form simplifies pattern matching
- Other passes can assume constants on right
- Reduces cases to check

## Advanced Patterns: Using Constraints

For complex patterns, use the `Pattern` class with constraints.

### Pattern Class Syntax

```tablegen
def PatternName : Pattern<
  (MatchPattern ...),           // What to match
  [                             // What to create (multiple ops)
    (Op1 ...),
    (Op2 ...),
    ...
  ],
  [                             // Constraints
    (Constraint1 ...),
    (Constraint2 ...),
    ...
  ]
>;
```

### Example: Difference of Squares

Implements: **x² - y² = (x+y)(x-y)**

```tablegen
// Constraint: Operation has only one use
def HasOneUse : Constraint<
  CPred<"$_self.hasOneUse()">,
  "has one use"
>;

// Pattern: x² - y² → (x+y)(x-y)
def DifferenceOfSquares : Pattern<
  // Match: sub(mul(x,x), mul(y,y))
  (Poly_SubOp
    (Poly_MulOp:$lhs $x, $x),
    (Poly_MulOp:$rhs $y, $y)
  ),

  // Replace with:
  [
    (Poly_AddOp:$sum $x, $y),      // sum = x + y
    (Poly_SubOp:$diff $x, $y),     // diff = x - y
    (Poly_MulOp $sum, $diff)       // result = sum * diff
  ],

  // Only apply if both mul ops have single use
  [
    (HasOneUse $lhs),
    (HasOneUse $rhs)
  ]
>;
```

**Why constraints matter:**

Without `HasOneUse` constraint:
```mlir
// BAD: Increases computation!
%x2 = poly.mul %x, %x  // Still used elsewhere
%y2 = poly.mul %y, %y  // Still used elsewhere
%sum = poly.add %x, %y
%diff = poly.sub %x, %y
%result = poly.mul %sum, %diff
// Now we have 5 operations instead of 3!
```

With `HasOneUse` constraint:
```mlir
// GOOD: Replaces operations
%sum = poly.add %x, %y
%diff = poly.sub %x, %y
%result = poly.mul %sum, %diff
// Only 3 operations, mul operations eliminated
```

### Constraint Types

**Built-in constraints:**

```tablegen
// C++ predicate
Constraint<CPred<"c++ expression">, "description">

// Negation
Constraint<Neg<OtherConstraint>>

// Conjunction
Constraint<And<[Constraint1, Constraint2]>>

// Disjunction
Constraint<Or<[Constraint1, Constraint2]>>
```

**Custom constraints:**

```tablegen
// Check if value is constant zero
def IsZero : Constraint<
  CPred<"isConstantZero($_self)">,
  "is constant zero"
>;

// Check if polynomial degree is less than N
def DegreeLessThan<int N> : Constraint<
  CPred<"getPolynomialDegree($_self) < " # N>,
  "degree less than " # N
>;
```

**In C++ helper functions:**

```cpp
// In PolyOps.cpp or similar
static bool isConstantZero(Value val) {
  auto constOp = val.getDefiningOp<ConstantOp>();
  if (!constOp)
    return false;

  auto coeffs = constOp.getCoefficients();
  return llvm::all_of(coeffs.getValues<APInt>(),
                     [](APInt v) { return v.isZero(); });
}

static int getPolynomialDegree(Value val) {
  auto polyType = val.getType().cast<PolynomialType>();
  return polyType.getDegreeBound();
}
```

## Complex Pattern Example: Optimizing Multiplication

Let's implement a pattern that replaces multiplication by a power of 2 with repeated addition.

### Problem

Multiplication is expensive. If we're multiplying by a small constant like 2, 4, 8, we can use addition instead.

### Pattern Definition

**File: `lib/Dialect/Poly/PolyCanonicalize.td`**

```tablegen
// Constraint: Value is a constant power of two
def IsPowerOfTwo : Constraint<
  CPred<"isConstantPowerOfTwo($_self)">,
  "is constant power of two"
>;

// Constraint: Power is small (≤ 8)
def IsSmallPower : Constraint<
  CPred<"getConstantPowerOfTwo($_self) <= 3">,  // 2^3 = 8
  "power of two is small (≤ 8)"
>;

// Pattern: mul(x, 2^k) → repeated add when k ≤ 3
def MulByPowerOfTwoToAdd : Pattern<
  // Match: mul(x, constant)
  (Poly_MulOp:$mul $x, $c),

  // Replace: (handled in C++ due to complexity)
  // We'll use NativeCodeCall for this

  // Constraints
  [
    (IsPowerOfTwo $c),
    (IsSmallPower $c)
  ]
>;
```

**Problem:** Replacement requires **dynamic number of operations** (depends on power).

**Solution:** Use **NativeCodeCall** to inject C++ code.

### Using NativeCodeCall

```tablegen
// Native function to create repeated additions
def CreateRepeatedAdd : NativeCodeCall<
  "createRepeatedAddition($_builder, $0, $1)"
>;

// Pattern with native code call
def MulByPowerOfTwoToAdd : Pattern<
  (Poly_MulOp $x, $c:$_),

  // Call C++ function to generate operations
  (CreateRepeatedAdd $x, $c),

  [(IsPowerOfTwo $c), (IsSmallPower $c)]
>;
```

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
// Helper: Check if constant is power of two
static bool isConstantPowerOfTwo(Value val) {
  auto constOp = val.getDefiningOp<ConstantOp>();
  if (!constOp)
    return false;

  auto coeffs = constOp.getCoefficients().getValues<APInt>();

  // For polynomial, check if it's just [2^k, 0, 0, ...]
  if (coeffs.empty())
    return false;

  APInt firstCoeff = *coeffs.begin();
  if (!firstCoeff.isPowerOf2())
    return false;

  // All other coefficients must be zero
  return llvm::all_of(llvm::drop_begin(coeffs, 1),
                     [](APInt v) { return v.isZero(); });
}

static int getConstantPowerOfTwo(Value val) {
  auto constOp = val.getDefiningOp<ConstantOp>();
  auto coeffs = constOp.getCoefficients().getValues<APInt>();
  APInt firstCoeff = *coeffs.begin();
  return firstCoeff.logBase2();  // Returns k where 2^k = value
}

// Native code call: Create repeated additions
static Value createRepeatedAddition(OpBuilder &builder, Value base, Value constVal) {
  int power = getConstantPowerOfTwo(constVal);

  Value result = base;
  // For 2^k, we need k additions:
  // 2x = x+x
  // 4x = (x+x)+(x+x)
  // 8x = ((x+x)+(x+x))+((x+x)+(x+x))
  for (int i = 0; i < power; ++i) {
    result = builder.create<AddOp>(
        base.getLoc(),
        result.getType(),
        result,
        result);
  }

  return result;
}
```

### Benefits and Trade-offs

**When beneficial:**
- Small powers (2, 4, 8)
- Addition is much cheaper than multiplication
- Processor has fast addition units

**When harmful:**
- Large powers (16, 32, ...)
- Creates too many operations
- May increase register pressure

**That's why we need the `IsSmallPower` constraint!**

## CMake Integration

### Step 1: Create TableGen File

**File: `lib/Dialect/Poly/PolyCanonicalize.td`**

```tablegen
#ifndef POLY_CANONICALIZE_TD
#define POLY_CANONICALIZE_TD

include "mlir/IR/PatternBase.td"
include "Dialect/Poly/PolyOps.td"

// Import constraint definitions
def HasOneUse : Constraint<CPred<"$_self.hasOneUse()">, "has one use">;
def IsPowerOfTwo : Constraint<CPred<"isConstantPowerOfTwo($_self)">,
                              "is constant power of two">;
def IsSmallPower : Constraint<CPred<"getConstantPowerOfTwo($_self) <= 3">,
                              "power of two is small">;

// Patterns
def LiftConjThroughEval : Pat<
  (Poly_EvalOp $f, (ConjOp $z)),
  (ConjOp (Poly_EvalOp $f, $z))
>;

def DifferenceOfSquares : Pattern<
  (Poly_SubOp (Poly_MulOp:$lhs $x, $x), (Poly_MulOp:$rhs $y, $y)),
  [(Poly_AddOp:$sum $x, $y), (Poly_SubOp:$diff $x, $y), (Poly_MulOp $sum, $diff)],
  [(HasOneUse $lhs), (HasOneUse $rhs)]
>;

#endif // POLY_CANONICALIZE_TD
```

### Step 2: Update CMakeLists.txt

**File: `lib/Dialect/Poly/CMakeLists.txt`**

```cmake
# Generate operation definitions
set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

# Generate canonicalization patterns from DRR
set(LLVM_TARGET_DEFINITIONS PolyCanonicalize.td)
mlir_tablegen(PolyCanonicalize.inc -gen-rewriters)
add_public_tablegen_target(MLIRPolyCanonicalizePatternsIncGen)

# Build library
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp
  PolyTypes.cpp

  DEPENDS
  MLIRPolyOpsIncGen
  MLIRPolyCanonicalizePatternsIncGen  # Add dependency

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRSideEffectInterfaces
)
```

### Step 3: Include Generated Patterns

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
#include "Dialect/Poly/PolyOps.h"
#include "Dialect/Poly/PolyDialect.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace mlir::tutorial::poly;

// Include generated patterns
#include "PolyCanonicalize.inc"

//===----------------------------------------------------------------------===//
// AddOp Canonicalization
//===----------------------------------------------------------------------===//

void AddOp::getCanonicalizationPatterns(RewritePatternSet &patterns,
                                       MLIRContext *context) {
  // Add C++ patterns (if any)
  patterns.add<SimplifyAddZero, CombineNestedAdds>(context);

  // Add DRR patterns (if this op is involved)
  // They're added automatically by populating the pattern set
}

//===----------------------------------------------------------------------===//
// SubOp Canonicalization
//===----------------------------------------------------------------------===//

void SubOp::getCanonicalizationPatterns(RewritePatternSet &patterns,
                                       MLIRContext *context) {
  // DRR patterns like DifferenceOfSquares are automatically included
}
```

### Step 4: Build

```powershell
cd D:\repos\mlir-tutorial\build
ninja MLIRPoly

# Check generated file
cat .\lib\Dialect\Poly\PolyCanonicalize.inc | Select-String "DifferenceOfSquares"
```

## Testing Canonicalization

### Test File Structure

**File: `tests/canonicalize.mlir`**

```mlir
// RUN: tutorial-opt %s --canonicalize | FileCheck %s

module {
  // Test: Difference of squares optimization
  // CHECK-LABEL: @difference_of_squares
  func.func @difference_of_squares(%x: !poly.poly<10>, %y: !poly.poly<10>)
      -> !poly.poly<10> {
    // CHECK-NOT: poly.mul{{.*}}, {{.*}}same{{.*}}
    // CHECK: %[[SUM:.*]] = poly.add %arg0, %arg1
    // CHECK: %[[DIFF:.*]] = poly.sub %arg0, %arg1
    // CHECK: %[[RESULT:.*]] = poly.mul %[[SUM]], %[[DIFF]]
    // CHECK: return %[[RESULT]]

    %x2 = poly.mul %x, %x : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %y2 = poly.mul %y, %y : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %result = poly.sub %x2, %y2 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    return %result : !poly.poly<10>
  }

  // Test: Should NOT apply if operands are reused
  // CHECK-LABEL: @no_optimization_with_reuse
  func.func @no_optimization_with_reuse(%x: !poly.poly<10>, %y: !poly.poly<10>)
      -> (!poly.poly<10>, !poly.poly<10>) {
    // CHECK: %[[X2:.*]] = poly.mul %arg0, %arg0
    // CHECK: %[[Y2:.*]] = poly.mul %arg1, %arg1
    // CHECK: %[[RESULT:.*]] = poly.sub %[[X2]], %[[Y2]]
    // CHECK: return %[[RESULT]], %[[X2]]

    %x2 = poly.mul %x, %x : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %y2 = poly.mul %y, %y : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %result = poly.sub %x2, %y2 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    // x2 is used again here, so pattern shouldn't apply
    return %result, %x2 : !poly.poly<10>, !poly.poly<10>
  }

  // Test: Nested additions with constants
  // CHECK-LABEL: @combine_nested_adds
  func.func @combine_nested_adds() -> !poly.poly<10> {
    // CHECK: %[[C:.*]] = poly.constant dense<[3, 0, 0]>
    // CHECK: %[[X:.*]] = poly.from_tensor
    // CHECK: %[[RESULT:.*]] = poly.add %[[X]], %[[C]]
    // CHECK: return %[[RESULT]]

    %c1 = poly.constant dense<[1, 0, 0]> : !poly.poly<10>
    %c2 = poly.constant dense<[2, 0, 0]> : !poly.poly<10>
    %x = poly.from_tensor ... : tensor<10xi32> -> !poly.poly<10>

    %temp = poly.add %x, %c1 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %result = poly.add %temp, %c2 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    return %result : !poly.poly<10>
  }
}
```

### Running Tests

```powershell
# Run specific test
.\build\bin\tutorial-opt.exe .\tests\canonicalize.mlir --canonicalize

# Run with FileCheck
.\build\bin\tutorial-opt.exe .\tests\canonicalize.mlir --canonicalize | `
  FileCheck .\tests\canonicalize.mlir

# Run all tests
cd build
ninja check-mlir-tutorial
```

### Debugging Canonicalization

```powershell
# See what patterns apply
.\build\bin\tutorial-opt.exe test.mlir --canonicalize `
  --mlir-print-ir-after-all

# Show pattern matching details
.\build\bin\tutorial-opt.exe test.mlir --canonicalize `
  --debug-only=pattern-match

# Statistics
.\build\bin\tutorial-opt.exe test.mlir --canonicalize `
  --mlir-pass-statistics
```

## Canonicalization Pass Mechanics

### How Patterns Are Applied

The canonicalization pass:

1. **Collects patterns** from all operations
2. **Creates a driver** that applies patterns repeatedly
3. **Iterates until fixed point** (no more changes)
4. **Respects pattern benefits** (higher benefit = tried first)

### Pattern Benefits

Control application order:

```tablegen
// Higher benefit = applied first (default = 1)
def HighPriorityPattern : Pattern<
  ...,
  ...,
  ...,
  (addBenefit 10)  // Try this pattern first
>;

def LowPriorityPattern : Pattern<
  ...,
  ...,
  ...,
  (addBenefit 0)  // Try this pattern last
>;
```

**When to use:**
- **High benefit**: Patterns that enable other patterns
- **Low benefit**: Expensive patterns that should only run if others fail

### Preventing Infinite Loops

**Problem:**
```tablegen
// BAD: Can loop forever!
def PatternA : Pat<(OpX $a), (OpY $a)>;
def PatternB : Pat<(OpY $a), (OpX $a)>;
```

**Solutions:**

1. **Add constraints** to prevent reverse transformation:
```tablegen
def PatternA : Pattern<
  (OpX $a),
  (OpY $a),
  [(Constraint $a)]  // Only apply in specific cases
>;
```

2. **Use pattern benefits** to control order:
```tablegen
def PatternA : Pattern<..., (addBenefit 2)>;
def PatternB : Pattern<..., (addBenefit 1)>;
```

3. **Design patterns carefully** - Ensure they always make progress toward canonical form.

## Real-World Examples

### From MLIR's Arith Dialect

```tablegen
// x - x = 0
def SubSelf : Pat<
  (Arith_SubIOp $x, $x),
  (Arith_ConstantOp (GetZeroAttr $x))
>;

// (x + c1) + c2 = x + (c1 + c2)
def AddConstantConstant : Pattern<
  (Arith_AddIOp (Arith_AddIOp $x, (Arith_ConstantOp $c1)),
                (Arith_ConstantOp $c2)),
  (Arith_AddIOp $x, (Arith_ConstantOp (AddInts $c1, $c2)))
>;

// x * 1 = x
def MulOne : Pat<
  (Arith_MulIOp $x, (Arith_ConstantOp ConstantAttr<I64Attr, "1">)),
  $x
>;
```

### From MLIR's Tensor Dialect

```tablegen
// extract(from_elements(x, y, z), 0) = x
def ExtractFromElements : Pattern<
  (Tensor_ExtractOp
    (Tensor_FromElementsOp $elements),
    (Arith_ConstantOp:$idx $_)),
  (SelectFromArray $elements, $idx)
>;
```

## Common Patterns to Implement

### Algebraic Identities

```tablegen
// x + 0 = x
def AddZero : Pat<(Poly_AddOp $x, (Poly_ZeroConstant)), $x>;

// x * 1 = x
def MulOne : Pat<(Poly_MulOp $x, (Poly_OneConstant)), $x>;

// x * 0 = 0
def MulZero : Pat<
  (Poly_MulOp $x, (Poly_ZeroConstant:$zero)),
  $zero
>;

// x - x = 0
def SubSelf : Pat<
  (Poly_SubOp $x, $x),
  (Poly_ZeroConstant)
>;
```

### Associativity and Commutativity

```tablegen
// (x + y) + z = x + (y + z)
def ReassociateAdd : Pat<
  (Poly_AddOp (Poly_AddOp $x, $y), $z),
  (Poly_AddOp $x, (Poly_AddOp $y, $z))
>;

// Ensure constants on right: c + x → x + c
def NormalizeConstantOrder : Pat<
  (Poly_AddOp (Poly_ConstantOp:$c $_), $x),
  (Poly_AddOp $x, $c)
>;
```

### Strength Reduction

```tablegen
// x * 2 → x + x
def MulByTwoToAdd : Pat<
  (Poly_MulOp $x, (Poly_TwoConstant)),
  (Poly_AddOp $x, $x)
>;

// x / 1 → x
def DivByOne : Pat<
  (Poly_DivOp $x, (Poly_OneConstant)),
  $x
>;
```

## Best Practices

### Pattern Design

✅ **DO:**
- Make patterns move toward canonical form
- Use constraints to prevent infinite loops
- Test with multiple iterations
- Document why patterns help

❌ **DON'T:**
- Create reversible pattern pairs
- Apply expensive transformations unconditionally
- Ignore pattern benefits
- Forget to test edge cases

### Performance Considerations

**Pattern matching cost:**
- Complex patterns = slower compilation
- Many patterns = more overhead
- Deep DAG matching = expensive

**Optimization:**
```tablegen
// GOOD: Check cheap condition first
def OptimizedPattern : Pattern<
  (Op $x),
  ...,
  [(CheapConstraint $x), (ExpensiveConstraint $x)]  // Order matters!
>;
```

### Debugging Tips

1. **Start simple** - Add one pattern at a time
2. **Use FileCheck** - Verify expected transformations
3. **Enable debug output** - See pattern matching details
4. **Check generated code** - Ensure TableGen generates correct C++
5. **Test edge cases** - Empty inputs, single elements, etc.

## Key Takeaways

**Conceptual:**

✅ **Normal forms reduce combinatorial complexity** - Without canonicalization, every downstream pass must handle all possible equivalent representations. Canonicalization standardizes IR structure, transforming an N-way explosion into a single canonical path

✅ **Canonicalization is an optimization force multiplier** - By reducing the space of IR structures other passes must handle, it makes all subsequent optimizations exponentially more effective. This is reduction of complexity through standardization

✅ **Algebraic identities enforce structural uniformity** - Mathematical properties like $f(\overline{z}) = \overline{f(z)}$ (conjugation commutativity) can be encoded as canonicalization patterns, ensuring consistent IR structure across the program

✅ **Differs from folding in power and scope** - Folding is local and limited (cannot create operations). Canonicalization uses DAG-to-DAG rewriting to create/delete operations and restructure entire computation subgraphs. Jeremy notes: "Most work on simplifying an IR according to algebraic rules belongs in the canonicalization pass"

✅ **DRR reduces boilerplate but has expressivity limits** - Declarative TableGen patterns are concise but Jeremy candidly admits: "I don't know how to check a constraint like 'has a single use' in pure DRR tablegen," requiring C++ fallback. Additionally, "because you still occasionally need to inject random C++ code, and inspect the generated C++ to debug, it helps to be fluent in both styles"

✅ **DRR is in maintenance mode** - Jeremy notes DRR is "in maintenance mode, but not yet deprecated," with PDLL as the future direction (though "I haven't figured out how to use that yet"). This suggests the abstraction is evolving but not yet fully mature

✅ **Type system constraints can block valid patterns** - Jeremy discovered "Complex types are forced to be floating point because all the op verifiers...require it," preventing Gaussian integer support despite mathematical validity. Design decisions upstream ripple through canonicalization possibilities

✅ **Generated code opacity requires debugging skills** - Developers must "inspect the generated C++ to debug" DRR patterns, suggesting the abstraction leaks during development. This isn't fully declarative—it's declarative with imperative debugging

**Practical:**

✅ **Two complementary approaches** - C++ patterns (flexible, imperative, full control) vs DRR (concise, declarative, limited expressivity). Use DRR for simple patterns, C++ for complex constraints

✅ **Constraints control pattern application** - `HasOneUse`, `IsPowerOfTwo`, custom predicates determine when patterns fire safely

✅ **Pattern benefits control ordering** - Higher benefit patterns apply first, enabling precise control over optimization sequences

✅ **Infinite loops require careful design** - Patterns can trigger each other endlessly without proper constraints (mutual triggering prevention)

✅ **CMake integration via mlir_tablegen** - Generate rewriters with `-gen-rewriters` flag, linking pattern definitions to dialect implementation

## Next Steps

1. **[Tutorial 10: Dialect Conversion](10-dialect-conversion.md)** - Convert between dialects systematically
2. **Implement canonicalization patterns** for your dialect operations
3. **Study MLIR source** - See patterns in `mlir/lib/Dialect/Arith/IR/ArithCanonicalization.td`
4. **Experiment** with different constraint combinations
5. **Profile** pattern matching performance

## Additional Resources

- **MLIR Canonicalization:** [mlir.llvm.org/docs/Canonicalization/](https://mlir.llvm.org/docs/Canonicalization/)
- **Pattern Rewriting:** [mlir.llvm.org/docs/PatternRewriter/](https://mlir.llvm.org/docs/PatternRewriter/)
- **DRR Documentation:** [mlir.llvm.org/docs/DeclarativeRewrites/](https://mlir.llvm.org/docs/DeclarativeRewrites/)
- **TableGen Backend:** [mlir.llvm.org/docs/OpDefinitions/#tablegen-syntax](https://mlir.llvm.org/docs/OpDefinitions/#tablegen-syntax)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/09/20/mlir-canonicalizers-and-declarative-rewrite-patterns/)

---

**Previous:** [← Tutorial 08: Verifiers](08-verifiers.md)
**Next:** [Tutorial 10: Dialect Conversion →](10-dialect-conversion.md)
