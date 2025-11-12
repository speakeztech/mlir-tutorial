# Tutorial 10: Dialect Conversion

**Original Article:** [MLIR — Dialect Conversion](https://jeremykun.com/2023/10/23/mlir-dialect-conversion/) by Jeremy Kun

**Windows Adaptation:** Focus on systematic dialect conversion framework with CMake build integration.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 💡 What You'll Learn

- Understanding the **dialect conversion framework**
- Implementing **type converters** for cross-dialect types
- Writing **conversion patterns** with `ConversionTarget`
- Handling **partial vs full conversion**
- Using **materialization hooks** for type conflicts
- Converting **structural operations** (func, scf, etc.)
- Integrating **conversion passes** with CMake

## The Type Obstacle: Why Naive Lowering Fails

Here's a problem that seems simple at first: you want to convert operations from one dialect to another. Just write patterns that replace operations, right?

**Not quite.** There's a fundamental obstacle that makes dialect conversion qualitatively different from pattern rewriting: **the type coordination problem**.

### The Coordination Problem

Consider this lowering task:

```mlir
// Original: Poly dialect
func.func @example(%p: !poly.poly<10>) -> !poly.poly<10> {
  %c = poly.constant dense<[1, 2, 3]> : !poly.poly<10>
  %result = poly.add %p, %c : (!poly.poly<10>, !poly.poly<10>) -> !poly.poly<10>
  return %result : !poly.poly<10>
}

// Goal: Lower to Tensor dialect
func.func @example(%p: tensor<10xi32>) -> tensor<10xi32> {
  %c = arith.constant dense<[1, 2, 3]> : tensor<10xi32>
  %result = tensor.add %p, %c : (tensor<10xi32>, tensor<10xi32>) -> tensor<10xi32>
  return %result : tensor<10xi32>
}
```

**Naive approach:** "I'll just write patterns to replace each operation."

**What happens:**

```mlir
// Step 1: Pattern converts poly.constant
%c = arith.constant dense<[1, 2, 3]> : tensor<10xi32>  // ✓ Converted
%result = poly.add %p, %c : (!poly.poly<10>, tensor<10xi32>) -> !poly.poly<10>
                         // ❌ TYPE MISMATCH!
```

**The problem:** Once you change a value's type, all downstream users expecting the old type become invalid. The IR is transiently broken.

**Why this matters:**
1. MLIR verification runs between passes
2. Invalid IR triggers assertion failures
3. Debugging is nearly impossible (which rewrite broke what?)
4. You're fighting the infrastructure instead of using it

This is the **type obstacle**—a coordination problem that requires special infrastructure.

### What Makes Conversion Different From Rewriting

**Standard pattern rewriting:**
- Operations are independent
- Each pattern can fire in isolation
- No global coordination needed
- Types remain stable

**Dialect conversion:**
- Operations are interdependent through types
- Patterns must coordinate type changes
- Global ordering matters
- Types evolve during transformation

As Jeremy Kun notes, dialect conversion would be "essentially the same as a normal pass" except for this coordination requirement. The conversion framework exists specifically to manage this complexity.

### The Dialect Conversion Framework Solution

MLIR provides infrastructure that solves the type obstacle through three mechanisms:

**1. Ordered Processing**
The framework "lowers ops in a certain sorted order, converting the types as they go, and giving the op converters access to both the original types of each op as well as what the in-progress converted types look like."

You don't manually sequence rewrites—the framework manages dependencies.

**2. Type Materialization**
When type conflicts arise, the framework can "insert new intermediate ops that resolve type conflicts" through materializer hooks.

Bridge operations like `poly.from_tensor` and `poly.to_tensor` appear automatically when needed.

**3. Staged Verification**
The framework maintains IR validity throughout conversion, allowing MLIR's verifiers to run without failing on partial transformations.

**The key insight:** Rather than hand-coding type-conflict resolution across all patterns, the framework centralizes this concern. You declare what types convert to what, and the framework handles coordination.

## Core Components

### Component 1: TypeConverter

**Defines mappings between source and target types.**

**File: `lib/Conversion/PolyToStandard/TypeConversion.h`**

```cpp
#ifndef POLY_TYPE_CONVERSION_H
#define POLY_TYPE_CONVERSION_H

#include "mlir/Transforms/DialectConversion.h"
#include "Dialect/Poly/PolyTypes.h"

namespace mlir {
namespace tutorial {

class PolyToStandardTypeConverter : public TypeConverter {
public:
  PolyToStandardTypeConverter(MLIRContext *ctx);
};

} // namespace tutorial
} // namespace mlir

#endif // POLY_TYPE_CONVERSION_H
```

**File: `lib/Conversion/PolyToStandard/TypeConversion.cpp`**

```cpp
#include "TypeConversion.h"
#include "Dialect/Poly/PolyTypes.h"
#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;
using namespace mlir::tutorial;
using namespace mlir::tutorial::poly;

PolyToStandardTypeConverter::PolyToStandardTypeConverter(MLIRContext *ctx) {
  // Rule 1: Keep all types unchanged by default
  addConversion([](Type type) { return type; });

  // Rule 2: Convert polynomial types to tensors
  addConversion([ctx](PolynomialType type) -> Type {
    int degreeBound = type.getDegreeBound();
    auto elementType = IntegerType::get(ctx, 32);  // i32 coefficients
    return RankedTensorType::get({degreeBound}, elementType);
  });

  // Rule 3: (Optional) Convert poly functions
  addConversion([this](FunctionType type) -> Type {
    // Convert function signatures
    SmallVector<Type> inputs;
    if (failed(convertTypes(type.getInputs(), inputs)))
      return nullptr;

    SmallVector<Type> results;
    if (failed(convertTypes(type.getResults(), results)))
      return nullptr;

    return FunctionType::get(type.getContext(), inputs, results);
  });
}
```

**How it works:**

1. **Identity conversion**: Most types pass through unchanged
2. **Custom conversions**: Specific types get custom mappings
3. **Recursive conversion**: Function types converted recursively
4. **First match wins**: Conversions checked in registration order

### Component 2: ConversionTarget

**Declares which operations are legal after conversion.**

```cpp
ConversionTarget target(getContext());

// Dialect-level legality
target.addIllegalDialect<PolyDialect>();       // Must be removed
target.addLegalDialect<TensorDialect>();       // Can remain
target.addLegalDialect<ArithDialect>();        // Can remain
target.addLegalDialect<func::FuncDialect>();   // Can remain

// Operation-level legality
target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
  // Function is legal if all types are converted
  return typeConverter.isSignatureLegal(op.getFunctionType());
});

target.addDynamicallyLegalOp<func::ReturnOp>([&](func::ReturnOp op) {
  // Return is legal if all operand types are converted
  return typeConverter.isLegal(op.getOperandTypes());
});
```

**Legality modes:**

- **`addIllegalDialect`**: All ops from this dialect must be converted
- **`addLegalDialect`**: All ops from this dialect can remain
- **`addDynamicallyLegalOp`**: Custom predicate determines legality

### Component 3: ConversionPatterns

**Rewrites operations while handling type conversion.**

**File: `lib/Conversion/PolyToStandard/PolyToStandard.cpp`**

```cpp
#include "mlir/Transforms/DialectConversion.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "Dialect/Poly/PolyOps.h"
#include "TypeConversion.h"

using namespace mlir;
using namespace mlir::tutorial;
using namespace mlir::tutorial::poly;

//===----------------------------------------------------------------------===//
// ConversionPattern for poly.constant
//===----------------------------------------------------------------------===//

struct ConvertPolyConstant : public OpConversionPattern<ConstantOp> {
  using OpConversionPattern<ConstantOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      ConstantOp op,
      OpAdaptor adaptor,  // Contains type-converted operands
      ConversionPatternRewriter &rewriter) const override {

    // Get the target type (converted automatically by framework)
    auto targetType = getTypeConverter()->convertType(op.getType());
    if (!targetType)
      return failure();

    // Original coefficients are already correct format
    auto coeffs = op.getCoefficients();

    // Create arith.constant with tensor type
    rewriter.replaceOpWithNewOp<arith::ConstantOp>(
        op, targetType, coeffs);

    return success();
  }
};

//===----------------------------------------------------------------------===//
// ConversionPattern for poly.add
//===----------------------------------------------------------------------===//

struct ConvertPolyAdd : public OpConversionPattern<AddOp> {
  using OpConversionPattern<AddOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      AddOp op,
      OpAdaptor adaptor,  // Operands are already type-converted!
      ConversionPatternRewriter &rewriter) const override {

    // Get converted operands from adaptor
    Value lhs = adaptor.getLhs();  // Now tensor<10xi32>, not !poly.poly<10>
    Value rhs = adaptor.getRhs();  // Now tensor<10xi32>, not !poly.poly<10>

    // Get target result type
    auto targetType = getTypeConverter()->convertType(op.getType());

    // Create elementwise tensor addition
    // Note: This is simplified - real implementation might need more ops
    rewriter.replaceOpWithNewOp<arith::AddIOp>(op, lhs, rhs);

    return success();
  }
};

//===----------------------------------------------------------------------===//
// ConversionPattern for poly.mul
//===----------------------------------------------------------------------===//

struct ConvertPolyMul : public OpConversionPattern<MulOp> {
  using OpConversionPattern<MulOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      MulOp op,
      OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {

    Value lhs = adaptor.getLhs();
    Value rhs = adaptor.getRhs();

    // Polynomial multiplication requires convolution
    // This is complex - simplified here
    auto targetType = getTypeConverter()->convertType(op.getType());
    int degreeBound = op.getType().cast<PolynomialType>().getDegreeBound();

    // Create a series of operations to implement polynomial multiplication
    // (extract, multiply pairs, reduce modulo x^D, accumulate)
    // Implementation omitted for brevity
    Value result = implementPolynomialMultiplication(
        rewriter, op.getLoc(), lhs, rhs, degreeBound, targetType);

    rewriter.replaceOp(op, result);
    return success();
  }

private:
  Value implementPolynomialMultiplication(
      ConversionPatternRewriter &rewriter,
      Location loc,
      Value lhs,
      Value rhs,
      int degreeBound,
      Type resultType) const {
    // Detailed implementation would go here
    // For now, this is a placeholder
    return Value();
  }
};
```

**Key insight:** `OpAdaptor` provides **already-converted operands**. The framework handles type conversion automatically!

### Component 4: The Conversion Pass

**Orchestrates the entire conversion.**

**File: `lib/Conversion/PolyToStandard/PolyToStandard.cpp`**

```cpp
//===----------------------------------------------------------------------===//
// Pass Definition
//===----------------------------------------------------------------------===//

namespace {
struct ConvertPolyToStandardPass
    : public PassWrapper<ConvertPolyToStandardPass, OperationPass<ModuleOp>> {

  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ConvertPolyToStandardPass)

  StringRef getArgument() const final { return "convert-poly-to-standard"; }
  StringRef getDescription() const final {
    return "Lower Poly dialect to Standard/Tensor/Arith dialects";
  }

  void runOnOperation() override {
    MLIRContext *context = &getContext();
    ModuleOp module = getOperation();

    // Step 1: Create type converter
    PolyToStandardTypeConverter typeConverter(context);

    // Step 2: Define conversion target
    ConversionTarget target(*context);

    // Poly dialect is illegal (must be lowered)
    target.addIllegalDialect<PolyDialect>();

    // Standard dialects are legal (can remain)
    target.addLegalDialect<TensorDialect>();
    target.addLegalDialect<ArithDialect>();
    target.addLegalDialect<func::FuncDialect>();

    // Functions need special handling - legal only if types are converted
    target.addDynamicallyLegalOp<func::FuncOp>([&](func::FuncOp op) {
      return typeConverter.isSignatureLegal(op.getFunctionType()) &&
             typeConverter.isLegal(&op.getBody());
    });

    target.addDynamicallyLegalOp<func::ReturnOp>([&](func::ReturnOp op) {
      return typeConverter.isLegal(op.getOperandTypes());
    });

    // Step 3: Populate conversion patterns
    RewritePatternSet patterns(context);
    patterns.add<
        ConvertPolyConstant,
        ConvertPolyAdd,
        ConvertPolyMul>(typeConverter, context);

    // Add function signature conversion patterns (built-in)
    populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(
        patterns, typeConverter);
    populateCallOpTypeConversionPattern(patterns, typeConverter);
    populateReturnOpTypeConversionPattern(patterns, typeConverter);

    // Step 4: Apply conversion
    if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};
} // namespace

//===----------------------------------------------------------------------===//
// Pass Registration
//===----------------------------------------------------------------------===//

void mlir::tutorial::registerConvertPolyToStandardPass() {
  PassRegistration<ConvertPolyToStandardPass>();
}
```

## Partial vs Full Conversion

MLIR provides two conversion strategies:

### Partial Conversion

```cpp
if (failed(applyPartialConversion(module, target, patterns))) {
  signalPassFailure();
}
```

**Behavior:**
- Converts operations marked illegal
- **Allows legal operations to remain**
- **Better error messages** - Shows what failed to convert
- **Recommended for most cases**

**Use when:**
- You're lowering incrementally
- Only specific operations need conversion
- You want clear error messages

### Full Conversion

```cpp
if (failed(applyFullConversion(module, target, patterns))) {
  signalPassFailure();
}
```

**Behavior:**
- Converts **all** operations using patterns
- **Fails if any operation lacks a pattern**
- Stricter requirements

**Use when:**
- Complete dialect conversion required
- No original dialect operations can remain
- Final lowering stage

### Greedy Conversion

```cpp
if (failed(applyGreedyConversion(module, patterns))) {
  signalPassFailure();
}
```

**Behavior:**
- Applies patterns until fixed point
- **No legality checking** - Applies any matching pattern
- Useful for canonicalization-like rewrites

## Materialization: Bridging Type Gaps

Sometimes type conversion creates **temporary incompatibilities**. Materialization hooks insert bridge operations.

### The Problem

```mlir
// After converting poly.add but before converting poly.eval:
%tensor = arith.constant dense<[1, 2, 3]> : tensor<10xi32>  // Converted
%result = poly.eval %poly, %tensor : (!poly.poly<10>, tensor<10xi32>)
                                   // ^^^ Type mismatch!
```

The `poly.eval` expects `!poly.poly<10>`, but we have `tensor<10xi32>`.

### Solution: Materialization Hooks

**Three types of materialization:**

1. **Source materialization**: Convert FROM target type TO source type
2. **Target materialization**: Convert FROM source type TO target type
3. **Argument materialization**: Convert function arguments

**File: `TypeConversion.cpp`**

```cpp
PolyToStandardTypeConverter::PolyToStandardTypeConverter(MLIRContext *ctx) {
  // ... existing conversions ...

  // Source materialization: tensor → poly
  // Used when unconverted ops need original types
  addSourceMaterialization([](OpBuilder &builder, Type resultType,
                              ValueRange inputs, Location loc) -> Value {
    if (inputs.size() != 1)
      return nullptr;

    // Check if converting tensor back to polynomial
    if (resultType.isa<PolynomialType>() &&
        inputs[0].getType().isa<RankedTensorType>()) {
      // Insert poly.from_tensor operation
      return builder.create<poly::FromTensorOp>(loc, resultType, inputs[0]);
    }

    return nullptr;
  });

  // Target materialization: poly → tensor
  // Used when converting to target types
  addTargetMaterialization([](OpBuilder &builder, Type resultType,
                              ValueRange inputs, Location loc) -> Value {
    if (inputs.size() != 1)
      return nullptr;

    // Check if converting polynomial to tensor
    if (inputs[0].getType().isa<PolynomialType>() &&
        resultType.isa<RankedTensorType>()) {
      // Insert poly.to_tensor operation
      return builder.create<poly::ToTensorOp>(loc, resultType, inputs[0]);
    }

    return nullptr;
  });

  // Argument materialization: Used for block arguments
  addArgumentMaterialization([](OpBuilder &builder, Type resultType,
                                ValueRange inputs, Location loc) -> Value {
    // Usually same as target materialization
    if (inputs.size() != 1)
      return nullptr;

    if (inputs[0].getType().isa<PolynomialType>() &&
        resultType.isa<RankedTensorType>()) {
      return builder.create<poly::ToTensorOp>(loc, resultType, inputs[0]);
    }

    return nullptr;
  });
}
```

### How Materialization Works

**Example flow:**

```mlir
// Original
%poly = poly.constant dense<[1, 2]> : !poly.poly<10>
%eval = poly.eval %poly, %z : (!poly.poly<10>, complex<f64>)

// After converting poly.constant but not poly.eval:
%tensor = arith.constant dense<[1, 2]> : tensor<10xi32>
%poly_materialized = poly.from_tensor %tensor : tensor<10xi32> -> !poly.poly<10>
%eval = poly.eval %poly_materialized, %z : (!poly.poly<10>, complex<f64>)

// After converting poly.eval:
%tensor = arith.constant dense<[1, 2]> : tensor<10xi32>
// Materialization operations cleaned up - no longer needed
```

The framework:
1. Inserts materializations when needed
2. Removes them when no longer necessary
3. Ensures IR validity throughout

### Cleanup Pass

After conversion, unrealized casts may remain:

```cpp
// Add to pass pipeline
pm.addPass(createReconcileUnrealizedCastsPass());
```

This removes `builtin.unrealized_conversion_cast` operations once types are consistent.

## Converting Structural Operations

Operations containing regions (functions, loops, conditionals) require special handling.

### Function Conversion

**File: `lib/Conversion/PolyToStandard/PolyToStandard.cpp`**

```cpp
void ConvertPolyToStandardPass::runOnOperation() {
  // ... setup ...

  // Use built-in helper for function conversion
  populateFunctionOpInterfaceTypeConversionPattern<func::FuncOp>(
      patterns, typeConverter);

  // This handles:
  // 1. Converting function signatures
  // 2. Converting block arguments
  // 3. Updating function types in callers
}
```

**What it does:**

```mlir
// Before
func.func @process(%arg: !poly.poly<10>) -> !poly.poly<10> {
  %result = poly.mul %arg, %arg : (!poly.poly<10>, !poly.poly<10>)
                                -> !poly.poly<10>
  return %result : !poly.poly<10>
}

// After
func.func @process(%arg: tensor<10xi32>) -> tensor<10xi32> {
  %result = arith.muli %arg, %arg : tensor<10xi32>
  return %result : tensor<10xi32>
}
```

### Loop Conversion (SCF)

For `scf.for`, `scf.while`, `scf.if`:

```cpp
#include "mlir/Dialect/SCF/Transforms/Passes.h"

void ConvertPolyToStandardPass::runOnOperation() {
  // ... existing setup ...

  // SCF operations need special handling for region arguments
  target.addDynamicallyLegalOp<scf::ForOp, scf::WhileOp, scf::IfOp>(
      [&](Operation *op) {
        return typeConverter.isLegal(op);
      });

  // Add SCF conversion patterns
  scf::populateSCFStructuralTypeConversionsAndLegality(
      typeConverter, patterns, target);
}
```

### Custom Region Operations

For your own operations with regions:

```cpp
struct ConvertPolyRegionOp : public OpConversionPattern<MyRegionOp> {
  using OpConversionPattern<MyRegionOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      MyRegionOp op,
      OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {

    // Convert region signature
    TypeConverter::SignatureConversion signatureConversion(
        op.getRegion().getNumArguments());

    for (auto [index, type] : llvm::enumerate(
            op.getRegion().getArgumentTypes())) {
      auto convertedType = getTypeConverter()->convertType(type);
      if (!convertedType)
        return failure();
      signatureConversion.addInputs(index, convertedType);
    }

    // Apply conversion to region
    if (failed(rewriter.convertRegionTypes(
            &op.getRegion(),
            *getTypeConverter(),
            &signatureConversion)))
      return failure();

    // Create new operation with converted types
    auto newOp = rewriter.create<MyRegionOp>(
        op.getLoc(),
        getTypeConverter()->convertType(op.getType()),
        adaptor.getOperands());

    // Move converted region
    rewriter.inlineRegionBefore(op.getRegion(), newOp.getRegion(),
                               newOp.getRegion().end());

    rewriter.replaceOp(op, newOp);
    return success();
  }
};
```

## Complete Example: End-to-End Conversion

Let's walk through a complete example.

### Input MLIR

**File: `test_conversion.mlir`**

```mlir
module {
  func.func @polynomial_math(%x: !poly.poly<4>, %y: !poly.poly<4>)
      -> !poly.poly<4> {
    %c = poly.constant dense<[1, 0, 0, 0]> : !poly.poly<4>
    %sum = poly.add %x, %y : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    %result = poly.mul %sum, %c : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    return %result : !poly.poly<4>
  }
}
```

### Expected Output

**After conversion:**

```mlir
module {
  func.func @polynomial_math(%x: tensor<4xi32>, %y: tensor<4xi32>)
      -> tensor<4xi32> {
    %c = arith.constant dense<[1, 0, 0, 0]> : tensor<4xi32>
    %sum = arith.addi %x, %y : tensor<4xi32>
    %result = arith.muli %sum, %c : tensor<4xi32>
    return %result : tensor<4xi32>
  }
}
```

### Running the Conversion

```powershell
# Before conversion
.\build\bin\tutorial-opt.exe test_conversion.mlir

# Apply conversion pass
.\build\bin\tutorial-opt.exe test_conversion.mlir --convert-poly-to-standard

# Verify with FileCheck
.\build\bin\tutorial-opt.exe test_conversion.mlir --convert-poly-to-standard | `
  FileCheck test_conversion.mlir
```

### FileCheck Annotations

**File: `test_conversion.mlir`**

```mlir
// RUN: tutorial-opt %s --convert-poly-to-standard | FileCheck %s

module {
  // CHECK-LABEL: func.func @polynomial_math
  // CHECK-SAME: (%[[X:.*]]: tensor<4xi32>, %[[Y:.*]]: tensor<4xi32>)
  // CHECK-SAME: -> tensor<4xi32>
  func.func @polynomial_math(%x: !poly.poly<4>, %y: !poly.poly<4>)
      -> !poly.poly<4> {

    // CHECK: %[[C:.*]] = arith.constant dense<[1, 0, 0, 0]> : tensor<4xi32>
    %c = poly.constant dense<[1, 0, 0, 0]> : !poly.poly<4>

    // CHECK: %[[SUM:.*]] = arith.addi %[[X]], %[[Y]] : tensor<4xi32>
    %sum = poly.add %x, %y : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>

    // CHECK: %[[RESULT:.*]] = arith.muli %[[SUM]], %[[C]] : tensor<4xi32>
    %result = poly.mul %sum, %c : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>

    // CHECK: return %[[RESULT]] : tensor<4xi32>
    return %result : !poly.poly<4>
  }
}
```

## CMake Integration

### Directory Structure

```
lib/Conversion/
├── PolyToStandard/
│   ├── CMakeLists.txt
│   ├── PolyToStandard.cpp
│   ├── TypeConversion.h
│   └── TypeConversion.cpp
```

### File: `lib/Conversion/PolyToStandard/CMakeLists.txt`

```cmake
add_mlir_library(MLIRPolyToStandardConversion
  PolyToStandard.cpp
  TypeConversion.cpp

  DEPENDS
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRTransforms
  MLIRFuncDialect
  MLIRTensorDialect
  MLIRArithDialect
  MLIRSCFDialect
  MLIRPoly  # Our dialect
)
```

### File: `lib/Conversion/CMakeLists.txt`

```cmake
add_subdirectory(PolyToStandard)
```

### File: `lib/CMakeLists.txt`

```cmake
add_subdirectory(Dialect)
add_subdirectory(Transform)
add_subdirectory(Conversion)  # Add this line
```

### Register Pass in `tutorial-opt`

**File: `tools/tutorial-opt.cpp`**

```cpp
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/IR/MLIRContext.h"
#include "Dialect/Poly/PolyDialect.h"
#include "Conversion/PolyToStandard/PolyToStandard.h"  // Add this

// Forward declarations
void registerConvertPolyToStandardPass();  // Add this

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;

  // Register dialects
  registry.insert<mlir::tutorial::poly::PolyDialect>();
  registry.insert<mlir::func::FuncDialect>();
  registry.insert<mlir::tensor::TensorDialect>();
  registry.insert<mlir::arith::ArithDialect>();

  // Register passes
  registerConvertPolyToStandardPass();  // Add this

  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Tutorial optimizer\n", registry));
}
```

### Build and Test

```powershell
cd D:\repos\mlir-tutorial\build
ninja tutorial-opt

