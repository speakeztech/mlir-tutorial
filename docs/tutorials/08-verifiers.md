# Tutorial 08: Verifiers

**Original Article:** [MLIR — Verifiers](https://jeremykun.com/2023/09/13/mlir-verifiers/) by Jeremy Kun

**Windows Adaptation:** Focus on verification mechanisms with CMake build integration.

---

## 📖 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 What You'll Learn

- Understanding **verification** in MLIR's architecture
- Using **built-in verification traits**
- Implementing **custom operation verifiers**
- Creating **reusable verification traits**
- Understanding **when verification runs**
- Debugging **verification failures**

## Verification as Communication

Here's an uncomfortable truth about compiler development: **most compiler bugs aren't logic errors—they're assumption violations**.

You write a pass assuming operations have certain properties. Maybe you assume operand types match. Maybe you assume degree bounds are consistent. Maybe you assume control flow is well-structured.

Then someone runs your pass on IR that violates those assumptions. Your pass crashes. Or worse—it silently produces wrong code. You spend hours debugging only to discover: "Oh, I was assuming the input was X, but it was actually Y."

**Verification makes assumptions explicit.** Instead of implicit expectations that might be violated, you write verifiers that check and enforce them. Verification isn't just error-catching—it's **documentation that executes**.

### The Philosophy: Fail Fast, Fail Clearly

**Fail fast** means catching errors immediately when they occur, not three passes later when the context is lost.

**Fail clearly** means error messages that explain what's wrong and where, not cryptic assertion failures.

Consider this progression:

**No verification:**
```
Parse → Transform → Transform → Transform → CRASH
                                           ↑
                         Where did the bug come from?
```

**With verification:**
```
Parse → Verify → Transform → Verify → ERROR: "poly.add requires same degree bounds"
                             ↑
                    Caught immediately with context!
```

The verification failure tells you:
1. **What failed** - Which operation or constraint
2. **Why it failed** - What property was violated
3. **Where it failed** - Location in the IR
4. **When it failed** - Which pass produced invalid IR

This is **communication to future developers** (including yourself). When verification fails, it's saying: "You've violated this contract. Here's what you need to fix."

### Verification is Economic

Every minute spent writing verifiers saves hours of debugging.

**Without verifiers:**
- Bugs are discovered late (after multiple transformations)
- Root cause is unclear (which pass broke what?)
- Debugging requires understanding entire pipeline
- Fixes are uncertain (did I actually solve it?)

**With verifiers:**
- Bugs are discovered immediately (right after the offending pass)
- Root cause is clear (this pass violated this property)
- Debugging is local (just look at that one pass)
- Fixes are confident (verification now passes)

**The investment:** 10 minutes to write a verifier.
**The return:** Potentially hours saved on every future bug.

This is leverage—verifiers pay dividends throughout the project's lifetime.

### When Verification Runs

**Automatically:**
1. **After parsing** - Ensure input is valid
2. **Before each pass** - Verify preconditions
3. **After each pass** - Verify pass didn't break IR
4. **Before output** - Ensure final IR is valid

**Manually:**
```powershell
# Explicit verification
.\build\bin\tutorial-opt.exe input.mlir --verify-each

# Without verification (dangerous!)
.\build\bin\tutorial-opt.exe input.mlir --disable-verify
```

## Built-in Verification Traits

MLIR provides traits that automatically generate verification logic.

### SameOperandsAndResultType

Ensures all operands and results have the same type.

#### Example: Comparison Operation

```tablegen
def Poly_CmpOp : Poly_Op<"cmp", [SameOperandsAndResultType]> {
  let summary = "Compare two polynomials for equality";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs I1:$result);
}
```

**Generated verification:**
```cpp
LogicalResult CmpOp::verify() {
  // Check that all operands and result have same type
  Type lhsType = getLhs().getType();
  Type rhsType = getRhs().getType();
  Type resultType = getResult().getType();

  if (lhsType != rhsType || rhsType != resultType) {
    return emitOpError("requires all operands and results to have same type");
  }

  return success();
}
```

**Valid:**
```mlir
%cmp = poly.cmp %a, %b : (!poly.poly<10>, !poly.poly<10>) -> i1
```

**Invalid:**
```mlir
// Error: mismatched degree bounds
%cmp = poly.cmp %a, %b : (!poly.poly<10>, !poly.poly<20>) -> i1
```

### SameOperandsAndResultElementType

More flexible variant - only checks element types, allowing different container shapes.

```tablegen
def Poly_AddOp : Poly_Op<"add", [
    Pure,
    ElementwiseMappable,
    SameOperandsAndResultElementType
  ]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
}
```

**Valid (same element type):**
```mlir
// Scalars
%r1 = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

// Tensors
%r2 = poly.add %x, %y : (tensor<5x!poly.poly<10>>, tensor<5x!poly.poly<10>>)
                      -> tensor<5x!poly.poly<10>>

// Mixed (broadcasting)
%r3 = poly.add %a, %x : (!poly.poly<10>, tensor<5x!poly.poly<10>>)
                      -> tensor<5x!poly.poly<10>>
```

**Invalid (different element types):**
```mlir
// Error: element type mismatch (!poly.poly<10> vs !poly.poly<20>)
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<20>) -> !poly.poly<10>
```

### SameOperandsAndResultShape

Ensures operands and results have the same container shape.

```tablegen
def Poly_ElementwiseOp : Poly_Op<"elementwise", [
    SameOperandsAndResultShape,
    SameOperandsAndResultElementType
  ]> {
  let arguments = (ins Polynomial:$input);
  let results = (outs Polynomial:$output);
}
```

**Valid:**
```mlir
%r = poly.elementwise %x : tensor<10x20x!poly.poly<5>> -> tensor<10x20x!poly.poly<5>>
```

**Invalid:**
```mlir
// Error: shape mismatch
%r = poly.elementwise %x : tensor<10x20x!poly.poly<5>> -> tensor<20x10x!poly.poly<5>>
```

### InferTypeOpInterface

Automatically infers result types, simplifying syntax and adding verification.

```tablegen
def Poly_AddOp : Poly_Op<"add", [
    Pure,
    SameOperandsAndResultType,
    DeclareOpInterfaceMethods<InferTypeOpInterface>
  ]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
}
```

**Implementation:**
```cpp
LogicalResult AddOp::inferReturnTypes(
    MLIRContext *context,
    Optional<Location> location,
    ValueRange operands,
    DictionaryAttr attributes,
    RegionRange regions,
    SmallVectorImpl<Type> &inferredReturnTypes) {

  // Result type is the same as operand type
  inferredReturnTypes.push_back(operands[0].getType());
  return success();
}
```

**Benefit - Shorter syntax:**
```mlir
// Before: must specify result type
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

// After: result type inferred
%r = poly.add %a, %b : !poly.poly<10>
```

## Custom Operation Verifiers

For dialect-specific constraints, implement custom verifiers.

### Example: Eval Operation

The `poly.eval` operation evaluates a polynomial at a point. We want to ensure the point is a 32-bit integer.

#### TableGen Definition

```tablegen
def Poly_EvalOp : Poly_Op<"eval", [Pure]> {
  let summary = "Evaluate a polynomial at a point";

  let description = [{
    Evaluates a polynomial at a specific integer point using Horner's method.

    The point must be a 32-bit signed integer.

    Example:
      %result = poly.eval %p at %x : (!poly.poly<10>, i32) -> i32
  }];

  let arguments = (ins Polynomial:$polynomial, I32:$point);
  let results = (outs I32:$output);

  let assemblyFormat = [{
    $polynomial `at` $point attr-dict `:` `(` type($polynomial) `,` type($point) `)` `->` type($output)
  }];

  // Enable custom verifier
  let hasVerifier = 1;
}
```

#### C++ Implementation

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
LogicalResult EvalOp::verify() {
  // Check that point is i32
  Type pointType = getPoint().getType();

  if (!pointType.isInteger(32)) {
    return emitOpError("requires point to be a 32-bit integer, got ")
           << pointType;
  }

  // Check that result is i32
  Type resultType = getOutput().getType();

  if (!resultType.isInteger(32)) {
    return emitOpError("requires result to be a 32-bit integer, got ")
           << resultType;
  }

  return success();
}
```

#### Testing the Verifier

**Valid:**
```mlir
func.func @valid_eval(%p: !poly.poly<10>, %x: i32) -> i32 {
  %result = poly.eval %p at %x : (!poly.poly<10>, i32) -> i32
  return %result : i32
}
```

**Invalid:**
```mlir
func.func @invalid_eval(%p: !poly.poly<10>, %x: i64) -> i32 {
  // Error: point must be i32, got i64
  %result = poly.eval %p at %x : (!poly.poly<10>, i64) -> i32
  return %result : i32
}
```

**Run verification:**
```powershell
# Should succeed
.\build\bin\tutorial-opt.exe valid_eval.mlir

# Should fail with error message
.\build\bin\tutorial-opt.exe invalid_eval.mlir
```

### Example: Degree Bound Verification

Verify that polynomial operands have matching degree bounds.

```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let hasVerifier = 1;
}
```

```cpp
LogicalResult AddOp::verify() {
  // Get polynomial types
  auto lhsType = getLhs().getType().cast<PolynomialType>();
  auto rhsType = getRhs().getType().cast<PolynomialType>();
  auto resultType = getOutput().getType().cast<PolynomialType>();

  // Check degree bounds match
  int lhsBound = lhsType.getDegreeBound();
  int rhsBound = rhsType.getDegreeBound();
  int resultBound = resultType.getDegreeBound();

  if (lhsBound != rhsBound || rhsBound != resultBound) {
    return emitOpError("requires all operands to have the same degree bound, got ")
           << lhsBound << ", " << rhsBound << ", and " << resultBound;
  }

  // Verify degree bounds are positive
  if (lhsBound <= 0) {
    return emitOpError("requires positive degree bound, got ") << lhsBound;
  }

  return success();
}
```

**Valid:**
```mlir
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
```

**Invalid:**
```mlir
// Error: degree bound mismatch (10 vs 20)
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<20>) -> !poly.poly<10>
```

### Example: Constant Coefficient Count

Verify that constant operations have the right number of coefficients.

```tablegen
def Poly_ConstantOp : Poly_Op<"constant", [Pure, ConstantLike]> {
  let summary = "Define a constant polynomial";
  let arguments = (ins DenseIntElementsAttr:$coefficients);
  let results = (outs Polynomial:$output);

  let hasVerifier = 1;
}
```

```cpp
LogicalResult ConstantOp::verify() {
  // Get the polynomial type
  auto polyType = getOutput().getType().cast<PolynomialType>();
  int degreeBound = polyType.getDegreeBound();

  // Get the coefficient attribute
  auto coeffsAttr = getCoefficients();
  int numCoeffs = coeffsAttr.size();

  // Verify coefficient count doesn't exceed degree bound
  if (numCoeffs > degreeBound) {
    return emitOpError("has ")
           << numCoeffs << " coefficients, but degree bound is "
           << degreeBound;
  }

  // Verify at least one coefficient
  if (numCoeffs == 0) {
    return emitOpError("requires at least one coefficient");
  }

  return success();
}
```

**Valid:**
```mlir
// 3 coefficients, degree bound 10
%p = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
```

**Invalid:**
```mlir
// Error: 12 coefficients exceeds degree bound 10
%p = poly.constant dense<[1,2,3,4,5,6,7,8,9,10,11,12]> : !poly.poly<10>
```

## Custom Reusable Traits

For verification logic used across multiple operations, create custom traits.

### Defining a Custom Trait

**File: `lib/Dialect/Poly/PolyTraits.td`**

```tablegen
#ifndef LIB_DIALECT_POLY_POLYTRAITS_TD
#define LIB_DIALECT_POLY_POLYTRAITS_TD

