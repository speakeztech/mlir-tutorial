# Tutorial 11: Lowering through LLVM

**Original Article:** [MLIR ,  Lowering Through LLVM](https://jeremykun.com/2023/11/01/mlir-lowering-through-llvm/) by Jeremy Kun

**Windows Adaptation:** Focus on complete lowering pipeline to LLVM IR with Windows/MSYS2 tooling and CMake integration.

---

## 🧭 Navigation Guide

This tutorial uses emojis to help you navigate:
- **📖 Reading sections** - Conceptual explanations and background
- **🔬 Examples** - Code samples and detailed examination
- **🔍 Deep dives** - Feature exploration and sage advice
- **👉 Action sections** - Commands to run and tasks to complete

---

## 💡 What You'll Learn

- Understanding the **LLVM dialect** as an exit dialect
- Building a **complete lowering pipeline**
- Handling **bufferization** (tensor → memref conversion)
- Converting **func operations** to LLVM
- Translating **MLIR to LLVM IR** with `mlir-translate`
- **Pass pipeline construction** strategies
- Integrating with **CMake build system**

## The Journey to Executable Code

Here's the reality of building compilers: **getting from high-level abstractions to machine code is messy**.

You start with operations that carry semantic meaning (`poly.mul` means polynomial multiplication). You end with CPU instructions that move bytes and flip bits. Between these extremes lies a cascade of transformations, each stripping away one layer of abstraction.

This tutorial follows that journey, honestly, including the false starts and trial-and-error that characterize real compiler development.

### The Non-Linear Problem

When Jeremy Kun describes building lowering pipelines, he's refreshingly candid: "The process I've used to build up a big pipeline is rather toilsome and incremental."

**Why is it toilsome?** Because lowering isn't a clean hierarchy. It's more like:

```
Custom Dialect → Standard Dialects → ... → LLVM Dialect → Machine Code
                    ↑                ↓
                    └─── Some passes reintroduce earlier dialects!
```

You lower to tensor operations, then discover bufferization introduces SCF loops. You convert functions to LLVM, then find control flow needs converting first. **The dependencies aren't obvious until you hit them.**

As the author notes: there "can be dozens of lowerings involved" in a complete pipeline, and ordering them correctly requires either deep knowledge of pass interactions or "embarrassing trial and error."

This is compiler engineering reality, the systematic methods exist, but practical pipeline construction remains partially artisanal.

### The LLVM Dialect: The Exit Point

The **LLVM dialect** serves a specific architectural role: it's the **exit dialect**, a known-good interface to external code generation infrastructure.

**Why not target machine code directly?**
1. **Architecture independence** - LLVM handles x86, ARM, RISC-V, etc.
2. **Mature optimizations** - Decades of optimization passes
3. **Tooling ecosystem** - Debuggers, profilers, linkers
4. **Maintenance burden** - Let LLVM handle ISA evolution

MLIR lowers to LLVM's representation, then delegates to LLVM's proven infrastructure. This is **reuse** at the architecture level.

**MLIR LLVM Dialect:**
```mlir
func.func @add(%arg0: i32, %arg1: i32) -> i32 {
  %0 = llvm.add %arg0, %arg1 : i32
  llvm.return %0 : i32
}
```

**LLVM IR (after translation):**
```llvm
define i32 @add(i32 %arg0, i32 %arg1) {
  %0 = add i32 %arg0, %arg1
  ret i32 %0
}
```

The LLVM dialect operations map directly to LLVM IR instructions. Once in LLVM IR, you're on familiar ground, the rest is standard LLVM compilation.

### The Complete Path: Abstraction to Execution

```
1. Custom Dialect (poly.mul)           ← Semantic meaning
2. Standard Dialects (arith, tensor)   ← Generic operations
3. Linear Algebra (linalg.generic)     ← Structured computation
4. Bufferization (tensor → memref)     ← Where data lives
5. Control Flow (scf → cf)             ← Explicit branches
6. LLVM Dialect (llvm.add, llvm.store) ← Machine operations
7. LLVM IR                             ← Platform-independent assembly
8. Machine Code                        ← CPU instructions
```

Each step **eliminates abstraction**. Each step **makes implicit assumptions explicit**. Each step **closes optimization opportunities** while opening execution paths.

## Building Pipelines: The Honest Assessment

Let me quote Jeremy Kun directly: "I don't have a particularly good solution here besides trial and error."

This isn't defeatism, it's honesty about the state of the art.

### The Incremental Approach

1. **Start with minimal pipeline**
2. **Run and observe failures**
3. **Add passes to resolve errors**
4. **Discover new constraints**
5. **Reorder passes**
6. **Repeat until successful**

This feels ad-hoc because it is. The alternative, planning the perfect pipeline from the start, requires encyclopedic knowledge of hundreds of passes and their interactions.

### Why Pass Ordering Is Hard

Consider a concrete example from the tutorial: moving `func-to-llvm` too early prevented `cf` lowering from completing. Why? Because `func-to-llvm` changed function signatures in ways that later passes couldn't handle.

**The problem:** Passes have implicit assumptions about their inputs. These assumptions aren't always documented. You discover them by breaking things.

**The current solution:** Experience. Familiarity with common patterns. Copying working pipelines and adapting them.

**The missing tool:** As Jeremy suggests, an automated analyzer that could "find all applicable rewrite patterns for a given op" or "construct a graph of all the possible conversions." These don't exist in standard MLIR infrastructure.

### Step 1: Initial Attempt

**File: `lib/Conversion/PolyToLLVM/PolyToLLVM.cpp`**

```cpp
#include "mlir/Pass/Pass.h"
#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/Conversion/LLVMCommon/Pattern.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

using namespace mlir;

namespace {
struct ConvertPolyToLLVMPass
    : public PassWrapper<ConvertPolyToLLVMPass, OperationPass<ModuleOp>> {

  void runOnOperation() override {
    MLIRContext *context = &getContext();
    ModuleOp module = getOperation();

    // Create empty pipeline - will fail!
    RewritePatternSet patterns(context);
    ConversionTarget target(*context);
    LLVMTypeConverter typeConverter(context);

    if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
      signalPassFailure();
    }
  }
};
} // namespace
```

**Run it:**
```powershell
.\build\bin\tutorial-opt.exe test.mlir --convert-poly-to-llvm
```

**Output:**
```
error: failed to legalize operation 'func.func' that was explicitly marked illegal
```

### Step 2: Add Function Conversion

Functions need special handling. Use MLIR's built-in helper.

```cpp
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"

void runOnOperation() override {
  MLIRContext *context = &getContext();
  ModuleOp module = getOperation();

  RewritePatternSet patterns(context);
  ConversionTarget target(*context);
  LLVMTypeConverter typeConverter(context);

  // Mark LLVM dialect as legal
  target.addLegalDialect<LLVM::LLVMDialect>();

  // Convert function operations
  populateFuncToLLVMConversionPatterns(typeConverter, patterns);

  if (failed(applyPartialConversion(module, target, std::move(patterns)))) {
    signalPassFailure();
  }
}
```

**Run again:**
```
error: failed to legalize operation 'poly.add'
```

Progress! Functions are now handled, but Poly operations remain.

### Step 3: Lower Custom Dialect First

We can't lower Poly directly to LLVM. Need intermediate step.

**Two-stage pipeline:**
```
Poly → Standard dialects → LLVM
```

**File: `tools/tutorial-opt.cpp`**

```cpp
#include "mlir/Pass/PassManager.h"

void buildPolyToLLVMPipeline(OpPassManager &pm) {
  // Stage 1: Lower custom dialect to standard dialects
  pm.addPass(createConvertPolyToStandardPass());

  // Stage 2: Lower standard dialects to LLVM
  pm.addPass(createConvertToLLVMPass());
}

// Register pipeline
void registerPipelines() {
  PassPipelineRegistration<>(
      "lower-poly-to-llvm",
      "Lower Poly dialect to LLVM IR",
      buildPolyToLLVMPipeline);
}
```

**Run pipeline:**
```powershell
.\build\bin\tutorial-opt.exe test.mlir --pass-pipeline="lower-poly-to-llvm"
```

### Step 4: Handle Tensor Operations

After Poly→Standard conversion, we have tensor operations. LLVM doesn't understand tensors.

**Problem:**
```mlir
%0 = arith.constant dense<[1, 2, 3]> : tensor<10xi32>
%1 = tensor.add %0, %0 : tensor<10xi32>
// LLVM dialect has no tensor operations!
```

**Solution: Bufferization** - Convert tensors to memrefs (memory references).

```cpp
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"

void buildPolyToLLVMPipeline(OpPassManager &pm) {
  // Stage 1: Poly → Standard
  pm.addPass(createConvertPolyToStandardPass());

  // Stage 2: Tensor → MemRef (bufferization)
  pm.addPass(bufferization::createOneShotBufferizePass());

  // Stage 3: MemRef + Arith + Func → LLVM
  pm.addPass(createConvertToLLVMPass());
}
```

## Understanding Bufferization

**Bufferization** transforms tensor operations (immutable, SSA values) into memref operations (mutable memory).

### Before Bufferization

```mlir
func.func @example(%arg: tensor<4xi32>) -> tensor<4xi32> {
  %c1 = arith.constant 1 : i32
  %result = tensor.add %arg, %c1 : tensor<4xi32>
  return %result : tensor<4xi32>
}
```

**Tensors:**
- Immutable values
- SSA form (single assignment)
- Abstract storage
- Optimize-friendly

### After Bufferization

```mlir
func.func @example(%arg: memref<4xi32>) -> memref<4xi32> {
  %c1 = arith.constant 1 : i32
  %alloc = memref.alloc() : memref<4xi32>

  // Store results in allocated memory
  %c0 = arith.constant 0 : index
  scf.for %i = %c0 to %c4 step %c1 {
    %load = memref.load %arg[%i] : memref<4xi32>
    %add = arith.addi %load, %c1 : i32
    memref.store %add, %alloc[%i] : memref<4xi32>
  }

  return %alloc : memref<4xi32>
}
```

**MemRefs:**
- Mutable memory
- Explicit loads/stores
- Concrete storage
- Maps to LLVM pointers

### One-Shot Bufferization

Modern MLIR uses **one-shot bufferization** instead of incremental passes.

```cpp
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"

void buildPipeline(OpPassManager &pm) {
  // Configure bufferization options
  bufferization::OneShotBufferizationOptions options;
  options.bufferizeFunctionBoundaries = true;

  pm.addPass(bufferization::createOneShotBufferizePass(options));
}
```

**Benefits:**
- Single analysis phase
- Better optimization opportunities
- Fewer intermediate steps
- More efficient

## Complete Lowering Pipeline

Here's a production-ready pipeline for Poly → LLVM.

### File: `lib/Conversion/PolyToLLVM/PolyToLLVM.cpp`

```cpp
#include "mlir/Pass/PassManager.h"
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"
#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"
#include "mlir/Conversion/ReconcileUnrealizedCasts/ReconcileUnrealizedCasts.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Transforms/Passes.h"

using namespace mlir;

void buildPolyToLLVMPipeline(OpPassManager &pm) {
  // Stage 1: Lower Poly dialect to Standard dialects
  pm.addPass(createConvertPolyToStandardPass());

  // Stage 2: Canonicalize and cleanup
  pm.addPass(createCanonicalizerPass());
  pm.addPass(createCSEPass());  // Common subexpression elimination

  // Stage 3: Bufferization - Tensor → MemRef
  bufferization::OneShotBufferizationOptions bufOptions;
  bufOptions.bufferizeFunctionBoundaries = true;
  pm.addPass(bufferization::createOneShotBufferizePass(bufOptions));

  // Stage 4: Cleanup after bufferization
  pm.addPass(createCanonicalizerPass());
  pm.addPass(bufferization::createBufferDeallocationSimplificationPass());
  pm.addPass(bufferization::createBufferDeallocationPass());

  // Stage 5: Lower to LLVM dialect
  pm.addPass(createConvertToLLVMPass());

  // Stage 6: Finalize conversions
  pm.addPass(createReconcileUnrealizedCastsPass());
}

void registerPolyToLLVMPipeline() {
  PassPipelineRegistration<>(
      "lower-poly-to-llvm",
      "Lower Poly dialect through standard dialects to LLVM",
      buildPolyToLLVMPipeline);
}
```

### Explanation of Each Stage

**Stage 1: Poly → Standard**
- Converts custom operations to Arith/Tensor/Func
- Type conversion: `!poly.poly<N>` → `tensor<Nxi32>`

**Stage 2: Canonicalization**
- Simplifies IR
- Removes dead code
- Combines operations
- Prepares for bufferization

**Stage 3: Bufferization**
- Tensor operations → MemRef operations
- Inserts memory allocations
- Adds explicit loads/stores
- Handles function boundaries

**Stage 4: Buffer Management**
- Simplifies allocation patterns
- Inserts deallocations (frees)
- Prevents memory leaks
- Optimizes buffer usage

**Stage 5: Lower to LLVM**
- MemRef → LLVM pointers
- Arith → LLVM arithmetic
- Func → LLVM functions
- SCF → LLVM control flow

**Stage 6: Cleanup**
- Removes unrealized casts
- Ensures type consistency
- Final verification

## Converting Individual Dialects

Let's look at specific conversion passes.

### Arith to LLVM

```cpp
#include "mlir/Conversion/ArithToLLVM/ArithToLLVM.h"

void runOnOperation() override {
  RewritePatternSet patterns(&getContext());
  LLVMTypeConverter typeConverter(&getContext());

  // Convert arith operations to LLVM
  arith::populateArithToLLVMConversionPatterns(typeConverter, patterns);

  ConversionTarget target(getContext());
  target.addLegalDialect<LLVM::LLVMDialect>();
  target.addIllegalDialect<arith::ArithDialect>();

  if (failed(applyPartialConversion(getOperation(), target, std::move(patterns))))
    signalPassFailure();
}
```

**Converts:**
- `arith.addi` → `llvm.add`
- `arith.subi` → `llvm.sub`
- `arith.muli` → `llvm.mul`
- `arith.constant` → `llvm.mlir.constant`

### MemRef to LLVM

```cpp
#include "mlir/Conversion/MemRefToLLVM/MemRefToLLVM.h"

void runOnOperation() override {
  RewritePatternSet patterns(&getContext());
  LLVMTypeConverter typeConverter(&getContext());

  // Convert memref operations to LLVM
  populateFinalizeMemRefToLLVMConversionPatterns(typeConverter, patterns);

  ConversionTarget target(getContext());
  target.addLegalDialect<LLVM::LLVMDialect>();
  target.addIllegalDialect<memref::MemRefDialect>();

  if (failed(applyPartialConversion(getOperation(), target, std::move(patterns))))
    signalPassFailure();
}
```

**Converts:**
- `memref<4xi32>` → LLVM struct with pointer and metadata
- `memref.alloc` → `llvm.mlir.alloca` or `malloc`
- `memref.load` → `llvm.load`
- `memref.store` → `llvm.store`

### Func to LLVM

```cpp
#include "mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h"

void runOnOperation() override {
  RewritePatternSet patterns(&getContext());
  LLVMTypeConverter typeConverter(&getContext());

  // Convert func operations to LLVM
  populateFuncToLLVMConversionPatterns(typeConverter, patterns);

  ConversionTarget target(getContext());
  target.addLegalDialect<LLVM::LLVMDialect>();
  target.addIllegalDialect<func::FuncDialect>();

  if (failed(applyPartialConversion(getOperation(), target, std::move(patterns))))
    signalPassFailure();
}
```

**Converts:**
- `func.func` → `llvm.func`
- `func.call` → `llvm.call`
- `func.return` → `llvm.return`

### SCF to Control Flow

```cpp
#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"

void runOnOperation() override {
  RewritePatternSet patterns(&getContext());

  // Convert SCF (structured control flow) to CF (control flow)
  populateSCFToControlFlowConversionPatterns(patterns);

  ConversionTarget target(getContext());
  target.addLegalDialect<cf::ControlFlowDialect>();
  target.addIllegalDialect<scf::SCFDialect>();

  if (failed(applyPartialConversion(getOperation(), target, std::move(patterns))))
    signalPassFailure();
}
```

**Converts:**
- `scf.for` → `cf.br` (branch) and `cf.cond_br` (conditional branch)
- `scf.if` → `cf.cond_br`
- `scf.while` → loop with `cf.br`

## Translation to LLVM IR

Once in LLVM dialect, use `mlir-translate` to generate LLVM IR.

### Using mlir-translate

**Command:**
```powershell
# MLIR → LLVM IR
.\build\bin\mlir-translate.exe `
  --mlir-to-llvmir `
  input.mlir `
  -o output.ll

# View the output
cat output.ll
```

### Example Translation

**Input: `example.mlir` (LLVM dialect)**
```mlir
module {
  llvm.func @add(%arg0: i32, %arg1: i32) -> i32 {
    %0 = llvm.add %arg0, %arg1 : i32
    llvm.return %0 : i32
  }
}
```

**Output: `example.ll` (LLVM IR)**
```llvm
; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"

define i32 @add(i32 %0, i32 %1) {
  %3 = add i32 %0, %1
  ret i32 %3
}
```

### Compiling to Machine Code

**Using LLC (LLVM static compiler):**
```powershell
# LLVM IR → Object file
llc example.ll -filetype=obj -o example.o

# Link to executable (MinGW on Windows)
gcc example.o -o example.exe
```

**Using Clang:**
```powershell
# LLVM IR → Executable
clang example.ll -o example.exe
```

## Handling Common Issues

### Issue 1: Unrealized Conversion Casts

**Problem:**
```mlir
%0 = builtin.unrealized_conversion_cast %arg : !poly.poly<10> to tensor<10xi32>
```

**Solution:**
```cpp
pm.addPass(createReconcileUnrealizedCastsPass());
```

### Issue 2: Index Type Mismatches

**Problem:**
```
error: cannot convert 'index' to 'i64'
```

**MLIR uses `index` type** for array indexing, but LLVM doesn't have it.

**Solution:**
```cpp
// In LLVMTypeConverter setup
typeConverter.addConversion([](IndexType type) {
  return IntegerType::get(type.getContext(), 64);  // index → i64
});
```

### Issue 3: Function Signature Mismatch

**Problem:**
```
error: function signature not converted
```

**Solution:** Ensure `populateFuncToLLVMConversionPatterns` is called.

### Issue 4: Missing Dialect Dependencies

**Problem:**
```
error: dialect 'llvm' is not registered
```

**Solution:**
```cpp
// In tool's main()
context.getOrLoadDialect<LLVM::LLVMDialect>();
```

## Complete End-to-End Example

### File: `examples/poly_complete.mlir`

```mlir
module {
  func.func @poly_square(%x: !poly.poly<4>) -> !poly.poly<4> {
    %result = poly.mul %x, %x : (!poly.poly<4>, !poly.poly<4>) -> !poly.poly<4>
    return %result : !poly.poly<4>
  }

  func.func @main() {
    %coeffs = arith.constant dense<[1, 2, 0, 0]> : tensor<4xi32>
    %poly = poly.from_tensor %coeffs : tensor<4xi32> -> !poly.poly<4>
    %result = func.call @poly_square(%poly) : (!poly.poly<4>) -> !poly.poly<4>
    return
  }
}
```

### Complete Lowering Commands

```powershell
# Step 1: Lower Poly → Standard
.\build\bin\tutorial-opt.exe examples\poly_complete.mlir `
  --convert-poly-to-standard `
  -o step1.mlir

# Step 2: Bufferization
.\build\bin\tutorial-opt.exe step1.mlir `
  --one-shot-bufferize="bufferize-function-boundaries=true" `
  -o step2.mlir

# Step 3: Lower to LLVM dialect
.\build\bin\tutorial-opt.exe step2.mlir `
  --convert-func-to-llvm `
  --convert-arith-to-llvm `
  --finalize-memref-to-llvm `
  --reconcile-unrealized-casts `
  -o step3.mlir

# Step 4: Translate to LLVM IR
.\build\bin\mlir-translate.exe step3.mlir `
  --mlir-to-llvmir `
  -o output.ll

# Step 5: Compile to executable
clang output.ll -o program.exe

# Step 6: Run!
.\program.exe
```

**Or use pipeline:**
```powershell
.\build\bin\tutorial-opt.exe examples\poly_complete.mlir `
  --pass-pipeline="lower-poly-to-llvm" `
  -o lowered.mlir
```

## Testing LLVM Lowering

### FileCheck Tests

**File: `tests/lower_to_llvm.mlir`**

```mlir
// RUN: tutorial-opt %s --lower-poly-to-llvm | FileCheck %s

module {
  // CHECK-LABEL: llvm.func @add
  // CHECK-SAME: (%[[ARG0:.*]]: i32, %[[ARG1:.*]]: i32)
  func.func @add(%arg0: i32, %arg1: i32) -> i32 {
    // CHECK: %[[RESULT:.*]] = llvm.add %[[ARG0]], %[[ARG1]] : i32
    %result = arith.addi %arg0, %arg1 : i32

    // CHECK: llvm.return %[[RESULT]] : i32
    return %result : i32
  }
}
```

### Integration Tests

**File: `tests/integration/run_poly.mlir`**

```mlir
// RUN: tutorial-opt %s --lower-poly-to-llvm | \
// RUN:   mlir-translate --mlir-to-llvmir | \
// RUN:   llc -filetype=obj -o %t.o && \
// RUN:   gcc %t.o -o %t.exe && \
// RUN:   %t.exe | FileCheck %s --check-prefix=OUTPUT

module {
  llvm.func @printf(!llvm.ptr<i8>, ...) -> i32

  func.func @main() -> i32 {
    %c42 = arith.constant 42 : i32

    // Print the result
    %fmt = llvm.mlir.constant("Result: %d\n\00") : !llvm.array<13 x i8>
    %fmt_ptr = llvm.mlir.addressof @fmt : !llvm.ptr<array<13 x i8>>
    %cast = llvm.getelementptr %fmt_ptr[0, 0]
      : (!llvm.ptr<array<13 x i8>>) -> !llvm.ptr<i8>
    %unused = llvm.call @printf(%cast, %c42)
      : (!llvm.ptr<i8>, i32) -> i32

    %c0 = arith.constant 0 : i32
    return %c0 : i32
  }

  llvm.mlir.global private constant @fmt("Result: %d\n\00")
}

// OUTPUT: Result: 42
```

## Performance Optimization

### LLVM Optimization Levels

```cpp
ExecutionEngineOptions options;

// No optimization
options.transformer = mlir::makeOptimizingTransformer(0, 0, nullptr);

// Standard optimization (-O2)
options.transformer = mlir::makeOptimizingTransformer(2, 0, nullptr);

// Aggressive optimization (-O3)
options.transformer = mlir::makeOptimizingTransformer(3, 0, nullptr);

// Size optimization (-Os)
options.transformer = mlir::makeOptimizingTransformer(2, 1, nullptr);
```

### Enabling LLVM Passes

```powershell
# Run LLVM optimization passes
opt -O3 output.ll -o optimized.ll

# View optimizations applied
opt -O3 -debug-pass=Structure output.ll
```

## CMake Integration

### Complete Conversion Library

**File: `lib/Conversion/PolyToLLVM/CMakeLists.txt`**

```cmake
add_mlir_library(MLIRPolyToLLVMConversion
  PolyToLLVM.cpp

  DEPENDS
  MLIRPolyOpsIncGen

  LINK_LIBS PUBLIC
  MLIRIR
  MLIRPass
  MLIRTransforms
  MLIRLLVMDialect
  MLIRFuncDialect
  MLIRArithDialect
  MLIRMemRefDialect
  MLIRSCFDialect

  # Conversion passes
  MLIRFuncToLLVM
  MLIRArithToLLVM
  MLIRMemRefToLLVM
  MLIRSCFToControlFlow
  MLIRControlFlowToLLVM

  # Bufferization
  MLIRBufferizationTransforms

  # Reconcile casts
  MLIRReconcileUnrealizedCasts

  # Our dialects
  MLIRPoly
  MLIRPolyToStandardConversion
)
```

### Build Everything

```powershell
cd D:\repos\mlir-tutorial\build
ninja tutorial-opt

# Test pipeline
.\bin\tutorial-opt.exe --help | Select-String "lower-poly-to-llvm"

# Run example
.\bin\tutorial-opt.exe ..\examples\poly_complete.mlir --lower-poly-to-llvm
```

## Key Takeaways

This tutorial explored complete lowering with honest assessment of the challenges:

✅ **Lowering is messy and non-linear** - Dependencies aren't obvious until you hit them

✅ **Pipeline construction is partially artisanal** - Trial and error characterizes real development

✅ **LLVM dialect is the exit point** - Architectural reuse of proven code generation infrastructure

✅ **Bufferization is a watershed** - From "what" computation to "where" data lives

✅ **Abstractions eliminate progressively** - Each step makes implicit assumptions explicit

✅ **Pass ordering matters critically** - Implicit input assumptions aren't always documented

✅ **Incremental approach works** - Start minimal, observe failures, add passes, repeat

✅ **Cleanup phases are essential** - Canonicalization and DCE dramatically simplify results

✅ **Tooling gaps exist** - No automated pass dependency analysis or conversion path construction

✅ **Testing reveals subtle bugs** - Verification across full stack catches errors optimization hides

## Next Steps

1. **[Tutorial 12: Dataflow Analysis](12-dataflow-analysis.md)** - Global optimization and analysis
2. **Implement complete lowering** for your dialect
3. **Study MLIR conversions** in `mlir/lib/Conversion/`
4. **Profile and optimize** generated LLVM IR
5. **Build integration tests** that compile and run programs

## Additional Resources

- **LLVM Dialect Doc:** [mlir.llvm.org/docs/Dialects/LLVM/](https://mlir.llvm.org/docs/Dialects/LLVM/)
- **Bufferization:** [mlir.llvm.org/docs/Bufferization/](https://mlir.llvm.org/docs/Bufferization/)
- **Translation:** [mlir.llvm.org/docs/TargetLLVMIR/](https://mlir.llvm.org/docs/TargetLLVMIR/)
- **ExecutionEngine:** Check `mlir/include/mlir/ExecutionEngine/`
- **LLVM Language Ref:** [llvm.org/docs/LangRef.html](https://llvm.org/docs/LangRef.html)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/11/01/mlir-lowering-through-llvm/)

---

**Previous:** [← Tutorial 10: Dialect Conversion](10-dialect-conversion.md)
**Next:** [Tutorial 12: Dataflow Analysis →](12-dataflow-analysis.md)