# Test conversion
.\bin\tutorial-opt.exe ..\tests\test_conversion.mlir --convert-poly-to-standard

# Run test suite
ninja check-mlir-tutorial
```

## Advanced Topics

### Conversion Adaptor Details

The `OpAdaptor` provides converted operands:

```cpp
struct ConvertMyOp : public OpConversionPattern<MyOp> {
  LogicalResult matchAndRewrite(
      MyOp op,
      OpAdaptor adaptor,
      ConversionPatternRewriter &rewriter) const override {

    // Original operation has !poly.poly<10> operands
    // adaptor.getLhs() returns tensor<10xi32> (converted!)

    Value lhs = adaptor.getLhs();  // Already converted type
    Value rhs = adaptor.getRhs();  // Already converted type

    // If you need original types:
    Type originalType = op.getLhs().getType();  // !poly.poly<10>

    // ...
  }
};
```

### Multi-Stage Conversion

Sometimes you need multiple conversion passes:

```cpp
void buildPipeline(OpPassManager &pm) {
  // Stage 1: Poly → Tensor/Arith
  pm.addPass(createConvertPolyToStandardPass());

  // Cleanup unrealized casts
  pm.addPass(createReconcileUnrealizedCastsPass());

  // Stage 2: Tensor → MemRef
  pm.addPass(createConvertTensorToMemRefPass());

  // Stage 3: MemRef + Arith → LLVM
  pm.addPass(createConvertToLLVMPass());
}
```

### Type Conversion with Attributes

Sometimes attributes need conversion too:

```cpp
addConversion([](MyAttributeType attr) -> Attribute {
  // Convert attribute values
  return convertMyAttribute(attr);
});
```

### Debugging Conversion

```powershell
# See what patterns apply
.\build\bin\tutorial-opt.exe test.mlir --convert-poly-to-standard `
  --mlir-print-ir-after-all

# Show pattern application details
.\build\bin\tutorial-opt.exe test.mlir --convert-poly-to-standard `
  --debug-only=dialect-conversion