include "mlir/IR/OpBase.td"

// Trait: All integer operands must be 32-bit
def Has32BitIntegerOperands : NativeOpTrait<"Has32BitIntegerOperands">;

// Trait: All polynomial operands must have the same degree bound
def SameDegreeBound : NativeOpTrait<"SameDegreeBound">;

#endif // LIB_DIALECT_POLY_POLYTRAITS_TD
```

### Implementing the Trait

**File: `lib/Dialect/Poly/PolyTraits.h`**

```cpp
#ifndef LIB_DIALECT_POLY_POLYTRAITS_H
#define LIB_DIALECT_POLY_POLYTRAITS_H

#include "mlir/IR/OpDefinition.h"
#include "Dialect/Poly/PolyTypes.h"

namespace mlir {
namespace tutorial {
namespace poly {
namespace OpTrait {

//===----------------------------------------------------------------------===//
// Has32BitIntegerOperands
//===----------------------------------------------------------------------===//

template <typename ConcreteType>
class Has32BitIntegerOperands
    : public TraitBase<ConcreteType, Has32BitIntegerOperands> {
public:
  static LogicalResult verifyTrait(Operation *op) {
    // Check all operands
    for (Value operand : op->getOperands()) {
      Type type = operand.getType();

      // Skip non-integer types
      if (!type.isIntOrIndex())
        continue;

      // Verify it's 32-bit
      if (!type.isInteger(32)) {
        return op->emitOpError("requires all integer operands to be 32-bit, got ")
               << type;
      }
    }

    return success();
  }
};

//===----------------------------------------------------------------------===//
// SameDegreeBound
//===----------------------------------------------------------------------===//

template <typename ConcreteType>
class SameDegreeBound : public TraitBase<ConcreteType, SameDegreeBound> {
public:
  static LogicalResult verifyTrait(Operation *op) {
    int degreeBound = -1;

    // Check all operands
    for (Value operand : op->getOperands()) {
      auto polyType = operand.getType().dyn_cast<PolynomialType>();
      if (!polyType)
        continue; // Skip non-polynomial types

      int bound = polyType.getDegreeBound();

      if (degreeBound == -1) {
        // First polynomial - set the degree bound
        degreeBound = bound;
      } else if (bound != degreeBound) {
        // Mismatch found
        return op->emitOpError("requires all polynomial operands to have ")
               << "the same degree bound, got " << degreeBound
               << " and " << bound;
      }
    }

    // Check all results
    for (Value result : op->getResults()) {
      auto polyType = result.getType().dyn_cast<PolynomialType>();
      if (!polyType)
        continue;

      int bound = polyType.getDegreeBound();

      if (degreeBound == -1) {
        degreeBound = bound;
      } else if (bound != degreeBound) {
        return op->emitOpError("requires all polynomial results to have ")
               << "the same degree bound as operands, got " << degreeBound
               << " and " << bound;
      }
    }

    return success();
  }
};

} // namespace OpTrait
} // namespace poly
} // namespace tutorial
} // namespace mlir

