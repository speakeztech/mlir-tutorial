# Tutorial 05: Defining a New Dialect

**Original Article:** [MLIR — Defining a New Dialect](https://jeremykun.com/2023/08/21/mlir-defining-a-new-dialect/) by Jeremy Kun

**Windows Adaptation:** Focus on MLIR dialect concepts with CMake build integration instead of Bazel.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 💡 What You'll Learn

- Understanding **dialect architecture** in MLIR
- Writing **TableGen definitions** for custom dialects
- Defining **parameterized types** with storage classes
- Creating **operations** with custom syntax
- Building dialects with **CMake**
- Making **semantic design decisions** for your domain

## 📖 The Philosophy of Dialect Design

When you define a custom dialect in MLIR, you're not just adding new syntax—you're **embedding domain knowledge into the compiler's type system**. This is a fundamentally different approach from traditional compiler design.

### The Traditional Compiler Problem

In a traditional compiler, domain-specific operations get lowered immediately to generic representations:

```
Your Domain → Generic IR → Optimization → Machine Code
   (lost immediately)   (one-size-fits-all)
```

Once you've lowered to that generic IR, you've **lost the semantic structure** that enables domain-specific optimizations. A polynomial multiplication becomes a series of loops and arithmetic operations—the compiler no longer knows it's dealing with polynomials.

### The MLIR Approach: Computation Dialects

MLIR introduces the concept of **computation dialects**—intermediate representations designed specifically to capture domain-specific operations and enable specialized transformations.

A computation dialect:
- Preserves high-level semantic structure
- Enables domain-specific optimizations
- Delays lowering until semantics are no longer needed
- Makes optimization opportunities explicit in the IR

**Example domains:**
- Tensor operations for machine learning
- Affine loop structures for polyhedral optimization
- Polynomial arithmetic for cryptography
- Quantum gate operations for quantum computing

Each domain has unique optimization opportunities that generic IRs can't express efficiently.

## 📖 Introduction: Building the Poly Dialect

Throughout this tutorial, we'll build a **Poly dialect** for polynomial mathematics. This example appears throughout the mlir-tutorial repository and demonstrates essential dialect design patterns.

### Why Polynomials?

Polynomials occupy a sweet spot for learning:
- **Mathematically simple** - No exotic domain knowledge required
- **Semantically rich** - Enough structure to demonstrate real MLIR features
- **Practically useful** - Cryptography (FHE, lattice crypto), signal processing, ML optimizations
- **Design choices** - Forces you to make semantic decisions that affect implementation

### The Critical Design Question: Semantic Choices

Here's where dialect design becomes interesting. Consider this operation:

```mlir
%result = poly.mul %p1, %p2 : (!poly.poly<7>, !poly.poly<7>) -> ???
```

What should the result type be?

**Option 1: Growing Degrees (Mathematical Reality)**
```mlir
poly.mul : (!poly.poly<7>, !poly.poly<7>) -> !poly.poly<14>
```

This matches mathematical reality: multiplying degree-7 polynomials yields a degree-14 result. But it creates complexity:
- Result type depends on operand types (requires inference)
- Operations aren't type-preserving (complicates analysis)
- Lowering becomes complex (tensor sizes change dynamically)

**Option 2: Bounded with Error (Verification)**
```mlir
poly.mul : (!poly.poly<7>, !poly.poly<7>) -> !poly.poly<7>  // Error if overflow
```

This enforces static bounds but requires verification:
- Need to prove statically that degree doesn't exceed bound
- Or insert runtime checks (performance cost)
- Makes some valid programs impossible to express

**Option 3: Ring Reduction (Modular Arithmetic)**
```mlir
poly.mul : (!poly.poly<7>, !poly.poly<7>) -> !poly.poly<7>
```

Treat polynomials as elements of R[x]/(x^D - 1) where D is the degree bound. When degree exceeds D, coefficients "wrap around" using the relation x^D = 1.

**We choose Option 3.** Here's why:

1. **Type-preserving operations** - All operations maintain degree bounds
2. **Matches cryptographic use cases** - Many crypto schemes use ring arithmetic
3. **Simplifies lowering** - Result tensor size known statically
4. **Enables optimizations** - Compiler knows exact memory layouts

This decision affects every aspect of the dialect: operation semantics, type system, verification, and lowering. **Semantic design choices are the foundation of dialect architecture.**

### The Iterative Design Philosophy

Dialect design is iterative. You start with:
1. **Minimal correct semantics** - Basic operations that parse and verify
2. **Expand capabilities** - Add optimization passes, canonicalizations
3. **Refine lowering** - Implement conversion to lower dialects
4. **Iterate based on use** - Adjust semantics as you discover optimization opportunities

This tutorial follows that progression. We'll start with basic type and operation definitions, then expand in later tutorials.

## 📖 Dialect Architecture Overview

A complete dialect consists of:

```
Poly Dialect
├── Dialect Definition (PolyDialect.td)
│   ├── Name and namespace
│   └── Type/operation includes
├── Type Definitions (PolyTypes.td)
│   ├── Polynomial type with degree bound
│   └── Parser/printer specifications
├── Operation Definitions (PolyOps.td)
│   ├── Arithmetic operations (add, mul, sub)
│   └── Utility operations (constant, eval)
└── C++ Implementation
    ├── Dialect registration
    ├── Type storage classes (auto-generated)
    └── Operation methods
```

## 🔬 Step 1: Basic Dialect Definition

Create the foundational dialect structure.

### File: `lib/Dialect/Poly/PolyDialect.td`

```tablegen
#ifndef LIB_DIALECT_POLY_POLYDIALECT_TD
#define LIB_DIALECT_POLY_POLYDIALECT_TD

include "mlir/IR/DialectBase.td"

def Poly_Dialect : Dialect {
  let name = "poly";

  let summary = "A dialect for polynomial arithmetic";

  let description = [{
    The Poly dialect provides types and operations for polynomial
    mathematics, including ring arithmetic with implicit modular reduction.

    Polynomials are represented with a degree bound parameter, treating
    operations in the ring R[x]/(x^D - 1) where D is the bound.
  }];

  let cppNamespace = "::mlir::tutorial::poly";

  // Enable default type parser/printer
  let useDefaultTypePrinterParser = 1;
}

#endif // LIB_DIALECT_POLY_POLYDIALECT_TD
```

### What This Generates

TableGen will create:

```cpp
namespace mlir {
namespace tutorial {
namespace poly {

class PolyDialect : public ::mlir::Dialect {
public:
  explicit PolyDialect(::mlir::MLIRContext *context);

  static constexpr ::llvm::StringLiteral getDialectNamespace() {
    return ::llvm::StringLiteral("poly");
  }

  // Type/operation registration hooks
  void initialize();
};

} // namespace poly
} // namespace tutorial
} // namespace mlir
```

## 🔬 Step 2: Defining Parameterized Types

Types in MLIR carry semantic information. For polynomials, the degree bound isn't just documentation—it's **computational semantics embedded in the type system**.

### Types as Semantic Anchors

This is a crucial concept: **types in MLIR don't just classify data; they encode domain constraints that enable optimization**.

Consider the difference:

**Generic approach (no domain knowledge):**
```cpp
// Generic IR loses the structure
void* polynomial = malloc(unknown_size);
loop_over_coefficients(polynomial); // Compiler doesn't know bounds
```

**Domain-specific approach (semantics in types):**
```mlir
%poly = ... : !poly.poly<10>
// Compiler knows:
// - Exactly 10 coefficients
// - Fixed memory layout
// - Multiplication produces degree 10 (ring reduction)
// - Can unroll loops statically
```

The type parameter `<10>` enables:
1. **Static verification** - Ensure operations respect degree bounds
2. **Optimization** - Compiler knows exact tensor dimensions
3. **Code generation** - Lower to fixed-size arrays
4. **Type safety** - Prevent mixing incompatible polynomials

### Understanding Type Parameters

**Without parameters** (like `i32`):
```mlir
%x = arith.addi %a, %b : i32
```
The type carries minimal information: "32-bit integer."

**With parameters** (like `tensor<10xi32>`):
```mlir
%x = arith.addi %a, %b : tensor<10xi32>
```
The type carries shape information: "1D tensor with 10 elements of type i32."

**Our polynomial type** needs a degree bound parameter:
```mlir
%x = poly.add %a, %b : !poly.poly<10>
```
The type carries domain semantics: "Polynomial in R[x]/(x^10 - 1)."

### File: `lib/Dialect/Poly/PolyTypes.td`

```tablegen
#ifndef LIB_DIALECT_POLY_POLYTYPES_TD
#define LIB_DIALECT_POLY_POLYTYPES_TD

include "mlir/IR/AttrTypeBase.td"
include "PolyDialect.td"

// Base class for Poly dialect types
class Poly_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Poly_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def Polynomial : Poly_Type<"Polynomial", "poly"> {
  let summary = "A polynomial with bounded degree";

  let description = [{
    Represents a polynomial in R[x]/(x^D - 1) where D is the degree bound.

    The polynomial type is parameterized by an integer degree bound,
    which determines when coefficient wrapping occurs during multiplication.

    Example:
      !poly.poly<10>  // Polynomial with degree bound 10
      !poly.poly<1024> // Polynomial with degree bound 1024
  }];

  // Parameter: degree bound (runtime value)
  let parameters = (ins "int":$degreeBound);

  // Assembly format: poly<DEGREE>
  let assemblyFormat = "`<` $degreeBound `>`";

  // Generate accessor method: int getDegreeBound() const;
}

#endif // LIB_DIALECT_POLY_POLYTYPES_TD
```

### What Gets Generated

TableGen creates a complete type class with:

**1. Storage Class** (for uniquing types):
```cpp
namespace mlir {
namespace tutorial {
namespace poly {
namespace detail {

struct PolynomialTypeStorage : public ::mlir::TypeStorage {
  using KeyTy = int;

  PolynomialTypeStorage(int degreeBound) : degreeBound(degreeBound) {}

  bool operator==(const KeyTy &key) const {
    return key == degreeBound;
  }

  static PolynomialTypeStorage *construct(
      ::mlir::TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<PolynomialTypeStorage>())
        PolynomialTypeStorage(key);
  }

  int degreeBound;
};

} // namespace detail
} // namespace poly
} // namespace tutorial
} // namespace mlir
```

**2. Type Class**:
```cpp
class PolynomialType : public ::mlir::Type {
public:
  using Base::Base;

  // Factory method
  static PolynomialType get(::mlir::MLIRContext *context, int degreeBound);

  // Accessor
  int getDegreeBound() const;

  // Parser/printer (delegated to dialect)
  static ::mlir::Type parse(::mlir::AsmParser &parser);
  void print(::mlir::AsmPrinter &printer) const;
};
```

### Type Uniquing

MLIR automatically ensures type uniqueness:

```cpp
auto ctx = getContext();
auto t1 = PolynomialType::get(ctx, 10);
auto t2 = PolynomialType::get(ctx, 10);
auto t3 = PolynomialType::get(ctx, 20);

assert(t1 == t2);  // Same degree → same instance
assert(t1 != t3);  // Different degree → different instance
```

This is implemented via the `TypeStorageAllocator` which maintains a uniquing map.

## 🔬 Step 3: Defining Operations

Operations are the verbs of your dialect. Let's define polynomial arithmetic.

### File: `lib/Dialect/Poly/PolyOps.td`

```tablegen
#ifndef LIB_DIALECT_POLY_POLYOPS_TD
#define LIB_DIALECT_POLY_POLYOPS_TD

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"
include "PolyDialect.td"
include "PolyTypes.td"

// Base class for Poly dialect operations
class Poly_Op<string mnemonic, list<Trait> traits = []> :
    Op<Poly_Dialect, mnemonic, traits>;

//===----------------------------------------------------------------------===//
// Addition Operation
//===----------------------------------------------------------------------===//

def Poly_AddOp : Poly_Op<"add"> {
  let summary = "Addition operation for polynomials";

  let description = [{
    Adds two polynomials coefficient-wise. Both operands must have the
    same degree bound, and the result has the same bound.

    Example:
      %result = poly.add %p1, %p2 : (!poly.poly<10>, !poly.poly<10>)
                                 -> !poly.poly<10>
  }];

  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];
}

//===----------------------------------------------------------------------===//
// Subtraction Operation
//===----------------------------------------------------------------------===//

def Poly_SubOp : Poly_Op<"sub"> {
  let summary = "Subtraction operation for polynomials";

  let description = [{
    Subtracts the second polynomial from the first, coefficient-wise.

    Example:
      %result = poly.sub %p1, %p2 : (!poly.poly<10>, !poly.poly<10>)
                                 -> !poly.poly<10>
  }];

  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];
}

//===----------------------------------------------------------------------===//
// Multiplication Operation
//===----------------------------------------------------------------------===//

def Poly_MulOp : Poly_Op<"mul"> {
  let summary = "Multiplication operation for polynomials";

  let description = [{
    Multiplies two polynomials using convolution, with implicit reduction
    modulo (x^D - 1) where D is the degree bound.

    When the product's degree would exceed D, coefficients wrap around
    according to the relation x^D = 1.

    Example:
      %result = poly.mul %p1, %p2 : (!poly.poly<10>, !poly.poly<10>)
                                 -> !poly.poly<10>
  }];

  let arguments = (ins Polynomial:$lhs, Polynomial:$rhs);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $lhs `,` $rhs attr-dict `:` `(` type($lhs) `,` type($rhs) `)` `->` type($output)
  }];
}

//===----------------------------------------------------------------------===//
// Constant Operation
//===----------------------------------------------------------------------===//

def Poly_ConstantOp : Poly_Op<"constant"> {
  let summary = "Define a constant polynomial";

  let description = [{
    Creates a polynomial constant from a list of integer coefficients.

    Example:
      // p(x) = 1 + 2x + 3x^2
      %p = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
  }];

  let arguments = (ins DenseIntElementsAttr:$coefficients);
  let results = (outs Polynomial:$output);

  let assemblyFormat = [{
    $coefficients attr-dict `:` type($output)
  }];
}

//===----------------------------------------------------------------------===//
// Evaluation Operation
//===----------------------------------------------------------------------===//

def Poly_EvalOp : Poly_Op<"eval"> {
  let summary = "Evaluate a polynomial at a point";

  let description = [{
    Evaluates a polynomial at a specific integer point using Horner's method.

    Example:
      %result = poly.eval %p at %x : (!poly.poly<10>, i32) -> i32
  }];

  let arguments = (ins Polynomial:$polynomial, I32:$point);
  let results = (outs I32:$output);

  let assemblyFormat = [{
    $polynomial `at` $point attr-dict `:` `(` type($polynomial) `,` type($point) `)` `->` type($output)
  }];
}

#endif // LIB_DIALECT_POLY_POLYOPS_TD
```

### Understanding Assembly Format

The `assemblyFormat` field controls how operations are parsed and printed.

**Format directives:**
- `$operand` - Reference an operand by name
- `type($operand)` - Print the type of an operand
- `attr-dict` - Print attributes (currently none)
- Literal strings like `","`, `"->"` - Printed verbatim

**Example for `poly.add`:**
```mlir
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
```

Maps to:
```
$lhs     = %a
","      = literal comma
$rhs     = %b
":"      = literal colon
"("      = literal paren
type($lhs) = !poly.poly<10>
","      = literal comma
type($rhs) = !poly.poly<10>
")"      = literal paren
"->"     = literal arrow
type($output) = !poly.poly<10>
```

## 👉 Step 4: CMake Integration

Now we need to build the dialect with CMake.

### File: `lib/Dialect/Poly/CMakeLists.txt`

```cmake
# Generate dialect/type/op definitions from TableGen
set(LLVM_TARGET_DEFINITIONS PolyDialect.td)
mlir_tablegen(PolyDialect.h.inc -gen-dialect-decls)
mlir_tablegen(PolyDialect.cpp.inc -gen-dialect-defs)
add_public_tablegen_target(MLIRPolyDialectIncGen)

set(LLVM_TARGET_DEFINITIONS PolyTypes.td)
mlir_tablegen(PolyTypes.h.inc -gen-typedef-decls)
mlir_tablegen(PolyTypes.cpp.inc -gen-typedef-defs)
add_public_tablegen_target(MLIRPolyTypesIncGen)

set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

# Build the dialect library
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyTypes.cpp
  PolyOps.cpp

  ADDITIONAL_HEADER_DIRS
  ${PROJECT_SOURCE_DIR}/include/Dialect/Poly

  DEPENDS
  MLIRPolyDialectIncGen
  MLIRPolyTypesIncGen
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
)
```

### File: `lib/Dialect/Poly/PolyDialect.cpp`

```cpp
#include "Dialect/Poly/PolyDialect.h"
#include "Dialect/Poly/PolyTypes.h"
#include "Dialect/Poly/PolyOps.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"

using namespace mlir;
using namespace mlir::tutorial::poly;

//===----------------------------------------------------------------------===//
// Poly Dialect
//===----------------------------------------------------------------------===//

// Include generated dialect definitions
#include "Dialect/Poly/PolyDialect.cpp.inc"

void PolyDialect::initialize() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "Dialect/Poly/PolyTypes.cpp.inc"
  >();

  addOperations<
#define GET_OP_LIST
#include "Dialect/Poly/PolyOps.cpp.inc"
  >();
}
```

### Building the Dialect

**Working directory:** Start from your repository root (such as `D:\repos\mlir-tutorial\`)

```powershell
# Configure (if not already done)
cd D:\repos\mlir-tutorial
mkdir build
cd build
cmake -G Ninja `
      -DCMAKE_BUILD_TYPE=Debug `
      -DMLIR_DIR="C:\msys64\mingw64\lib\cmake\mlir" `
      -DLLVM_DIR="C:\msys64\mingw64\lib\cmake\llvm" `
      ..

# Build just the Poly dialect
ninja MLIRPoly

# Or build everything
ninja
```

### Verifying the Build

Check that generated files exist:

```powershell
ls .\lib\Dialect\Poly\

# Should see:
# PolyDialect.h.inc
# PolyDialect.cpp.inc
# PolyTypes.h.inc
# PolyTypes.cpp.inc
# PolyOps.h.inc
# PolyOps.cpp.inc
```

## 👉 Step 5: Using Your Dialect

### Registering with tutorial-opt

**File: `tools/tutorial-opt.cpp`**

```cpp
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "Dialect/Poly/PolyDialect.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;

  // Register Poly dialect
  registry.insert<mlir::tutorial::poly::PolyDialect>();

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Tutorial Pass Driver\n", registry));
}
```

### Writing MLIR Code

**File: `test_poly.mlir`**

```mlir
// Demonstrate polynomial operations

module {
  func.func @polynomial_math(%arg0: !poly.poly<10>, %arg1: !poly.poly<10>) -> !poly.poly<10> {
    // Add two polynomials
    %sum = poly.add %arg0, %arg1 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    // Multiply the result
    %product = poly.mul %sum, %arg0 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>

    return %product : !poly.poly<10>
  }

  func.func @constant_example() -> i32 {
    // Define a constant polynomial: 2 + 8x + 20x^2
    %poly = poly.constant dense<[2, 8, 20]> : !poly.poly<10>

    // Evaluate at x = 3
    %point = arith.constant 3 : i32
    %result = poly.eval %poly at %point : (!poly.poly<10>, i32) -> i32

    // Result: 2 + 8(3) + 20(9) = 2 + 24 + 180 = 206
    return %result : i32
  }
}
```

### Running tutorial-opt

```powershell
# Parse and pretty-print
.\build\bin\tutorial-opt.exe test_poly.mlir

# Verify operations
.\build\bin\tutorial-opt.exe test_poly.mlir --verify-each

# Check diagnostics
.\build\bin\tutorial-opt.exe test_poly.mlir --mlir-print-ir-after-all
```

## 🔍 Design Considerations: The Art of Dialect Design

Dialect design involves navigating trade-offs between expressiveness, simplicity, and optimization potential. Every choice affects the entire implementation stack.

### Choosing Type Parameters

**Question:** What should be parameterized?

This isn't arbitrary—parameters determine what the compiler can reason about statically.

**Polynomial example:**
- ✅ **Degree bound** - Affects operation semantics, enables static analysis
- ❌ **Coefficient type** - Could be parameterized (e.g., `poly<10, i32>`) but adds complexity
- ❌ **Coefficient values** - These are runtime data, not type-level information

**The criterion:** Parameterize properties that:
- Affect type compatibility (should `poly<7>` be compatible with `poly<10>`? No.)
- Enable optimization (can compiler generate better code? Yes—fixed-size arrays)
- Express semantic constraints (does this prevent invalid programs? Yes—mismatched degrees)

**The cost:** Each parameter increases type system complexity. More parameters mean:
- More storage class code (hashing, equality, construction)
- More verbose IR (`!poly.poly<10, i32, modular>` vs `!poly.poly<10>`)
- More complex type inference

We start simple (single parameter) and add complexity only when needed.

### Operation Semantics: The Cascade of Consequences

**Question:** How should operations behave?

For `poly.mul`, we chose:
- **Implicit modular reduction**: x^D = 1 (ring arithmetic)
- **No overflow checking**: Wraps silently
- **Type-preserving**: `poly<D> * poly<D> -> poly<D>`

**This single decision cascades:**

1. **Affects lowering**: We can lower to fixed-size tensor operations
2. **Affects verification**: No need to check degree bounds dynamically
3. **Affects optimization**: Enables loop unrolling (size known statically)
4. **Affects semantics**: Users must understand ring behavior

**Alternatives considered:**

**Option A: Explicit modulo operation** (`poly.mul_mod`)
- Pro: Makes ring reduction explicit in IR
- Con: Verbose, requires users to understand modulo semantics
- Con: Extra operation complicates dialect

**Option B: Dynamic degree bounds** (result type depends on operands)
- Pro: Mathematically accurate
- Con: Type inference required (complex)
- Con: Lowering must handle dynamic sizes (inefficient)
- Con: Hard to optimize (sizes unknown until runtime)

**Option C: Overflow errors** (verify statically or fail at runtime)
- Pro: Catches errors early
- Con: Requires sophisticated static analysis or runtime checks
- Con: Makes some valid programs (that rely on wrapping) impossible

**Why we chose implicit ring reduction:**
- **Simplicity**: Type system remains simple
- **Performance**: Static sizes enable aggressive optimization
- **Use case alignment**: Cryptographic schemes use ring arithmetic
- **Composability**: Works well with existing MLIR passes

**The lesson:** Semantic choices aren't "right" or "wrong"—they're **trade-offs aligned with use cases**.

### Assembly Format Design: Ergonomics vs Explicitness

**Question:** How should operations look in text?

**Maximally explicit format:**
```mlir
%r = poly.add(lhs: %a : !poly.poly<10>, rhs: %b : !poly.poly<10>) -> (result: !poly.poly<10>)
```

**Verbose format:**
```mlir
%r = poly.add(%a : !poly.poly<10>, %b : !poly.poly<10>) -> !poly.poly<10>
```

**Our chosen format:**
```mlir
%r = poly.add %a, %b : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
```

**Minimalist format (with full inference):**
```mlir
%r = poly.add %a, %b  // Infer all types
```

**Trade-offs:**
- **Shorter syntax** → easier to read, less typing
- **Type inference** → less redundancy, but harder to understand errors
- **Convention matching** → familiar to MLIR users (important for adoption)

We choose the middle ground: explicit types (no inference complexity) but concise syntax (ergonomic).

**Why explicit types despite redundancy?**

1. **Error messages** - When something fails, you see types immediately
2. **Self-documentation** - IR is readable without consulting operation definitions
3. **Verification** - Parser can check type consistency locally
4. **Simplicity** - No inference engine required (TableGen stays simple)

This is MLIR philosophy: **prefer explicit over implicit**. The cost (verbosity) is paid once; the benefit (clarity) compounds.

## 👉 Debugging Your Dialect

### View Generated Code

```powershell
# Check generated type definitions
cat .\build\lib\Dialect\Poly\PolyTypes.h.inc | Select-String "class Polynomial"

# Check generated operations
cat .\build\lib\Dialect\Poly\PolyOps.h.inc | Select-String "class.*Op"
```

### Common Errors

**Error: "use of undeclared identifier 'Polynomial'"**

**Problem:** Type not registered with dialect.

**Solution:** Add to `initialize()`:
```cpp
addTypes<PolynomialType>();
```

**Error: "no member named 'getDegreeBound'"**

**Problem:** TableGen didn't generate accessor.

**Solution:** Check that `PolyTypes.td` has:
```tablegen
let parameters = (ins "int":$degreeBound);
```

**Error: "undefined reference to `poly::PolyDialect::PolyDialect'"**

**Problem:** Missing dialect implementation.

**Solution:** Ensure `PolyDialect.cpp` includes:
```cpp
#include "Dialect/Poly/PolyDialect.cpp.inc"
```

### Testing Your Dialect

Create a simple test:

**File: `tests/poly_basic.mlir`**

```mlir
// RUN: tutorial-opt %s | tutorial-opt | FileCheck %s

// CHECK-LABEL: func @test_poly
func.func @test_poly(%arg0: !poly.poly<10>) -> !poly.poly<10> {
  // CHECK: poly.add
  %0 = poly.add %arg0, %arg0 : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %0 : !poly.poly<10>
}
```

Run with:
```powershell
.\build\bin\tutorial-opt.exe .\tests\poly_basic.mlir | `
  .\build\bin\tutorial-opt.exe | `
  FileCheck .\tests\poly_basic.mlir
```

## 🔍 Advanced Topics

### Multiple Type Parameters

You can have multiple parameters:

```tablegen
def ComplexPolynomial : Poly_Type<"ComplexPolynomial", "complex_poly"> {
  let summary = "Complex polynomial with degree and precision";

  let parameters = (ins
    "int":$degreeBound,
    "int":$precision
  );

  let assemblyFormat = "`<` $degreeBound `,` $precision `>`";
}
```

Usage:
```mlir
%x = poly.add %a, %b : !poly.complex_poly<10, 32>
```

### Custom Type Constraints

Add verification to types:

```tablegen
def Polynomial : Poly_Type<"Polynomial", "poly"> {
  let parameters = (ins "int":$degreeBound);
  let assemblyFormat = "`<` $degreeBound `>`";

  // Add verification
  let genVerifyDecl = 1;
}
```

In C++:
```cpp
LogicalResult PolynomialType::verify(
    function_ref<InFlightDiagnostic()> emitError,
    int degreeBound) {
  if (degreeBound <= 0)
    return emitError() << "degree bound must be positive";
  return success();
}
```

### Type Hierarchy

Create a base type with subclasses:

```tablegen
class Poly_Type<string name> : TypeDef<Poly_Dialect, name> {
  let cppBaseClassName = "::mlir::tutorial::poly::PolyTypeInterface";
}

def IntPolynomial : Poly_Type<"IntPolynomial"> {
  let parameters = (ins "int":$degreeBound);
}

def FloatPolynomial : Poly_Type<"FloatPolynomial"> {
  let parameters = (ins "int":$degreeBound, "FloatType":$coeffType);
}
```

## Comparing to Bazel Build

### Original Tutorial (Bazel)

**File: `BUILD`**
```python
gentbl_cc_library(
    name = "poly_ops_inc_gen",
    tbl_outs = [
        (["-gen-op-decls"], "PolyOps.h.inc"),
        (["-gen-op-defs"], "PolyOps.cpp.inc"),
        (["-gen-dialect-decls"], "PolyDialect.h.inc"),
        (["-gen-dialect-defs"], "PolyDialect.cpp.inc"),
    ],
    tblgen = "@llvm-project//mlir:mlir-tblgen",
    td_file = "PolyOps.td",
    deps = [
        "@llvm-project//mlir:OpBaseTdFiles",
        "@llvm-project//mlir:SideEffectInterfacesTdFiles",
    ],
)

cc_library(
    name = "poly_dialect",
    srcs = ["PolyDialect.cpp", "PolyOps.cpp"],
    hdrs = ["PolyDialect.h", "PolyOps.h"],
    deps = [
        ":poly_ops_inc_gen",
        "@llvm-project//mlir:IR",
    ],
)
```

### This Tutorial (CMake)

**Much simpler:**
```cmake
set(LLVM_TARGET_DEFINITIONS PolyOps.td)
mlir_tablegen(PolyOps.h.inc -gen-op-decls)
mlir_tablegen(PolyOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(MLIRPolyOpsIncGen)

add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp
  DEPENDS MLIRPolyOpsIncGen
  LINK_LIBS PUBLIC MLIRIR
)
```

## Real-World Dialect Examples

### Tensor Dialect

From MLIR standard library:
```mlir
%result = tensor.extract %t[%i, %j] : tensor<10x20xf32>
```

**Type parameter:** Shape and element type
**Design choice:** Immutable tensors (SSA form)

### LLVM Dialect

Interface to LLVM IR:
```mlir
%ptr = llvm.alloca %size x i32 : (i64) -> !llvm.ptr<i32>
%val = llvm.load %ptr : !llvm.ptr<i32>
```

**Type parameters:** Pointee type (being phased out)
**Design choice:** Opaque pointers matching LLVM's direction

### Affine Dialect

Loop optimization:
```mlir
affine.for %i = 0 to 100 {
  affine.load %memref[%i] : memref<100xf32>
}
```

**Type parameters:** Memory space
**Design choice:** Polyhedral model for loop transformations

## 📖 Key Takeaways

**Conceptual:**

✅ **Dialects exist to preserve domain semantics through compilation** - Unlike generic IRs that lose semantic structure immediately, MLIR dialects maintain domain-specific operations long enough to enable specialized optimizations

✅ **Semantic design choices cascade through the entire system** - Deciding that polynomials live in R[x]/(x^D-1) affects not just multiplication semantics but also lowering strategy, verification logic, and which optimizations become possible

✅ **Type parameters encode what must be known at compile-time** - Parameterizing `poly.poly<D>` with a degree bound represents a fundamental commitment: this information is statically available and enables shape-static compilation

✅ **Pragmatism over philosophical purity** - Jeremy's honest acknowledgment: "There is quite a large surface area of design choices," and the tutorial trades perfect design for functional implementation. The ring reduction semantics (Option 3) was chosen partly because it's "easier" to implement, not because it's mathematically superior

✅ **TableGen is semantic encoding, not just code generation** - Lines like `let assemblyFormat = ...` don't merely generate parsers—they declare how concrete syntax mirrors semantic structure. The progression from `class` (abstract design) to `def` (realized artifact) mirrors design-to-implementation

✅ **Storage classes hide unavoidable complexity** - The `PolynomialTypeStorage` pattern represents a concession: dialects present simple interfaces (`poly<7>`), but underneath require storage management for parameters. Jeremy notes external projects have "multi-thousand line implementation files" for this

✅ **Design with lowering targets in mind** - The static degree choice is justified partly because it "makes lowering a poly type require replacing `poly.poly<D>` with a tensor of D coefficients"—a natural, zero-overhead abstraction. Progressive lowering validates design decisions

✅ **Type inference is opt-in, not automatic** - Jeremy observes that auto-generated type inference "should be able to work" but "the MLIR devs appear to have made [it] opt-in via the trait infrastructure." Even MLIR's design contains unresolved tensions between inference and explicit specification

**Practical:**

✅ **TableGen generates predictable patterns** - Always inspect generated code to understand what you're building on

✅ **CMake integration is straightforward** - `mlir_tablegen()` and `add_mlir_library()` handle code generation and linking

✅ **Registration makes types and ops visible** - Types only exist when explicitly declared via `addTypes<...>()`, preventing accidental polymorphism

✅ **Start minimal, expand iteratively** - Begin with basic correct semantics, then add optimizations as use cases emerge

## Next Steps

1. **[Tutorial 06: Using Traits](06-using-traits.md)** - Add reusable behaviors to operations
2. **Explore** `lib/Dialect/Poly/` in the repository
3. **Experiment** with adding new operations to the Poly dialect
4. **Study** other dialects in `C:\msys64\mingw64\include\mlir\Dialect\`

## Additional Resources

- **MLIR Dialect Documentation:** [mlir.llvm.org/docs/Dialects/](https://mlir.llvm.org/docs/Dialects/)
- **OpBase.td Reference:** `C:\msys64\mingw64\include\mlir\IR\OpBase.td`
- **Toy Tutorial:** [mlir.llvm.org/docs/Tutorials/Toy/](https://mlir.llvm.org/docs/Tutorials/Toy/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/08/21/mlir-defining-a-new-dialect/)

---

**Previous:** [← Tutorial 04: Using TableGen for Passes](04-using-tablegen.md)
**Next:** [Tutorial 06: Using Traits →](06-using-traits.md)