# Check for unrealized casts
.\build\bin\tutorial-opt.exe test.mlir --convert-poly-to-standard | `
  Select-String "unrealized_conversion_cast"
```

## Common Pitfalls

### 1. Forgetting Materialization Hooks

**Problem:**
```
error: failed to legalize operation 'builtin.unrealized_conversion_cast'
```

**Solution:** Add source/target materialization hooks to `TypeConverter`.

### 2. Incorrect Legality Specification

**Problem:**
```
error: pattern failed to match
```

**Solution:** Check `ConversionTarget` - ensure operations are marked correctly.

### 3. Missing Conversion Patterns

**Problem:**
```
error: unable to convert type '!poly.poly<10>'
```

**Solution:** Add conversion pattern for the operation or type.

### 4. Transitive Dependencies

**Problem:** Converting `poly.add` works, but `poly.eval` fails because it uses `poly.add`.

**Solution:** Ensure all dependent operations have conversion patterns.

### 5. Region Argument Mismatch

**Problem:**
```
error: block argument types don't match
```

**Solution:** Use `populateFunctionOpInterfaceTypeConversionPattern` for proper region conversion.

## Real-World Examples

### MLIR's Built-in Conversions

Study these for reference:

**Arith to LLVM:**
```cpp
// In mlir/lib/Conversion/ArithToLLVM/ArithToLLVM.cpp
struct ConvertArithAddI : public ConvertOpToLLVMPattern<arith::AddIOp> {
  LogicalResult matchAndRewrite(...) {
    // Create LLVM::AddOp from arith::AddIOp
  }
};
```