#endif // LIB_DIALECT_POLY_POLYTRAITS_H
```

### Using Custom Traits

**File: `lib/Dialect/Poly/PolyOps.td`**

```tablegen
include "PolyTraits.td"

def Poly_AddOp : Poly_Op<"add", [
    Pure,
    Commutative,
    SameDegreeBound  // Custom trait!
  ]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
}

def Poly_EvalOp : Poly_Op<"eval", [
    Pure,
    Has32BitIntegerOperands  // Custom trait!
  ]> {
  let summary = "Evaluate a polynomial at a point";
  let arguments = (ins Polynomial:$polynomial, I32:$point);
  let results = (outs I32:$output);
}
```

### Benefits of Custom Traits

✅ **Reusability** - Write once, use everywhere
✅ **Composability** - Combine multiple traits
✅ **Documentation** - Trait name self-documents constraint
✅ **Maintainability** - Change logic in one place

## Verification Error Messages

Good error messages are crucial for usability.

### Bad Error Messages

```cpp
❌ return emitOpError("invalid");
❌ return emitOpError("type mismatch");
❌ return emitOpError("error in operation");
```

### Good Error Messages

```cpp
✅ return emitOpError("requires point to be a 32-bit integer, got ") << type;

✅ return emitOpError("has ") << numCoeffs
         << " coefficients, but degree bound is " << degreeBound;

