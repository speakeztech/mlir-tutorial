# Tutorial 06: Using Traits

**Original Article:** [MLIR — Using Traits](https://jeremykun.com/2023/09/07/mlir-using-traits/) by Jeremy Kun

**Windows Adaptation:** Focus on trait concepts and implementation with CMake integration.

---

## 📖 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Advanced features and detailed analysis
- **👉 Action sections** - Commands to run and tasks to complete

---

## 📖 What You'll Learn

- Understanding **operation traits** in MLIR
- Using **built-in traits** to enable optimizations
- Implementing **Pure** and **ElementwiseMappable** traits
- Understanding **memory effect modeling**
- Enabling **speculative execution** for operations
- How traits unlock **general-purpose compiler passes**

## Traits: Inverting the Optimization Burden

When you define a custom dialect, there's a traditional problem: **how do you get existing compiler infrastructure to work with your new operations?**

The naive answer: write custom passes for every optimization. Want common subexpression elimination? Write a custom CSE pass for your dialect. Want loop invariant code motion? Write custom LICM logic. Want dead code elimination? More custom code.

This doesn't scale. Every dialect reimplements the same optimizations in slightly different ways. Code duplication explodes. Maintenance becomes a nightmare.

**Traits invert this burden.**

### The Architectural Insight

Rather than making **passes** know about your dialect, you make **your dialect** declare properties that passes already understand.

**Traditional approach (passes query operations):**
```
Pass: "Is this a polynomial addition?"
Operation: "Yes, I'm poly.add"
Pass: "Can I eliminate you if you're unused?"
Operation: "Um... let me check my semantics..."
```

**Trait-based approach (operations declare contracts):**
```
Operation: "I'm Pure—no side effects, deterministic, safe to speculate"
Pass: "Perfect, I can eliminate you, hoist you, deduplicate you"
```

The pass doesn't need to know what `poly.add` is. It only needs to know that `poly.add` is Pure. The **trait is a contract**—a zero-method interface that declares behavioral properties.

### The Real Example: From Zero to Full Optimization

You write this single line in TableGen:
```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure]> {
  let summary = "Addition operation";
  // ...
}
```

That `[Pure]` declaration unlocks:
- **Common Subexpression Elimination** - Duplicate operations eliminated
- **Dead Code Elimination** - Unused results removed
- **Loop Invariant Code Motion** - Computations hoisted out of loops
- **Control Flow Sinking** - Operations moved to where they're needed
- **Speculative Execution** - Operations executed before knowing if result is used
- **Register Allocation** - Optimizers know there are no hidden dependencies

**Zero additional code.** No custom passes. No dialect-specific logic. Just one word: `Pure`.

### Why This Matters: The Economics of Compiler Infrastructure

Consider the economics. LLVM/MLIR has hundreds of optimization passes developed over decades by thousands of engineers. These passes encode sophisticated algorithms—polyhedral optimization, value numbering, dataflow analysis, alias analysis, instruction scheduling.

Without traits, your custom dialect can't access this infrastructure. You'd need to:
1. Understand each optimization algorithm
2. Reimplement it for your dialect
3. Test it thoroughly
4. Maintain it as your dialect evolves
5. Repeat for every pass you want

With traits, you:
1. Mark your operations with standard properties
2. Inherit decades of optimization work

This is **leverage**. You're not building a compiler from scratch—you're plugging into existing infrastructure by declaring conformance to known contracts.

## What Are Traits?

**Traits are mixins** - composable pieces of behavior attached to operations.

### Conceptual Model

Think of traits as interfaces, but simpler:

**Interface (heavy):**
```cpp
class Printable {
  virtual void print() = 0;  // Must implement method
};
```

**Trait (lightweight):**
```cpp
class Pure : public Trait {
  // No methods to implement!
  // Just declares a property
};
```

### How Traits Work

1. **You declare** traits in TableGen
2. **TableGen generates** C++ code that mixes the trait into your operation
3. **Passes query** operations for traits
4. **Behavior adapts** based on which traits are present

## Essential Trait: Pure

The `Pure` trait is the most important trait you'll use.

### What Pure Means

An operation is **Pure** if:
1. It has **no side effects** (doesn't modify memory)
2. It's **deterministic** (same inputs → same outputs)
3. It can be **safely speculated** (safe to execute speculatively)

### Why Pure Matters

Pure operations can be:
- **Moved** (reordered in execution)
- **Eliminated** (if result unused)
- **Deduplicated** (CSE)
- **Hoisted** (moved out of loops)

### Example: Polynomial Operations

All polynomial arithmetic operations are pure:

```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
  // ...
}

def Poly_MulOp : Poly_Op<"mul", [Pure]> {
  let summary = "Multiplication operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
  // ...
}
```

### What Pure Actually Enables

#### 1. Common Subexpression Elimination (CSE)

**Before:**
```mlir
func.func @duplicate_computation(%p: !poly.poly<10>) -> !poly.poly<10> {
  %0 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  %1 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  %2 = poly.add %0, %1 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %2 : !poly.poly<10>
}
```

**After CSE pass:**
```mlir
func.func @duplicate_computation(%p: !poly.poly<10>) -> !poly.poly<10> {
  %0 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  // %1 eliminated - reuse %0
  %2 = poly.add %0, %0 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %2 : !poly.poly<10>
}
```

Run it:
```powershell
.\build\bin\tutorial-opt.exe test.mlir --cse
```

#### 2. Loop Invariant Code Motion (LICM)

**Before:**
```mlir
func.func @loop_with_invariant(%p: !poly.poly<10>, %n: index) -> !poly.poly<10> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %result = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %p) -> !poly.poly<10> {
    // This is loop invariant - doesn't depend on %i
    %squared = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %sum = poly.add %acc, %squared : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    scf.yield %sum : !poly.poly<10>
  }
  return %result : !poly.poly<10>
}
```

**After LICM pass:**
```mlir
func.func @loop_with_invariant(%p: !poly.poly<10>, %n: index) -> !poly.poly<10> {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  // Hoisted outside loop!
  %squared = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  %result = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %p) -> !poly.poly<10> {
    %sum = poly.add %acc, %squared : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    scf.yield %sum : !poly.poly<10>
  }
  return %result : !poly.poly<10>
}
```

Run it:
```powershell
.\build\bin\tutorial-opt.exe test.mlir --loop-invariant-code-motion
```

#### 3. Dead Code Elimination (DCE)

**Before:**
```mlir
func.func @unused_computation(%p: !poly.poly<10>) -> !poly.poly<10> {
  %0 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  %1 = poly.add %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  // %0 is never used!
  return %1 : !poly.poly<10>
}
```

**After DCE pass:**
```mlir
func.func @unused_computation(%p: !poly.poly<10>) -> !poly.poly<10> {
  // %0 eliminated
  %1 = poly.add %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %1 : !poly.poly<10>
}
```

Run it:
```powershell
.\build\bin\tutorial-opt.exe test.mlir --canonicalize
```

### Understanding Pure: The Dual Contract

The `Pure` trait is actually a combination of two traits:

```cpp
// In MLIR source code
def Pure : TraitList<[NoMemoryEffect, AlwaysSpeculatable]>;
```

This dual nature is important—it's not just about memory, it's about **safety guarantees** for aggressive optimization.

#### NoMemoryEffect: The Memory Contract

Declares the operation doesn't:
- Read from memory (no load operations)
- Write to memory (no store operations)
- Have observable side effects (no I/O, no global state modification)

```cpp
// Generated for Pure operations
void getEffects(SmallVectorImpl<SideEffects::Effect> &effects) {
  // Empty - no effects!
}
```

**Why memory effects matter:**

Operations that touch memory have ordering constraints. Consider:

```mlir
%addr = ... : memref<i32>
memref.store %val1, %addr : memref<i32>
%result = memref.load %addr : memref<i32>
```

The load **must** happen after the store. If a pass reordered them, the program would read stale data. Memory effects model these dependencies.

When an operation declares `NoMemoryEffect`, it's asserting: "I don't participate in memory ordering." Passes can reorder, eliminate, or duplicate it without breaking program semantics.

#### AlwaysSpeculatable: The Safety Contract

Declares the operation is:
- **Safe to execute early** - Before knowing if result is needed
- **Won't crash** - No null pointer dereferences, divide-by-zero, etc.
- **Won't hang** - Terminates in bounded time
- **No observable effects** - Executing it speculatively doesn't change program behavior

**Why speculatability matters:**

Some operations are memory-safe but still dangerous to execute speculatively:

```mlir
// Not speculatable - might divide by zero
%result = arith.divsi %a, %b : i32

// Not speculatable - might access invalid memory
%result = memref.load %ptr : memref<i32>

// Not speculatable - has observable side effects
func.call @print(%msg) : (i32) -> ()
```

Even if an operation doesn't touch memory, it might crash or have effects that make early execution wrong. `AlwaysSpeculatable` asserts: "It's safe to execute me whenever."

#### The Combination: Pure = NoMemoryEffect + AlwaysSpeculatable

Together, these traits say:
1. "I don't touch memory" (NoMemoryEffect)
2. "I'm safe to run anytime" (AlwaysSpeculatable)

This combination unlocks **maximum optimization freedom**. Passes can:
- Move the operation anywhere (no memory dependencies)
- Execute it speculatively (safe to run early)
- Duplicate it (no side effects to worry about)
- Eliminate it (if result unused, has no effect)

**Polynomial operations are Pure because:**
- They compute on SSA values, not memory
- They're deterministic (same inputs → same outputs)
- They can't fail (no division, no memory access)
- They have no effects beyond producing a result

This makes them ideal candidates for aggressive optimization.

### When NOT to Use Pure

**Don't use Pure for:**

❌ **I/O operations:**
```tablegen
// Wrong!
def PrintOp : MyDialect_Op<"print", [Pure]> {
  let arguments = (ins I32:$value);
}
```

❌ **Memory writes:**
```tablegen
// Wrong!
def StoreOp : MyDialect_Op<"store", [Pure]> {
  let arguments = (ins AnyMemRef:$memref, I32:$value);
}
```

❌ **Non-deterministic operations:**
```tablegen
// Wrong!
def RandomOp : MyDialect_Op<"random", [Pure]> {
  let results = (outs I32:$output);
}
```

❌ **Operations that can fail:**
```tablegen
// Wrong!
def DivideOp : MyDialect_Op<"divide", [Pure]> {
  // Can fail on divide-by-zero!
  let arguments = (ins I32:$lhs, I32:$rhs);
  let results = (outs I32:$output);
}
```

## Advanced Trait: ElementwiseMappable

The `ElementwiseMappable` trait extends scalar operations to work on tensors and vectors automatically.

### The Problem

You define a scalar operation:
```mlir
%r = poly.add %a, %b : !poly.poly<10>
```

But you want it to work on tensors too:
```mlir
%r = poly.add %a, %b : tensor<10x!poly.poly<10>>
```

**Without ElementwiseMappable:** Define separate operations for scalars and tensors.

**With ElementwiseMappable:** One operation works for both!

### Adding the Trait

```tablegen
include "mlir/Interfaces/ControlFlowInterfaces.td"

def Poly_AddOp : Poly_Op<"add", [Pure, ElementwiseMappable]> {
  let summary = "Addition operation for polynomials";
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
  // ...
}
```

### What It Enables

**Before (only scalars):**
```mlir
func.func @scalar_only(%a: !poly.poly<10>, %b: !poly.poly<10>) -> !poly.poly<10> {
  %r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %r : !poly.poly<10>
}
```

**After (scalars and tensors):**
```mlir
func.func @works_with_tensors(
    %a: tensor<5x!poly.poly<10>>,
    %b: tensor<5x!poly.poly<10>>) -> tensor<5x!poly.poly<10>> {
  // Automatically vectorized!
  %r = poly.add %a, %b : (tensor<5x!poly.poly<10>>, tensor<5x!poly.poly<10>>)
                       -> tensor<5x!poly.poly<10>>
  return %r : tensor<5x!poly.poly<10>>
}
```

**Mixed operands:**
```mlir
func.func @broadcast_scalar(
    %scalar: !poly.poly<10>,
    %tensor: tensor<5x!poly.poly<10>>) -> tensor<5x!poly.poly<10>> {
  // Scalar is broadcast to match tensor!
  %r = poly.add %scalar, %tensor : (!poly.poly<10>, tensor<5x!poly.poly<10>>)
                                 -> tensor<5x!poly.poly<10>>
  return %r : tensor<5x!poly.poly<10>>
}
```

### How ElementwiseMappable Works

The trait generates verification logic that:
1. Extracts the **element type** from containers (tensors/vectors)
2. Verifies element types match
3. Allows **broadcasting** (scalar + tensor)

Generated code (conceptual):
```cpp
LogicalResult Poly_AddOp::verify() {
  auto lhsElemType = getElementTypeOrSelf(getLhs().getType());
  auto rhsElemType = getElementTypeOrSelf(getRhs().getType());
  auto outElemType = getElementTypeOrSelf(getOutput().getType());

  // Verify element types match
  if (lhsElemType != outElemType || rhsElemType != outElemType)
    return emitError("element types must match");

  return success();
}
```

### Complete Example

**File: `lib/Dialect/Poly/PolyOps.td`**

```tablegen
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "PolyDialect.td"
include "PolyTypes.td"

// Base class with common traits
class Poly_BinOp<string mnemonic> :
    Poly_Op<mnemonic, [Pure, ElementwiseMappable]> {
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];
}

def Poly_AddOp : Poly_BinOp<"add"> {
  let summary = "Addition operation for polynomials";
}

def Poly_SubOp : Poly_BinOp<"sub"> {
  let summary = "Subtraction operation for polynomials";
}

def Poly_MulOp : Poly_BinOp<"mul"> {
  let summary = "Multiplication operation for polynomials";
}
```

**Usage:**
```mlir
module {
  // Scalar operations
  func.func @scalar(%a: !poly.poly<10>, %b: !poly.poly<10>) -> !poly.poly<10> {
    %r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    return %r : !poly.poly<10>
  }

  // Tensor operations (automatically work!)
  func.func @tensor(
      %a: tensor<100x!poly.poly<10>>,
      %b: tensor<100x!poly.poly<10>>) -> tensor<100x!poly.poly<10>> {
    %r = poly.add %a, %b : (tensor<100x!poly.poly<10>>, tensor<100x!poly.poly<10>>)
                         -> tensor<100x!poly.poly<10>>
    return %r : tensor<100x!poly.poly<10>>
  }

  // Broadcasting (scalar + tensor)
  func.func @broadcast(
      %scalar: !poly.poly<10>,
      %tensor: tensor<100x!poly.poly<10>>) -> tensor<100x!poly.poly<10>> {
    %r = poly.add %scalar, %tensor : (!poly.poly<10>, tensor<100x!poly.poly<10>>)
                                   -> tensor<100x!poly.poly<10>>
    return %r : tensor<100x!poly.poly<10>>
  }
}
```

## Verification Trait: SameOperandsAndResultElementType

This trait ensures type consistency for elementwise operations.

### Adding the Trait

```tablegen
class Poly_BinOp<string mnemonic> :
    Poly_Op<mnemonic, [
      Pure,
      ElementwiseMappable,
      SameOperandsAndResultElementType
    ]> {
  // ...
}
```

### What It Verifies

Ensures the **element types** of all operands and results match:

**Valid:**
```mlir
// All element types are !poly.poly<10>
%r = poly.add %a, %b : (tensor<5x!poly.poly<10>>, tensor<5x!poly.poly<10>>)
                     -> tensor<5x!poly.poly<10>>
```

**Invalid:**
```mlir
// Error: Element types don't match (10 vs 20)
%r = poly.add %a, %b : (tensor<5x!poly.poly<10>>, tensor<5x!poly.poly<20>>)
                     -> tensor<5x!poly.poly<10>>
```

### Generated Verification

```cpp
LogicalResult Poly_AddOp::verify() {
  // Extract element types
  Type lhsElem = getElementTypeOrSelf(getLhs().getType());
  Type rhsElem = getElementTypeOrSelf(getRhs().getType());
  Type outElem = getElementTypeOrSelf(getOutput().getType());

  // Verify all match
  if (lhsElem != rhsElem || rhsElem != outElem) {
    return emitOpError("requires all operands and results to have "
                       "the same element type");
  }

  return success();
}
```

## Other Useful Traits

### Commutative

For operations where operand order doesn't matter:

```tablegen
def Poly_AddOp : Poly_Op<"add", [Pure, Commutative]> {
  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);
}
```

Enables canonicalization:
```mlir
// Before: operands in arbitrary order
%r1 = poly.add %b, %a : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
%r2 = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

// After: canonicalized to same order
%r1 = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
%r2 = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

// CSE can now eliminate %r2
```

### Idempotent

For operations where `f(f(x)) = f(x)`:

```tablegen
def AbsOp : MyDialect_Op<"abs", [Idempotent]> {
  let arguments = (ins I32:$input);
  let results = (outs I32:$output);
}
```

Enables simplification:
```mlir
// Before
%0 = my.abs %x : i32
%1 = my.abs %0 : i32  // Redundant!

// After
%0 = my.abs %x : i32
// %1 eliminated, uses of %1 replaced with %0
```

### Terminator

For operations that end blocks:

```tablegen
def ReturnOp : MyDialect_Op<"return", [Terminator]> {
  let arguments = (ins Variadic<AnyType>:$operands);
}
```

Required for control flow operations.

### IsolatedFromAbove

For operations that create isolated regions:

```tablegen
def FuncOp : MyDialect_Op<"func", [IsolatedFromAbove]> {
  let regions = (region SizedRegion<1>:$body);
}
```

Used for function-like operations that can't reference values from outer scopes.

## CMake Integration

Traits don't require special CMake configuration, but you need to include the right TableGen files.

### File: `lib/Dialect/Poly/PolyOps.td`

```tablegen
// Include necessary trait definitions
include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "mlir/Interfaces/ControlFlowInterfaces.td"
include "mlir/Interfaces/InferTypeOpInterface.td"

// Your operations with traits
def Poly_AddOp : Poly_Op<"add", [Pure, ElementwiseMappable]> {
  // ...
}
```

### File: `lib/Dialect/Poly/CMakeLists.txt`

```cmake
# Standard TableGen generation
set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

# Link against interface libraries
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp

  DEPENDS
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSideEffectInterfaces  # For Pure trait
  MLIRControlFlowInterfaces # For ElementwiseMappable
)
```

### Build and Test

```powershell
cd D:\repos\mlir-tutorial\build
ninja MLIRPoly

# Test CSE
.\bin\tutorial-opt.exe ..\tests\cse.mlir --cse

# Test LICM
.\bin\tutorial-opt.exe ..\tests\licm.mlir --loop-invariant-code-motion
```

## Demonstrating Trait Effects

Create a test file to see traits in action.

### File: `test_traits.mlir`

```mlir
// RUN: tutorial-opt %s --cse --canonicalize | FileCheck %s

module {
  // CHECK-LABEL: func @test_cse
  func.func @test_cse(%p: !poly.poly<10>) -> !poly.poly<10> {
    // These two multiplications are identical
    %0 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    %1 = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    // CHECK: %[[V0:.*]] = poly.mul
    // CHECK-NOT: poly.mul
    // CHECK: poly.add %[[V0]], %[[V0]]

    %2 = poly.add %0, %1 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
    return %2 : !poly.poly<10>
  }

  // CHECK-LABEL: func @test_dce
  func.func @test_dce(%p: !poly.poly<10>) -> !poly.poly<10> {
    // This is unused - should be eliminated
    %unused = poly.mul %p, %p : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    // CHECK-NOT: poly.mul
    // CHECK: return %arg0

    return %p : !poly.poly<10>
  }

  // CHECK-LABEL: func @test_elementwise
  func.func @test_elementwise(
      %a: tensor<10x!poly.poly<5>>,
      %b: tensor<10x!poly.poly<5>>) -> tensor<10x!poly.poly<5>> {
    // Elementwise operations work on tensors
    %r = poly.add %a, %b : (tensor<10x!poly.poly<5>>, tensor<10x!poly.poly<5>>)
                         -> tensor<10x!poly.poly<5>>
    // CHECK: poly.add
    return %r : tensor<10x!poly.poly<5>>
  }
}
```

### Run the Tests

```powershell
# Parse and apply optimizations
.\build\bin\tutorial-opt.exe test_traits.mlir --cse --canonicalize

# Verify with FileCheck (if available)
.\build\bin\tutorial-opt.exe test_traits.mlir --cse --canonicalize | `
  FileCheck test_traits.mlir
```

## Debugging Traits

### Check If Trait Is Applied

View generated code to verify trait attachment:

```powershell
cat .\build\lib\Dialect\Poly\PolyOps.cpp.inc | Select-String -Context 5 "NoMemoryEffect"
```

Should show:
```cpp
void Poly_AddOp::getEffects(SmallVectorImpl<SideEffects::Effect> &effects) {
  // No effects - Pure trait
}
```

### Test Optimization Passes

```powershell
# Verbose output to see what passes do
.\build\bin\tutorial-opt.exe test.mlir --cse --mlir-print-ir-after-all

# Show statistics
.\build\bin\tutorial-opt.exe test.mlir --cse --mlir-pass-statistics
```

### Common Issues

**Issue: CSE doesn't eliminate duplicates**

**Cause:** Operation not marked Pure

**Solution:**
```tablegen
def MyOp : MyDialect_Op<"my_op", [Pure]> {  // Add Pure!
  // ...
}
```

**Issue: "Type mismatch" errors with ElementwiseMappable**

**Cause:** Element types don't match

**Solution:** Add `SameOperandsAndResultElementType`:
```tablegen
def MyOp : MyDialect_Op<"my_op", [
  Pure,
  ElementwiseMappable,
  SameOperandsAndResultElementType  // Add this!
]> {
  // ...
}
```

## Advanced: Custom Traits

You can define your own traits for dialect-specific properties.

### TableGen Definition

```tablegen
// Custom trait for polynomial operations requiring same degree bound
def SameDegreeBound : NativeOpTrait<"SameDegreeBound">;

def Poly_AddOp : Poly_Op<"add", [Pure, SameDegreeBound]> {
  // ...
}
```

### C++ Implementation

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

template <typename ConcreteType>
class SameDegreeBound : public TraitBase<ConcreteType, SameDegreeBound> {
public:
  static LogicalResult verifyTrait(Operation *op) {
    // Get operand types
    auto lhsType = op->getOperand(0).getType().cast<PolynomialType>();
    auto rhsType = op->getOperand(1).getType().cast<PolynomialType>();
    auto resultType = op->getResult(0).getType().cast<PolynomialType>();

    // Verify degree bounds match
    if (lhsType.getDegreeBound() != rhsType.getDegreeBound() ||
        rhsType.getDegreeBound() != resultType.getDegreeBound()) {
      return op->emitOpError("requires all operands and results to have "
                            "the same degree bound");
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

This trait ensures polynomial operations only work with matching degree bounds.

## Key Takeaways

**Conceptual:**

✅ **Traits invert the optimization burden** - Instead of writing custom passes for every dialect, you declare behavioral contracts that existing generic passes already understand. This architectural inversion enables massive code reuse across the MLIR ecosystem

✅ **Traits are zero-method interfaces** - Unlike interfaces requiring implementation, traits are purely declarative tags: "a trait is an interface with no methods." They signal properties to passes without imposing implementation burden

✅ **Pure = NoMemoryEffect + AlwaysSpeculatable is a dual contract** - Jeremy discovered through debugging that LICM requires both traits. `AlwaysSpeculatable` alone was insufficient; the pass also checks `MemoryEffectOpInterface` to confirm memory-effect freedom. This dual requirement isn't immediately obvious from documentation

✅ **Discovery requires pass-level investigation** - Jeremy's candid observation: "To figure out what each trait does, you have to dig through the pass implementations." The official traits list "is missing quite a few" (ConstantLike, Involution, Idempotent). Traits are best understood by reading pass source code, not documentation alone

✅ **Traits are a thin semantic layer, not a general framework** - They enable passes that already exist but cannot customize compiler behavior in arbitrary ways. When passes don't exist (like the Commutative optimization pass Jeremy mentions as "never registered"), traits become no-ops

✅ **Unused abstractions exist** - The `Commutative` trait exists in TableGen but "the pass is never registered or manually applied so this trait is a no-op." This reveals that trait infrastructure sometimes outpaces actual pass implementation

✅ **Semantic ambiguity can creep in** - `ElementwiseMappable` permits tensor addition that "the caller [must] type-switch or dyn_cast manually during passes," and broadcasting semantics remain "implied" rather than enforced. Traits declare properties but don't always prevent ambiguous interpretations

**Practical:**

✅ **Memory effects model dependencies** - Operations without effects can be freely reordered, enabling aggressive optimization

✅ **Speculative execution requires safety** - `AlwaysSpeculatable` means not just correctness, but crash-free and side-effect-free execution even when results go unused

✅ **ElementwiseMappable generalizes operations** - Scalar operations automatically extend to tensors/vectors when element-wise semantics apply

✅ **Traits unlock decades of optimization infrastructure** - Leveraging existing passes beats reimplementing optimizations for every dialect

✅ **Composition enables complex guarantees** - Combining traits expresses nuanced behavioral properties

## Next Steps

1. **[Tutorial 07: Folders and Constant Propagation](07-folders-constant-propagation.md)** - Implement constant folding
2. **Add traits** to your custom operations
3. **Experiment** with different optimization passes
4. **Study** trait definitions in `C:\msys64\mingw64\include\mlir\IR\OpBase.td`

## Additional Resources

- **OpBase.td:** `C:\msys64\mingw64\include\mlir\IR\OpBase.td`
- **SideEffectInterfaces:** `C:\msys64\mingw64\include\mlir\Interfaces\SideEffectInterfaces.td`
- **MLIR Traits Documentation:** [mlir.llvm.org/docs/Traits/](https://mlir.llvm.org/docs/Traits/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/09/07/mlir-using-traits/)

---

**Previous:** [← Tutorial 05: Defining a New Dialect](05-defining-dialect.md)
**Next:** [Tutorial 07: Folders and Constant Propagation →](07-folders-constant-propagation.md)