**Tensor to Linalg:**
```cpp
// In mlir/lib/Conversion/TensorToLinalg/TensorToLinalg.cpp
struct ConvertTensorEmpty : public OpConversionPattern<tensor::EmptyOp> {
  LogicalResult matchAndRewrite(...) {
    // Create linalg.init_tensor
  }
};
```

## Key Takeaways

This tutorial explored systematic dialect conversion from both philosophical and practical perspectives:

✅ **The type obstacle is fundamental** - Changing value types breaks downstream users, requiring coordination

✅ **Naive lowering fights the infrastructure** - Sequential rewriting creates transiently invalid IR

✅ **Conversion framework manages dependencies** - Ordered processing ensures validity throughout transformation

✅ **TypeConverter is declarative** - Specify mappings once, framework applies them consistently

✅ **ConversionTarget declares legality** - Separate "what's legal" from "how to achieve it"

✅ **OpAdaptor provides converted operands** - Patterns receive already-transformed inputs automatically

✅ **Materialization resolves conflicts** - Framework inserts bridge operations when needed

✅ **Partial conversion gives better errors** - Can see steps and unresolved conflicts for debugging

✅ **Separation of concerns scales** - Type logic, operation patterns, and legality declarations are independent

✅ **Framework enables incremental lowering** - Progressive transformation through multiple dialect levels

## Next Steps

1. **[Tutorial 11: Lowering through LLVM](11-lowering-through-llvm.md)** - Generate executable code
2. **Implement conversion** from your custom dialect
3. **Study MLIR conversions** in `mlir/lib/Conversion/`
4. **Add materialization hooks** for complex type conversions
5. **Test edge cases** - multiple returns, nested regions, etc.

## Additional Resources

- **Dialect Conversion Doc:** [mlir.llvm.org/docs/DialectConversion/](https://mlir.llvm.org/docs/DialectConversion/)
- **Type Conversion:** [mlir.llvm.org/docs/Tutorials/UnderstandingTheIRStructure/#type-system](https://mlir.llvm.org/docs/Tutorials/UnderstandingTheIRStructure/#type-system)
- **ConversionTarget API:** Check `mlir/include/mlir/Transforms/DialectConversion.h`
- **Conversion Examples:** See `mlir/lib/Conversion/` directory
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/10/23/mlir-dialect-conversion/)

---

**Previous:** [← Tutorial 09: Canonicalizers](09-canonicalizers.md)
**Next:** [Tutorial 11: Lowering through LLVM →](11-lowering-through-llvm.md)