✅ return emitOpError("requires all polynomial operands to have ")
         << "the same degree bound, got " << lhsBound
         << " and " << rhsBound;
```

### Best Practices

1. **Be specific** - Say what's wrong
2. **Show values** - Include actual types/values encountered
3. **Suggest fix** - Hint at what's expected
4. **Use consistent format** - Follow MLIR conventions

### Example: Comprehensive Error Message

```cpp
LogicalResult FmaOp::verify() {
  // Fused multiply-add: fma(a, b, c) = a*b + c

  auto aType = getA().getType().cast<PolynomialType>();
  auto bType = getB().getType().cast<PolynomialType>();
  auto cType = getC().getType().cast<PolynomialType>();
  auto resultType = getResult().getType().cast<PolynomialType>();

  int aBound = aType.getDegreeBound();
  int bBound = bType.getDegreeBound();
  int cBound = cType.getDegreeBound();
  int resultBound = resultType.getDegreeBound();

  if (aBound != bBound || bBound != cBound || cBound != resultBound) {
    return emitOpError()
           << "requires all operands and result to have the same degree bound\n"
           << "  operand 'a' has degree bound: " << aBound << "\n"
           << "  operand 'b' has degree bound: " << bBound << "\n"
           << "  operand 'c' has degree bound: " << cBound << "\n"
           << "  result has degree bound: " << resultBound << "\n"
           << "  expected all degree bounds to match";
  }

  return success();
}
```

**Output when verification fails:**
```
error: 'poly.fma' op requires all operands and result to have the same degree bound
  operand 'a' has degree bound: 10
  operand 'b' has degree bound: 20
  operand 'c' has degree bound: 10
  result has degree bound: 10
  expected all degree bounds to match
