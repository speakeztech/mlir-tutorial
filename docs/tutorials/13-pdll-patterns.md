# Tutorial 13: Defining Patterns with PDLL

**Original Article:** [MLIR ,  PDLL](https://www.jeremykun.com/2024/08/04/mlir-pdll/) by Jeremy Kun

**Windows Adaptation:** Focus on PDLL (Pattern Descriptor Language) for advanced pattern matching with CMake integration.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 💡 What You'll Learn

- Understanding **PDLL vs TableGen DRR**
- Writing **PDLL pattern files** (`.pdll`)
- Using **advanced pattern matching** features
- Implementing **constraints** and **native code integration**
- Generating **C++ or PDL IR** from PDLL
- **Compiling PDLL** with `mlir-pdll` on Windows
- **CMake integration** for PDLL patterns
- **Performance benefits** of PDLL bytecode

## Introduction: What Is PDLL?

**PDLL** (Pattern Descriptor Language Language) is a high-level language for defining MLIR pattern rewrites. It's more expressive than TableGen's Declarative Rewrite Rules (DRR).

### The Evolution Problem: When Declarative Breaks Down

When you first learned pattern matching in Tutorial 09, TableGen DRR seemed elegant: declare what you want to match, declare the replacement, done. But that elegance has limits. **TableGen DRR cannot express operations with multiple results, operations containing regions (like loops), operations with variable-length operand lists, or patterns that need to perform arithmetic on constant values during matching.**

These aren't edge cases, they're fundamental IR patterns. When you encounter them, you face an unpleasant choice: abandon declarative pattern matching and write verbose C++ pattern classes, or contort your dialect to avoid these features. PDLL offers a third option: **a more expressive pattern language that preserves declarative benefits while handling the complexity TableGen cannot.**

### The Bytecode Insight: Interpretation Enables Extensibility

PDLL's design makes a fascinating trade-off. Instead of compiling patterns directly to C++, PDLL follows a three-stage pipeline:

1. **PDLL source → PDL IR** (pattern descriptor dialect)
2. **PDL IR → PDL-interp bytecode** (lower-level interpretation dialect)
3. **Runtime bytecode execution** during pattern matching

Why interpretation instead of compilation? Three concrete wins: **extensibility** (users can provide patterns without recompiling the compiler), **binary size** (bytecode is ~10x smaller than equivalent C++), and **joint optimization** (the system can merge redundant work across multiple patterns into a shared finite state machine).

This last point is subtle but powerful. When you have hundreds of patterns competing to match IR, they repeatedly access the same operands and attributes. Compiled C++ patterns duplicate this work; interpreted bytecode can coordinate it. The performance trade-off, slower individual pattern execution, is amortized by reducing redundant access across the pattern set.

### PDLL vs TableGen DRR

**TableGen DRR (Tutorial 09):**
```tablegen
// Declarative but limited
def DifferenceOfSquares : Pattern<
  (Poly_SubOp (Poly_MulOp $x, $x), (Poly_MulOp $y, $y)),
  [(Poly_AddOp:$sum $x, $y), (Poly_SubOp:$diff $x, $y), (Poly_MulOp $sum, $diff)]
>;
```

**PDLL:**
```pdll
// More expressive and readable
Pattern DifferenceOfSquares {
  let root = op<poly.sub>(
    lhs: op<poly.mul>(x: Value, x: Value),
    rhs: op<poly.mul>(y: Value, y: Value)
  );

  rewrite root with {
    let sum = op<poly.add>(x, y);
    let diff = op<poly.sub>(x, y);
    replace root with op<poly.mul>(sum, diff);
  };
}
```

### Why Use PDLL?

**Advantages over TableGen DRR:**

✅ **Multiple results** - Operations with multiple outputs
✅ **Regions** - Match operations containing regions (loops, branches)
✅ **Variadic operands** - Operations with variable number of operands
✅ **Arithmetic on static values** - Compute with constants in patterns
✅ **Better readability** - More natural syntax
✅ **Bytecode compilation** - ~10x smaller than C++ equivalent
✅ **Runtime extensibility** - Load patterns without recompiling

**When TableGen DRR is insufficient:**
- Complex control flow operations
- Operations with multiple results
- Dynamic pattern generation
- Runtime pattern loading

## PDLL Basics

### File Structure

**File: `patterns.pdll`**

```pdll
// Import MLIR dialects
#include "mlir/Dialect/Arith/IR/ArithOps.td"
#include "Dialect/Poly/PolyOps.td"

// Define patterns
Pattern PatternName {
  // Pattern matching logic
  let root = ...;

  // Rewrite logic
  rewrite root with {
    ...
  };
}
```

### Pattern Syntax

**Basic structure:**

```pdll
Pattern Name {
  // 1. Match phase: Identify IR to transform
  let root = <match expression>;

  // 2. (Optional) Additional constraints
  require <constraint>;

  // 3. Rewrite phase: Transform IR
  rewrite root with {
    <replacement operations>
  };
}
```

### Operation Matching

**Syntax:**
```pdll
op<dialect.operation>(operand1, operand2, ...) -> (result_type1, result_type2, ...)
```

**Examples:**

```pdll
// Match: poly.add %x, %y
let add_op = op<poly.add>(x: Value, y: Value);

// Match: arith.constant 42 : i32
let const_op = op<arith.constant> -> (i32);

// Match: poly.mul with named result
let mul_op: Op = op<poly.mul>(a: Value, b: Value);

// Match: operation with attribute
let op_with_attr = op<poly.constant> {
  coefficients = attr<"dense<[1, 2, 3]> : tensor<3xi32>">
};
```

### Type and Value Capture

**Value capture:**
```pdll
Pattern Example {
  // Capture operand values
  let root = op<poly.add>(lhs: Value, rhs: Value);

  // Use captured values in rewrite
  rewrite root with {
    replace root with op<poly.add>(rhs, lhs);  // Swap operands
  };
}
```

**Type capture:**
```pdll
Pattern TypeExample {
  // Capture types
  let root = op<poly.cast>(input: Value) -> (output_type: Type);

  rewrite root with {
    // Use captured type
    replace root with op<poly.identity>(input) -> (output_type);
  };
}
```

**Attribute capture:**
```pdll
Pattern AttrExample {
  // Capture attributes
  let root = op<poly.constant> {coefficients = coeffs: Attr};

  rewrite root with {
    // Use captured attribute
    replace root with op<arith.constant> {value = coeffs};
  };
}
```

## Simple Patterns

### Example 1: Commutative Normalization

Move constants to the right side of commutative operations.

**File: `normalize.pdll`**

```pdll
#include "Dialect/Poly/PolyOps.td"

// Pattern: Move constant to RHS in addition
Pattern MoveConstantRight {
  let root = op<poly.add>(
    const_op: op<poly.constant>,
    other: Value
  );

  rewrite root with {
    // Swap operands
    replace root with op<poly.add>(other, const_op);
  };
}
```

### Example 2: Identity Elimination

Remove operations with identity elements.

**File: `identity.pdll`**

```pdll
#include "Dialect/Poly/PolyOps.td"

// Pattern: x + 0 = x
Pattern AddZero {
  let zero = op<poly.constant> {
    coefficients = attr<"dense<[0]> : tensor<1xi32>">
  };

  let root = op<poly.add>(x: Value, zero);

  rewrite root with {
    replace root with x;  // Just return x
  };
}

// Pattern: x * 1 = x
Pattern MulOne {
  let one = op<poly.constant> {
    coefficients = attr<"dense<[1]> : tensor<1xi32>">
  };

  let root = op<poly.mul>(x: Value, one);

  rewrite root with {
    replace root with x;
  };
}
```

### Example 3: Algebraic Identities

**File: `algebra.pdll`**

```pdll
#include "Dialect/Poly/PolyOps.td"

// Pattern: x² - y² = (x+y)(x-y)
Pattern DifferenceOfSquares {
  let root = op<poly.sub>(
    lhs: op<poly.mul>(x: Value, x: Value),
    rhs: op<poly.mul>(y: Value, y: Value)
  );

  rewrite root with {
    let sum = op<poly.add>(x, y);
    let diff = op<poly.sub>(x, y);
    replace root with op<poly.mul>(sum, diff);
  };
}

// Pattern: (x + c1) + c2 = x + (c1 + c2)
Pattern CombineConstants {
  let root = op<poly.add>(
    inner: op<poly.add>(
      x: Value,
      c1: op<poly.constant>
    ),
    c2: op<poly.constant>
  );

  rewrite root with {
    // Note: Constant folding would happen automatically
    let combined = op<poly.add>(c1, c2);
    replace root with op<poly.add>(x, combined);
  };
}
```

## Advanced Features

### Constraints

Add conditions that must be satisfied for pattern to match.

**File: `constrained.pdll`**

```pdll
#include "Dialect/Poly/PolyOps.td"

// Constraint: Check if operation has exactly one use
Constraint HasOneUse(value: Value) [{
  return success(value.hasOneUse());
}];

// Pattern with constraint
Pattern SafeDifferenceOfSquares {
  let lhs_mul: Op = op<poly.mul>(x: Value, x: Value);
  let rhs_mul: Op = op<poly.mul>(y: Value, y: Value);
  let root = op<poly.sub>(lhs_mul, rhs_mul);

  // Only apply if mul operations have single use
  require HasOneUse(lhs_mul);
  require HasOneUse(rhs_mul);

  rewrite root with {
    let sum = op<poly.add>(x, y);
    let diff = op<poly.sub>(x, y);
    replace root with op<poly.mul>(sum, diff);
  };
}
```

### Native Constraints with Return Values

Some constraints compute values used in rewrite.

**File: `native_constraint.pdll`**

```pdll
// Constraint declaration (implementation in C++)
Constraint GetConstantValue(op: Op) -> Attr;
Constraint IsPowerOfTwo(value: Attr) -> Attr;

// Pattern: mul by power of 2 → shifts
Pattern MulByPowerOfTwo {
  let const_op: Op = op<poly.constant>;
  let root = op<poly.mul>(x: Value, const_op);

  // Get constant value and check if power of 2
  let const_val = GetConstantValue(const_op);
  let shift_amount = IsPowerOfTwo(const_val);

  rewrite root with {
    // Use computed shift amount
    replace root with op<poly.shift_left>(x) {amount = shift_amount};
  };
}
```

**C++ implementation:**

```cpp
// In PolyPatterns.cpp
static FailureOr<Attribute> getConstantValue(PDLPatternModule &pdl, Operation *op) {
  auto constOp = dyn_cast<poly::ConstantOp>(op);
  if (!constOp)
    return failure();
  return constOp.getCoefficientsAttr();
}

static FailureOr<Attribute> isPowerOfTwo(PDLPatternModule &pdl, Attribute attr) {
  auto denseAttr = attr.dyn_cast<DenseIntElementsAttr>();
  if (!denseAttr)
    return failure();

  APInt value = *denseAttr.value_begin<APInt>();
  if (!value.isPowerOf2())
    return failure();

  // Return log2 as shift amount
  int shiftAmount = value.logBase2();
  return IntegerAttr::get(attr.getContext(), APInt(32, shiftAmount));
}

void registerPDLLConstraints(RewritePatternSet &patterns) {
  auto &pdlPatterns = patterns.getPDLPatterns();

  pdlPatterns.registerConstraintFunction("GetConstantValue", getConstantValue);
  pdlPatterns.registerConstraintFunction("IsPowerOfTwo", isPowerOfTwo);
}
```

### Pattern Benefits

Control pattern application order with benefits (higher = applied first).

**File: `benefits.pdll`**

```pdll
// High priority: Try this first
Pattern EarlyOptimization with benefit(10) {
  let root = op<poly.expensive_op>(x: Value);
  rewrite root with {
    replace root with op<poly.cheap_op>(x);
  };
}

// Low priority: Try this last
Pattern FallbackOptimization with benefit(0) {
  let root = op<poly.generic_op>(x: Value);
  rewrite root with {
    // Generic transformation
    replace root with x;
  };
}
```

### Matching Multiple Results

PDLL handles operations with multiple results naturally.

**File: `multi_result.pdll`**

```pdll
#include "Dialect/Poly/PolyOps.td"

// Pattern: Match operation with 2 results
Pattern SplitAndMerge {
  // poly.divrem returns quotient and remainder
  let divrem: Op = op<poly.divrem>(dividend: Value, divisor: Value)
    -> (quotient: Value, remainder: Value);

  // Only optimize if remainder is unused
  require IsUnused(remainder);

  rewrite divrem with {
    // Replace with simple division
    replace divrem with op<poly.div>(dividend, divisor);
  };
}
```

### Region Matching

Match operations containing regions (functions, loops, conditionals).

**File: `regions.pdll`**

```pdll
#include "mlir/Dialect/SCF/IR/SCFOps.td"

// Pattern: Simplify loop with constant bounds
Pattern SimplifyLoop {
  let root: Op = op<scf.for>(
    lb: op<arith.constant>,
    ub: op<arith.constant>,
    step: op<arith.constant>
  ) {
    // Match region structure
    // (Advanced - requires understanding region syntax)
  };

  rewrite root with {
    // Unroll loop or other optimization
    ...
  };
}
```

### Variadic Operands

Handle operations with variable number of operands.

**File: `variadic.pdll`**

```pdll
// Pattern: Simplify concat with single input
Pattern SimplifyConcat {
  // Match concat with any number of operands
  let root = op<poly.concat>(operands: ValueRange);

  // Check if only one operand
  require IsSize<1>(operands);

  rewrite root with {
    // Extract single operand
    let single = operands[0];
    replace root with single;
  };
}
```

## Compiling PDLL Patterns

### Using mlir-pdll Tool

**Command-line usage:**

```powershell
# Generate C++ code
mlir-pdll patterns.pdll `
  -x=cpp `
  -I D:\repos\mlir-tutorial\include `
  -o patterns.cpp.inc

# Generate PDL IR
mlir-pdll patterns.pdll `
  -x=mlir `
  -I D:\repos\mlir-tutorial\include `
  -o patterns.pdl

# Generate PDL bytecode (for runtime loading)
mlir-pdll patterns.pdll `
  -x=bytecode `
  -I D:\repos\mlir-tutorial\include `
  -o patterns.pdlb
```

### Output Formats

**C++ (`-x=cpp`):**
- Generates C++ pattern classes
- Compiled into binary
- Best performance
- Static patterns

**PDL IR (`-x=mlir`):**
- Generates PDL dialect operations
- Human-readable
- Can be further optimized
- Useful for debugging

**Bytecode (`-x=bytecode`):**
- Compact binary format
- ~10x smaller than C++ equivalent
- Runtime loading without recompilation
- Interpreted execution

## CMake Integration

### Step 1: Add PDLL Dependency

**File: `cmake/modules/FindMLIR.cmake` (if needed)**

```cmake
# Ensure mlir-pdll is available
find_program(MLIR_PDLL_EXECUTABLE mlir-pdll
  HINTS ${MLIR_TOOLS_DIR}
  DOC "Path to mlir-pdll executable")

if(NOT MLIR_PDLL_EXECUTABLE)
  message(WARNING "mlir-pdll not found. PDLL patterns will not be built.")
endif()
```

### Step 2: Create PDLL Compilation Function

**File: `cmake/modules/AddMLIRPDLL.cmake`**

```cmake
function(add_mlir_pdll_library target)
  cmake_parse_arguments(ARG "" "OUTPUT_FORMAT" "PDLL_FILES;INCLUDE_DIRS" ${ARGN})

  if(NOT ARG_OUTPUT_FORMAT)
    set(ARG_OUTPUT_FORMAT "cpp")
  endif()

  set(generated_files "")

  foreach(pdll_file ${ARG_PDLL_FILES})
    get_filename_component(pdll_name ${pdll_file} NAME_WE)

    if(ARG_OUTPUT_FORMAT STREQUAL "cpp")
      set(output_file "${CMAKE_CURRENT_BINARY_DIR}/${pdll_name}.cpp.inc")
    elseif(ARG_OUTPUT_FORMAT STREQUAL "mlir")
      set(output_file "${CMAKE_CURRENT_BINARY_DIR}/${pdll_name}.pdl")
    else()
      set(output_file "${CMAKE_CURRENT_BINARY_DIR}/${pdll_name}.pdlb")
    endif()

    # Build include flags
    set(include_flags "")
    foreach(inc_dir ${ARG_INCLUDE_DIRS})
      list(APPEND include_flags "-I${inc_dir}")
    endforeach()

    # Add custom command
    add_custom_command(
      OUTPUT ${output_file}
      COMMAND ${MLIR_PDLL_EXECUTABLE}
        ${CMAKE_CURRENT_SOURCE_DIR}/${pdll_file}
        -x=${ARG_OUTPUT_FORMAT}
        ${include_flags}
        -o ${output_file}
      DEPENDS ${pdll_file}
      COMMENT "Compiling PDLL pattern ${pdll_file}"
    )

    list(APPEND generated_files ${output_file})
  endforeach()

  # Create target
  add_custom_target(${target} DEPENDS ${generated_files})
endfunction()
```

### Step 3: Use in Dialect CMakeLists.txt

**File: `lib/Dialect/Poly/CMakeLists.txt`**

```cmake
# Include PDLL support
include(AddMLIRPDLL)

# Compile PDLL patterns to C++
add_mlir_pdll_library(PolyPDLLPatterns
  PDLL_FILES
    PolyPatterns.pdll
  INCLUDE_DIRS
    ${PROJECT_SOURCE_DIR}/include
    ${MLIR_INCLUDE_DIRS}
  OUTPUT_FORMAT cpp
)

# Main library depends on generated patterns
add_mlir_library(MLIRPoly
  PolyDialect.cpp
  PolyOps.cpp
  PolyTypes.cpp

  DEPENDS
  MLIRPolyOpsIncGen
  PolyPDLLPatterns  # Add dependency

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRSupport
  MLIRSideEffectInterfaces
  MLIRPDLL  # Link PDLL support
)
```

### Step 4: Include Generated Patterns

**File: `lib/Dialect/Poly/PolyOps.cpp`**

```cpp
#include "Dialect/Poly/PolyOps.h"
#include "mlir/IR/PatternMatch.h"

// Include generated PDLL patterns
#include "PolyPatterns.cpp.inc"

using namespace mlir;
using namespace mlir::tutorial::poly;

void poly::registerPolyPatterns(RewritePatternSet &patterns) {
  // Register PDLL-generated patterns
  populateGeneratedPDLLPatterns(patterns);

  // Register native constraint functions
  auto &pdlPatterns = patterns.getPDLPatterns();
  pdlPatterns.registerConstraintFunction("GetConstantValue", getConstantValue);
  pdlPatterns.registerConstraintFunction("IsPowerOfTwo", isPowerOfTwo);
  // ... more constraints ...
}
```

## Complete Example

### File: `lib/Dialect/Poly/PolyPatterns.pdll`

```pdll
//===- PolyPatterns.pdll - Polynomial dialect patterns -------*- PDLL -*-===//
//
// Pattern rewrites for the Polynomial dialect.
//
//===----------------------------------------------------------------------===//

#include "Dialect/Poly/PolyOps.td"

//===----------------------------------------------------------------------===//
// Identity patterns
//===----------------------------------------------------------------------===//

// Pattern: x + 0 = x
Pattern AddIdentity {
  let zero = op<poly.constant> {
    coefficients = attr<"dense<[0]> : tensor<1xi32>">
  };
  let root = op<poly.add>(x: Value, zero);

  rewrite root with {
    replace root with x;
  };
}

// Pattern: x * 1 = x
Pattern MulIdentity {
  let one = op<poly.constant> {
    coefficients = attr<"dense<[1]> : tensor<1xi32>">
  };
  let root = op<poly.mul>(x: Value, one);

  rewrite root with {
    replace root with x;
  };
}

// Pattern: x * 0 = 0
Pattern MulZero {
  let zero: Value = op<poly.constant> {
    coefficients = attr<"dense<[0]> : tensor<1xi32>">
  };
  let root = op<poly.mul>(x: Value, zero);

  rewrite root with {
    replace root with zero;
  };
}

//===----------------------------------------------------------------------===//
// Algebraic simplifications
//===----------------------------------------------------------------------===//

// Constraint: Check single use
Constraint HasOneUse(value: Value) [{
  return success(value.hasOneUse());
}];

// Pattern: x² - y² = (x+y)(x-y)
Pattern DifferenceOfSquares {
  let lhs_mul: Op = op<poly.mul>(x: Value, x: Value);
  let rhs_mul: Op = op<poly.mul>(y: Value, y: Value);
  let root = op<poly.sub>(lhs_mul, rhs_mul);

  require HasOneUse(lhs_mul);
  require HasOneUse(rhs_mul);

  rewrite root with {
    let sum = op<poly.add>(x, y);
    let diff = op<poly.sub>(x, y);
    replace root with op<poly.mul>(sum, diff);
  };
}

// Pattern: (a + b) + c = a + (b + c) [Reassociation]
Pattern ReassociateAdd {
  let root = op<poly.add>(
    inner: op<poly.add>(a: Value, b: Value),
    c: Value
  );

  rewrite root with {
    let new_inner = op<poly.add>(b, c);
    replace root with op<poly.add>(a, new_inner);
  };
}

//===----------------------------------------------------------------------===//
// Constant normalization
//===----------------------------------------------------------------------===//

// Pattern: const + x = x + const
Pattern NormalizeAddConstant {
  let const_val: Op = op<poly.constant>;
  let root = op<poly.add>(const_val, x: Value);

  rewrite root with {
    replace root with op<poly.add>(x, const_val);
  };
}

//===----------------------------------------------------------------------===//
// Advanced patterns with native constraints
//===----------------------------------------------------------------------===//

Constraint GetCoefficients(op: Op) -> Attr;
Constraint IsAllZeros(attr: Attr) -> Attr;

// Pattern: Eliminate operations on zero polynomial
Pattern EliminateZeroPolynomial {
  let const_op: Op = op<poly.constant>;
  let coeffs = GetCoefficients(const_op);
  let zero_attr = IsAllZeros(coeffs);

  let root = op<poly.eval>(const_op, point: Value);

  rewrite root with {
    // Evaluating zero polynomial always gives zero
    replace root with op<arith.constant> {value = zero_attr};
  };
}
```

### Build and Test

```powershell
# Build with PDLL patterns
cd D:\repos\mlir-tutorial\build
ninja MLIRPoly

# Check generated file
cat .\lib\Dialect\Poly\PolyPatterns.cpp.inc | Select-String "Pattern"

# Test patterns
.\bin\tutorial-opt.exe ..\tests\poly_patterns.mlir --canonicalize
```

### Test File

**File: `tests/poly_patterns.mlir`**

```mlir
// RUN: tutorial-opt %s --canonicalize | FileCheck %s

module {
  // CHECK-LABEL: @identity_add
  func.func @identity_add(%x: !poly.poly<4>) -> !poly.poly<4> {
    // CHECK-NOT: poly.add
    // CHECK: return %arg0
    %zero = poly.constant dense<[0]> : !poly.poly<4>
    %result = poly.add %x, %zero : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    return %result : !poly.poly<4>
  }

  // CHECK-LABEL: @difference_of_squares
  func.func @difference_of_squares(%x: !poly.poly<4>, %y: !poly.poly<4>)
      -> !poly.poly<4> {
    // CHECK: %[[SUM:.*]] = poly.add
    // CHECK: %[[DIFF:.*]] = poly.sub
    // CHECK: %[[RESULT:.*]] = poly.mul %[[SUM]], %[[DIFF]]
    // CHECK: return %[[RESULT]]
    %x2 = poly.mul %x, %x : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    %y2 = poly.mul %y, %y : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    %result = poly.sub %x2, %y2 : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    return %result : !poly.poly<4>
  }
}
```

## Runtime Pattern Loading

For extensibility, load PDLL patterns at runtime.

**File: `tools/tutorial-opt-dynamic.cpp`**

```cpp
#include "mlir/Tools/PDLL/PDLLMain.h"
#include "mlir/IR/MLIRContext.h"

int main(int argc, char **argv) {
  MLIRContext context;

  // Load PDLL bytecode file
  auto patternModule = pdll::PDLPatternModule::fromFile("patterns.pdlb", &context);
  if (!patternModule) {
    llvm::errs() << "Failed to load PDLL patterns\n";
    return 1;
  }

  // Register patterns
  RewritePatternSet patterns(&context);
  patternModule->registerRewritePatterns(patterns);

  // Apply patterns...
  return 0;
}
```

## Debugging PDLL

### View Generated PDL IR

```powershell
# Generate PDL IR to see internals
mlir-pdll patterns.pdll -x=mlir -o patterns.pdl

# View the PDL operations
cat patterns.pdl
```

**Example output:**
```mlir
pdl.pattern @AddIdentity : benefit(1) {
  %zero = pdl.operation "poly.constant" { coefficients = dense<[0]> }
  %x = pdl.operand
  %root = pdl.operation "poly.add"(%x, %zero : !pdl.value, !pdl.value)

  pdl.rewrite %root {
    pdl.replace %root with %x
  }
}
```

### Enable Verbose Output

```powershell
# Show pattern compilation details
mlir-pdll patterns.pdll -x=cpp --debug -o patterns.cpp.inc
```

### Test Individual Patterns

Extract single pattern to separate file for testing:

```pdll
// test_pattern.pdll - Single pattern for testing
#include "Dialect/Poly/PolyOps.td"

Pattern TestPattern {
  let root = op<poly.add>(x: Value, y: Value);
  rewrite root with {
    replace root with x;
  };
}
```

## Performance Comparison

### Bytecode vs C++

**Bytecode advantages:**
- **~10x smaller** binary size
- **Runtime loading** - No recompilation
- **Dynamic patterns** - Update without rebuilding
- **Faster compilation** - Generates less code

**C++ advantages:**
- **Faster execution** - Native code
- **Static analysis** - Compiler optimizations
- **Debugging** - Better stack traces
- **Type safety** - Compile-time checks

**Recommendation:** Use bytecode for development, C++ for production.

## Key Takeaways

**Conceptual:**

✅ **Interpretation over compilation is a deliberate trade-off:** PDLL chooses bytecode execution instead of C++ generation to enable three capabilities: user-provided patterns without recompilation, 10x binary size reduction, and joint optimization across pattern sets. The performance cost of interpretation is amortized when pattern sets share redundant operand/attribute access.

✅ **Declarative with escape hatches:** PDLL doesn't dogmatically enforce pure declarativity. The native constraint mechanism explicitly allows "anything [PDLL] doesn't support" to drop into C++ implementations. The philosophy: **declare what you can, shell out to imperative code where necessary**. This pragmatism acknowledges that pattern languages cannot anticipate every domain need.

✅ **Evolution from TableGen's limitations:** DRR breaks on fundamental IR constructs, multi-result operations, regions, variadic operands, constant arithmetic during matching. PDLL exists because these aren't edge cases; they're structural features of real dialects. The language represents MLIR's admission that TableGen was the wrong abstraction for complex pattern matching.

✅ **Extensibility as architectural goal:** The bytecode model reframes pattern matching from compile-time artifact (DRR generates C++) to runtime service (PDLL loads bytecode). This shift enables a future where "the user [can pass] their own patterns to the compiler without having to rebuild it", treating optimization as configuration rather than compilation.

✅ **Incomplete but evolving:** Jeremy's honest assessment notes missing features (arithmetic/logic/comparison have RFCs but aren't implemented, regions and dialect conversion have no RFC yet) and unclear documentation requiring implementer consultation. PDLL is a work-in-progress, not a finished specification.

**Practical:**

✅ **Three output formats** serve different needs: C++ for static compilation and max performance, PDL IR for debugging and inspection, bytecode for runtime loading and size

✅ **mlir-pdll tool** compiles `.pdll` source to any format with `-x=cpp|mlir|bytecode`

✅ **Native constraints** bridge PDLL declarations with C++ implementations for domain-specific logic not expressible in the pattern language

✅ **Pattern benefits** assign priorities controlling application order when multiple patterns match

✅ **CMake integration** via custom functions enables automatic PDLL compilation during build

## Next Steps

1. **Implement PDLL patterns** for your dialect
2. **Study examples** in MLIR source: `mlir/test/lib/Dialect/Test/TestPatterns.pdll`
3. **Benchmark** bytecode vs C++ performance
4. **Experiment with runtime loading** for extensible tools
5. **Combine with dataflow analysis** for advanced optimizations
6. **Build pattern libraries** that can be shared across projects

## Additional Resources

- **PDLL Documentation:** [mlir.llvm.org/docs/PDLL/](https://mlir.llvm.org/docs/PDLL/)
- **PDL Dialect:** [mlir.llvm.org/docs/Dialects/PDLOps/](https://mlir.llvm.org/docs/Dialects/PDLOps/)
- **Pattern Rewriting:** [mlir.llvm.org/docs/PatternRewriter/](https://mlir.llvm.org/docs/PatternRewriter/)
- **PDLL Examples:** Check `mlir/test/lib/Dialect/Test/` in LLVM source
- **Original Article:** [jeremykun.com](https://www.jeremykun.com/2024/08/04/mlir-pdll/)

---

**Previous:** [← Tutorial 12: Dataflow Analysis](12-dataflow-analysis.md)

**🎉 Congratulations!** You've completed the MLIR Tutorial Series for Windows!

## What's Next?

Now that you've mastered MLIR fundamentals, consider:

1. **Build your own dialect** for a specific domain (ML, DSP, graphics, etc.)
2. **Contribute to LLVM/MLIR** - The community welcomes contributions
3. **Explore MLIR dialects** - Study Linalg, Vector, GPU, and others
4. **Join the community** - LLVM Discourse, Discord, GitHub discussions
5. **Read research papers** - Stay updated on latest MLIR developments

### Community Resources

- **LLVM Discourse:** [discourse.llvm.org](https://discourse.llvm.org/)
- **MLIR Discord:** [discord.gg/xS7Z362](https://discord.gg/xS7Z362)
- **GitHub Discussions:** [github.com/llvm/llvm-project/discussions](https://github.com/llvm/llvm-project/discussions)
- **Weekly Meetings:** Check LLVM calendar for MLIR open meetings

### Advanced Topics to Explore

- **Linalg dialect** - Structured linear algebra operations
- **Vector dialect** - SIMD and vector operations
- **GPU dialect** - GPU kernel generation
- **Transform dialect** - Programmatic IR transformations
- **Async dialect** - Asynchronous execution
- **Affine dialect** - Polyhedral optimizations

**Happy Hacking! 🚀**

---

**[← Back to Tutorial Index](README.md)**