```

## CMake Integration

Verifiers are part of operation definitions - no special CMake configuration needed.

### File: `lib/Dialect/Poly/CMakeLists.txt`

```cmake
# Generate operations (includes verifier hooks)
set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

# Build library with verifier implementations
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp  # Contains verify() implementations

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/Dialect/Poly

  DEPENDS
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
)
```

### Build and Test

```powershell
cd D:\repos\mlir-tutorial\build
ninja MLIRPoly

# Test verification (should succeed)
.\bin\tutorial-opt.exe ..\tests\valid.mlir

# Test verification (should fail)
.\bin\tutorial-opt.exe ..\tests\invalid.mlir
```

## Testing Verifiers

Create comprehensive tests for verification logic.

### File: `tests/poly_verify.mlir`

```mlir
// RUN: tutorial-opt %s -split-input-file -verify-diagnostics

// -----
// Test: Valid eval operation
func.func @valid_eval(%p: !poly.poly<10>, %x: i32) -> i32 {
  %result = poly.eval %p at %x : (!poly.poly<10>, i32) -> i32
  return %result : i32
}

// -----
// Test: Invalid eval - wrong point type
func.func @invalid_eval_point(%p: !poly.poly<10>, %x: i64) -> i32 {
  // expected-error @+1 {{requires point to be a 32-bit integer}}
  %result = poly.eval %p at %x : (!poly.poly<10>, i64) -> i32
  return %result : i32
}

// -----
// Test: Invalid eval - wrong result type
func.func @invalid_eval_result(%p: !poly.poly<10>, %x: i32) -> i64 {
  // expected-error @+1 {{requires result to be a 32-bit integer}}
  %result = poly.eval %p at %x : (!poly.poly<10>, i32) -> i64
  return %result : i64
}

// -----
// Test: Valid add operation
func.func @valid_add(%a: !poly.poly<10>, %b: !poly.poly<10>) -> !poly.poly<10> {
  %result = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %result : !poly.poly<10>
}

// -----
// Test: Invalid add - degree bound mismatch
func.func @invalid_add_bounds(%a: !poly.poly<10>, %b: !poly.poly<20>) -> !poly.poly<10> {
  // expected-error @+1 {{requires all operands to have the same degree bound}}
  %result = poly.add %a, %b : (!poly.poly<10>, !poly.poly<20>) -> !poly.poly<10>
  return %result : !poly.poly<10>
}

// -----
// Test: Valid constant
func.func @valid_constant() -> !poly.poly<10> {
  %p = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
  return %p : !poly.poly<10>
}

// -----
// Test: Invalid constant - too many coefficients
func.func @invalid_constant_size() -> !poly.poly<5> {
  // expected-error @+1 {{has 10 coefficients, but degree bound is 5}}
  %p = poly.constant dense<[1,2,3,4,5,6,7,8,9,10]> : !poly.poly<5>
  return %p : !poly.poly<5>
}
```

### Running Tests

```powershell
# Run with lit (if configured)
cd D:\repos\mlir-tutorial\build
ninja check-mlir-tutorial

# Manual test with FileCheck
.\bin\tutorial-opt.exe ..\tests\poly_verify.mlir -split-input-file -verify-diagnostics
```

## Debugging Verification Failures

### Enable Verbose Diagnostics

```powershell
# Show detailed error location
.\build\bin\tutorial-opt.exe test.mlir --verify-diagnostics

# Show IR before verification fails
.\build\bin\tutorial-opt.exe test.mlir --mlir-print-ir-before-all
```

### Add Debug Output

```cpp
LogicalResult AddOp::verify() {
  llvm::errs() << "Verifying AddOp:\n";
  this->dump();

  auto lhsType = getLhs().getType().cast<PolynomialType>();
  auto rhsType = getRhs().getType().cast<PolynomialType>();

  llvm::errs() << "  LHS degree bound: " << lhsType.getDegreeBound() << "\n";
  llvm::errs() << "  RHS degree bound: " << rhsType.getDegreeBound() << "\n";

  // ... verification logic ...
}
```

### Common Issues

**Issue: Verification passes but IR is malformed**

**Cause:** Verifier logic is incomplete

**Solution:** Add more checks, test edge cases

**Issue: False positives (valid IR rejected)**

**Cause:** Verifier logic is too strict

**Solution:** Review constraints, allow valid cases

**Issue: Unclear error messages**

**Cause:** Generic error text

**Solution:** Include actual values in error messages

## Advanced Verification

### Region Verification

For operations with regions (like functions):

```cpp
LogicalResult FuncOp::verify() {
  // Verify function signature matches body
  Region &body = getBody();

  if (body.empty())
    return emitOpError("requires non-empty body");

  Block &entryBlock = body.front();

  if (entryBlock.getNumArguments() != getNumInputs()) {
    return emitOpError("entry block has ")
           << entryBlock.getNumArguments()
           << " arguments, but function signature has "
           << getNumInputs() << " inputs";
  }

  return success();
}
```

### Attribute Verification

For operations with complex attributes:

```cpp
LogicalResult ConstantOp::verify() {
  auto coeffsAttr = getCoefficients();

  // Verify attribute type
  if (!coeffsAttr.getElementType().isInteger(32)) {
    return emitOpError("requires coefficients to be 32-bit integers, got ")
           << coeffsAttr.getElementType();
  }

  // Verify attribute shape
  if (coeffsAttr.getType().getRank() != 1) {
    return emitOpError("requires 1D coefficient array, got ")
           << coeffsAttr.getType().getRank() << "D";
  }

  return success();
}
```

## Key Takeaways

**Conceptual:**

✅ **Verification makes assumptions executable** - Instead of implicit expectations that might be violated, verifiers check and enforce them. This transforms assumptions from informal documentation into runtime checks, creating a contract between IR representation and passes that transform it

✅ **Fail fast, fail clearly is foundational** - Catch errors immediately with informative messages (`emitOpError`), not three passes later with cryptic failures. Jeremy notes that "if you just return failure, then the verifier will fail but not output any information," making `emitOpError` mandatory for clarity

✅ **Verification is economic leverage** - 10 minutes writing a verifier saves hours of debugging throughout the project's lifetime. By enforcing invariants through verification, "passes [can be] simpler because they can rely on the invariants to avoid edge case checking." This is investment that reduces downstream complexity

✅ **Strictness vs flexibility is a deliberate trade-off** - Jeremy's tutorial demonstrates progression from `SameOperandsAndResultElementType` (flexible, allowed mixed poly/tensor semantics) to `SameOperandsAndResultType` (strict, uniform types). This choice involves "reducing expressiveness to gain stronger guarantees"—accepting constraints on programs to gain confidence in transformations

✅ **Verification enables conciseness elsewhere** - Once type inference is available through traits, assembly format can be "simplified...so that the type need only be specified once instead of three times." Verification investments pay off in improved developer experience

✅ **Most bugs are assumption violations** - Not logic errors in pass implementation, but violated expectations about IR properties (operand types match, degree bounds consistent, control flow well-structured)

✅ **Nomenclature and implementation have friction** - Jeremy's honest assessment: the verification nomenclature "is a bit confusing," custom trait verification requires "awkward casting to support specific ops," and MLIR documentation claims about "traits as subclasses of a Constraint base class" are "wrong" (as of 2023). Even mature systems contain rough edges

**Practical:**

✅ **Layered verification granularity** - Trait-based (automatic), operation-specific (custom verifiers), generic trait-based (cross-cutting concerns like `Has32BitArguments`)

✅ **Built-in traits generate verifiers** - `SameOperandsAndResultType`, `SameOperandsAndResultElementType` enforce type consistency automatically

✅ **Custom verifiers enforce domain constraints** - Dialect-specific invariants beyond what traits can express

✅ **Custom traits enable reuse** - Write verification logic once, apply to many operations (though with "awkward casting" for named arguments)

✅ **Verification runs automatically** - Before and after each pass, creating checkpoints where transformations cannot silently corrupt representation

✅ **Testing requires negative cases** - Use `-verify-diagnostics` to test error paths and ensure verifiers catch violations

## Next Steps

1. **Add verifiers** to all your custom operations
2. **Create custom traits** for common verification patterns
3. **Write comprehensive tests** with `-verify-diagnostics`
4. **Study** MLIR's built-in verifiers for patterns and techniques

## Additional Resources

- **MLIR Verification:** [mlir.llvm.org/docs/Diagnostics/](https://mlir.llvm.org/docs/Diagnostics/)
- **OpBase.td Traits:** `C:\msys64\mingw64\include\mlir\IR\OpBase.td`
- **Testing with verify-diagnostics:** [mlir.llvm.org/docs/TestingGuide/](https://mlir.llvm.org/docs/TestingGuide/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/09/13/mlir-verifiers/)

---

**Previous:** [← Tutorial 07: Folders and Constant Propagation](07-folders-constant-propagation.md)

**Congratulations!** You've completed the core MLIR dialect tutorial series. You now understand:
- Dialect and type definitions
- Operation traits and their power
- Constant folding mechanisms
- Verification for correctness

Continue exploring MLIR's advanced features like pattern rewriting, dialect conversion, and custom passes!
