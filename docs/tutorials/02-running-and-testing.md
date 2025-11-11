# Tutorial 02: Running and Testing a Lowering

**Original Article:** [MLIR — Running and Testing a Lowering](https://jeremykun.com/2023/08/10/mlir-running-and-testing-a-lowering/) by Jeremy Kun

**Windows Adaptation:** This tutorial focuses on lit/FileCheck testing with CMake instead of Bazel.

---

## What You'll Learn

- How MLIR **dialects** represent different abstraction levels
- How to **progressively lower** from high-level to low-level dialects
- Testing transformations with **lit** and **FileCheck**
- Running MLIR code with **mlir-cpu-runner**
- Setting up the testing infrastructure with **CMake**

## Understanding Dialects and Lowering: The Core of MLIR

If Tutorial 01 was about setup and philosophy, Tutorial 02 is where MLIR's design starts to **make sense**. You'll see why progressive lowering isn't just a nice idea—it's a practical necessity that makes sophisticated optimizations possible.

### The Problem: The Impedance Mismatch

Here's the fundamental problem every compiler faces: **source code and machine code live in different universes**.

Source code is about:
- High-level abstractions (objects, functions, patterns)
- Human intent ("find the first prime number greater than N")
- Flexibility ("I don't care how you do it, just get the answer")

Machine code is about:
- Registers and memory addresses
- Precise instruction sequences
- Hardware reality ("load this byte, shift these bits, jump to that address")

Traditional compilers try to bridge this gap in **one giant leap**. They parse source code, immediately lower to a single IR (like LLVM IR), optimize there, and emit assembly. But here's the problem: **by the time you reach the IR, you've lost information**.

### Why Information Loss Matters

Let me give you a concrete example. Consider this high-level loop:

```python
for i in range(1000):
    matrix[i][i] = 0  # Zero the diagonal
```

A traditional compiler immediately lowers this to something like:

```llvm
for (int i = 0; i < 1000; i++) {
    *(matrix + i * stride + i) = 0;
}
```

Now suppose you want to **vectorize** this loop—process multiple elements at once using SIMD instructions. Can you tell from the LLVM-style IR that this accesses a diagonal? That there's no aliasing? That iterations are independent?

Maybe. But you'd need to **reconstruct** that information through complex dataflow analysis. You'd need alias analysis to prove the iterations don't interfere. You'd need pattern matching to recognize the diagonal access pattern. It's a huge pain, and it's error-prone.

### MLIR's Solution: Keep the Structure

MLIR's philosophy: **don't throw away information until you need to**. Instead of lowering directly to LLVM IR, maintain intermediate dialects that preserve high-level structure:

```mlir
// High-level: affine dialect (preserves loop structure)
affine.for %i = 0 to 1000 {
  %val = arith.constant 0 : i32
  affine.store %val, %matrix[%i, %i] : memref<1000x1000xi32>
}
```

The `affine` dialect explicitly represents:
- Loop bounds as affine expressions
- Array accesses with multi-dimensional indices
- Independence between iterations (implicitly, through affine constraints)

Now vectorization is **trivial**—the structure is explicit. Polyhedral analysis works directly on the affine form. Only after optimization do you lower to simpler dialects.

This is MLIR's core insight: **preserve structure through multiple levels**, discarding it only when you lower to the next level. Each level enables optimizations that would be impossible at lower levels.

### The Problem: Many Abstraction Levels

A compiler needs to bridge the gap from high-level source code to machine instructions. MLIR solves this with **dialects**—small, focused intermediate representations at different abstraction levels.

But here's the key: **dialects coexist**. You don't replace all high-level operations at once. Instead, you incrementally lower parts of your program, keeping high-level structure where it helps and lowering to low-level forms where it doesn't.

**Example: Computing ctlz (count leading zeros)**

```mlir
// High-level: math dialect
%result = math.ctlz %input : i32

// Mid-level: arith + scf dialects
%c31 = arith.constant 31 : i32
%c1 = arith.constant 1 : i32
%c0 = arith.constant 0 : i32
%count = scf.while (%arg0 = %c31) : (i32) -> i32 {
  %bit = arith.shli %c1, %arg0 : i32
  %test = arith.andi %input, %bit : i32
  %is_zero = arith.cmpi eq, %test, %c0 : i32
  scf.condition(%is_zero) %arg0 : i32
} do {
^bb0(%arg0: i32):
  %next = arith.subi %arg0, %c1 : i32
  scf.yield %next : i32
}
%result = arith.subi %c31, %count : i32

// Low-level: LLVM dialect
%result = llvm.ctlz %input : i32
```

### Progressive Lowering Pattern: Why Small Steps Matter

Instead of one giant transformation, MLIR uses **incremental lowering**:

```
math dialect → arith + scf → LLVM dialect → Machine Code
  (high)         (mid)          (low)
```

Each arrow is a **pass** that converts operations from one dialect to another. But why break this into multiple steps? Why not go directly from `math` to `llvm`?

#### The Composition Benefit

Small lowering steps **compose**. Consider these three compilers:

**Compiler A**: Needs `math` → `llvm`
**Compiler B**: Needs `tensor` → `linalg` → `llvm`
**Compiler C**: Needs `quantum` → `math` → `llvm`

If every compiler implements "X to LLVM" directly, we have:
- Compiler A: Writes `math` → `llvm`
- Compiler B: Writes `tensor` → `linalg`, `linalg` → `llvm`
- Compiler C: Writes `quantum` → `math`, `math` → `llvm`

Notice the duplication: both A and C implement `math` → `llvm`. With **small steps**, we write:
- `math` → `arith + scf` (once, reused by A and C)
- `arith + scf` → `llvm` (once, reused by everyone)
- `tensor` → `linalg` (once, for B)
- `linalg` → `llvm` (once, for B)
- `quantum` → `math` (once, for C)

Now each transformation is **written once and reused**. This is MLIR's compositional win.

#### The Debugging Benefit

When a lowering fails, small steps make debugging **tractable**.

**Giant transformation:**
```
Input: 500 lines of math dialect
Output: 5000 lines of LLVM dialect
Problem: Output is wrong somewhere
Question: Where did it break?
Answer: Could be anywhere in 5000 lines
```

**Incremental transformation:**
```
Step 1: math → arith + scf (500 → 800 lines)
        FileCheck: Verify structure
Step 2: arith + scf → llvm (800 → 5000 lines)
        FileCheck: Verify structure
Problem: Test fails at Step 1
Answer: The bug is in math lowering, not arith lowering
```

Incremental steps **narrow the search space**. You know which pass broke, which transformation failed, and can inspect the intermediate IR.

#### The Optimization Benefit

Here's the subtle one: **intermediate dialects enable optimizations that wouldn't work elsewhere**.

Example: Suppose you lower `math.ctlz` to a loop:

```mlir
// After math → arith + scf
%count = scf.while (%bit = %c31) : (i32) -> i32 {
  %mask = arith.shli %c1, %bit : i32
  %test = arith.andi %input, %mask : i32
  %is_zero = arith.cmpi eq, %test, %c0 : i32
  scf.condition(%is_zero) %bit : i32
} do {
^bb0(%bit: i32):
  %next = arith.subi %bit, %c1 : i32
  scf.yield %next : i32
}
```

Before lowering to LLVM, you might run:
- **Loop unrolling** (works on `scf.while`)
- **Constant folding** (works on `arith` ops)
- **Dead code elimination** (works on SSA form)

These passes **can't see through LLVM dialect** because LLVM dialect is too low-level. But they work perfectly on the intermediate form.

Then you lower to LLVM and run **LLVM's own optimizations** (instruction selection, register allocation, etc.).

By staging lowering, you get **best of both worlds**: high-level optimizations before lowering, low-level optimizations after.

#### The Mental Model

Think of progressive lowering like **refining a sculpture**:

1. Start with a rough block (high-level dialect)
2. Carve major features (lower to mid-level dialects)
3. Smooth surfaces (optimize at mid-level)
4. Add fine details (lower to low-level dialect)
5. Polish (optimize at low-level)

You can't polish before carving—you need the right level of abstraction for each operation. MLIR's progressive lowering matches this natural workflow.

## Example: Count Leading Zeros (ctlz)

Let's look at the ctlz example in `tests/ctlz.mlir`:

```mlir
// tests/ctlz.mlir
func.func @main() -> i32 {
  %input = arith.constant 8 : i32
  %result = math.ctlz %input : i32
  return %result : i32
}
```

**What this does:**
- Creates constant `8` (binary: `0000...01000`)
- Counts leading zeros (28 in this case)
- Returns the count

### Running the Example

```powershell
# Show the original MLIR
.\build\bin\tutorial-opt.exe .\tests\ctlz.mlir

# Convert math.ctlz to a function call
mlir-opt .\tests\ctlz.mlir --convert-math-to-funcs=convert-ctlz

# Lower to LLVM dialect
mlir-opt .\tests\ctlz.mlir `
  --convert-math-to-llvm `
  --convert-arith-to-llvm `
  --convert-func-to-llvm

# Execute it!
mlir-cpu-runner .\tests\ctlz_runner.mlir `
  --entry-point-result=i32 `
  -e main `
  --shared-libs=C:\msys64\mingw64\bin\mlir_runner_utils.dll
```

## Testing with lit and FileCheck: The Philosophy of Compiler Testing

Now we get to one of MLIR's most distinctive features: **embedded testing**. When I first saw lit/FileCheck, I thought: "Why are tests embedded in source files? This violates separation of concerns!"

But after writing a few dozen MLIR passes, I understood: **for compiler transformations, embedding tests in source files is brilliant**.

### The Problem with Traditional Testing

Traditional unit testing works well for functions with small inputs and outputs:

```cpp
assert(add(2, 3) == 5);  // Input: 2, 3. Output: 5. Easy.
```

But compiler passes have **massive inputs and outputs**:

**Input:** An entire MLIR module (could be hundreds of lines)

**Output:** A transformed MLIR module (also hundreds of lines)

Traditional testing would look like:
```cpp
std::string input = "module { func.func @test() { ... 100 lines ... } }";
std::string expected = "module { func.func @test() { ... 100 transformed lines ... } }";
assert(transform(input) == expected);
```

This is **unmaintainable**. When your transformation changes, you update 100-line strings in C++ test files? No thanks.

### MLIR's Solution: Literate Testing

Instead, embed the test in the MLIR file itself:

```mlir
// RUN: tutorial-opt %s --my-pass | FileCheck %s

func.func @test() {
  // ... input code ...
}

// CHECK-LABEL: func.func @test
// CHECK: expected transformation
```

Now the **input** is the file itself, and the **expected output** is right there in comments. When the transformation changes, you see input and output together—making updates natural.

This is called "literate testing" because tests **document** what the code should do, right where you can see it.

### What are lit and FileCheck?

**lit (LLVM Integrated Tester):**

`lit` is LLVM's test runner. It:
- Recursively finds test files (`.mlir`, `.ll`, `.c`, etc.)
- Extracts `RUN:` commands from comments
- Executes commands in a controlled environment
- Reports pass/fail with detailed output

Think of `lit` as a specialized test runner that understands compiler testing patterns. It's like `pytest` but designed for compiler infrastructure.

**FileCheck:**

`FileCheck` is a pattern matcher for text output. It:
- Reads expected patterns from `CHECK:` comments
- Matches them against actual command output
- Supports regex, variable capture, and complex patterns
- Reports exactly where matching failed

The genius of FileCheck is that it's **flexible enough** to handle minor formatting changes but **strict enough** to catch real errors. It's not a simple string comparison—it's a domain-specific matcher for compiler output.

### Why This Combination Works

The `lit` + `FileCheck` combination solves several problems:

1. **Co-location**: Tests live near code they test (not in separate directories)
2. **Documentation**: Tests show **how** transformations work
3. **Flexibility**: FileCheck handles formatting variations
4. **Precision**: You test specific transformations, not entire outputs
5. **Scalability**: Adding tests doesn't require framework changes

LLVM has **tens of thousands** of tests using this pattern. It scales from small examples to million-line codebases. That's proven design.

### Anatomy of a Test File

Let's look at `tests/ctlz_simple.mlir`:

```mlir
// RUN: mlir-opt %s --convert-math-to-funcs=convert-ctlz | FileCheck %s

func.func @main() -> i32 {
  %input = arith.constant 8 : i32
  %result = math.ctlz %input : i32
  return %result : i32
}

// CHECK-LABEL: func.func @main
// CHECK-NOT: math.ctlz
// CHECK: call @__mlir_math_ctlz_i32
```

**Breaking it down:**

**`RUN:` directive** (line 1):
```
mlir-opt %s --convert-math-to-funcs=convert-ctlz | FileCheck %s
```
- `%s` = current file (`ctlz_simple.mlir`)
- Run `mlir-opt` with the pass
- Pipe output to `FileCheck`
- `FileCheck` reads same file for `CHECK:` patterns

**`CHECK:` directives:**
- `CHECK-LABEL: func.func @main` - Find this function
- `CHECK-NOT: math.ctlz` - Ensure `math.ctlz` is gone
- `CHECK: call @__mlir_math_ctlz_i32` - Verify it was converted to a call

### Running Tests Manually

```powershell
# Run the transformation
mlir-opt .\tests\ctlz_simple.mlir --convert-math-to-funcs=convert-ctlz

# Expected output should include:
# func.call @__mlir_math_ctlz_i32(%input) : (i32) -> i32

# Run with FileCheck
mlir-opt .\tests\ctlz_simple.mlir --convert-math-to-funcs=convert-ctlz | `
  FileCheck .\tests\ctlz_simple.mlir
```

If the transformation worked, FileCheck prints nothing (success). If it fails, you'll see:
```
error: CHECK: expected string not found in input
```

## Advanced FileCheck Patterns: The Art of Flexible Matching

When I started using FileCheck, I wrote tests that were **too specific**. They'd break when MLIR changed trivial details like SSA value numbering. After rewriting tests dozens of times, I learned: **FileCheck patterns should be as loose as necessary and as tight as needed**.

### Variable Capture and Reuse: Testing Dataflow

The most powerful FileCheck feature is **variable capture**—capturing part of the output and referencing it later.

```mlir
// CHECK: %[[VAR:.*]] = arith.constant 8
// CHECK: %[[RESULT:.*]] = math.ctlz %[[VAR]]
// CHECK: return %[[RESULT]]
```

**What's happening:**

1. **`%[[VAR:.*]]`** - Captures the SSA value name (e.g., `%0`, `%c8`, `%input`) into variable `VAR`
2. **`%[[VAR]]`** - References that captured value later

**Why this matters:**

SSA value names are **implementation details**. MLIR might name a value `%0` or `%input` or `%c8_i32` depending on optimizations, printing options, or phase of the moon. If you write:

```mlir
// CHECK: %0 = arith.constant 8
// CHECK: %1 = math.ctlz %0
```

This test **breaks** if MLIR names the values differently. But with capture:

```mlir
// CHECK: %[[C:.*]] = arith.constant 8
// CHECK: %{{.*}} = math.ctlz %[[C]]
```

The test **survives** naming changes because you're testing **relationships** (ctlz uses the constant), not specific names.

### Regular Expressions: When You Don't Care About Details

FileCheck supports POSIX extended regexes inside `{{...}}`:

```mlir
// CHECK: %{{.*}} = arith.constant {{[0-9]+}} : i32
```

**`{{.*}}`** matches any SSA value name

**`{{[0-9]+}}`** matches one or more digits (any constant value)

**When to use regex:**

- You're testing that *some* constant exists, but the value doesn't matter
- You're matching patterns in names: `{{func_[0-9]+}}`
- You're testing presence, not specifics

**When NOT to use regex:**

- You know the exact value and it matters: just write `8`, not `{{[0-9]+}}`
- You need to reference the value later (use capture instead)

### CHECK Variants: Controlling Match Order

FileCheck has several CHECK variants that control **where and when** matches occur:

#### `CHECK:` - Sequential Matching

```mlir
// CHECK: first thing
// CHECK: second thing
// CHECK: third thing
```

Matches must appear **in order**, but there can be anything between them. This is your default.

#### `CHECK-NEXT:` - Immediate Adjacency

```mlir
// CHECK: %0 = arith.constant 1
// CHECK-NEXT: %1 = arith.constant 2
```

The second line must **immediately follow** the first (no blank lines, comments, or other operations). Use sparingly—it makes tests brittle.

**When to use:** Verifying specific instruction sequence (e.g., "constant must be immediately before use for some optimization").

#### `CHECK-NOT:` - Absence Testing

```mlir
// CHECK-NOT: math.ctlz
```

This line must **NOT appear** between the previous CHECK and the next CHECK. Critical for verifying transformations:

```mlir
// CHECK-LABEL: func.func @test
// CHECK-NOT: math.ctlz
// CHECK: llvm.ctlz
```

This says: "In function `@test`, there should be NO `math.ctlz` before we see `llvm.ctlz`." It verifies the lowering succeeded.

#### `CHECK-LABEL:` - Defining Boundaries

```mlir
// CHECK-LABEL: func.func @function1
// CHECK: something in function1
// CHECK-LABEL: func.func @function2
// CHECK: something in function2
```

`CHECK-LABEL` creates a **scope boundary**. Matches between the first label and second label **can't cross** the second label. This prevents false matches.

**Without CHECK-LABEL:**
```mlir
// CHECK: operation1
// ... matches operation1 anywhere in file ...
// CHECK: operation2
// ... matches operation2 anywhere after operation1 ...
```

**With CHECK-LABEL:**
```mlir
// CHECK-LABEL: @function1
// CHECK: operation1
// ... matches operation1 only in function1 ...
// CHECK-LABEL: @function2
// CHECK: operation2
// ... matches operation2 only in function2 ...
```

Always use `CHECK-LABEL` when testing multiple functions or modules.

#### `CHECK-DAG:` - Unordered Matching

```mlir
// CHECK-DAG: first thing (might appear second)
// CHECK-DAG: second thing (might appear first)
// CHECK: third thing (must come after both DAGs)
```

`CHECK-DAG` directives match **in any order** within their group. Use when order doesn't matter:

```mlir
// Constants can be emitted in any order
// CHECK-DAG: %[[C1:.*]] = arith.constant 1
// CHECK-DAG: %[[C2:.*]] = arith.constant 2
// CHECK-DAG: %[[C3:.*]] = arith.constant 3
// But the addition must use them
// CHECK: arith.addi %[[C1]], %[[C2]]
```

### Practical Patterns I Use Constantly

**Pattern 1: "I don't care about SSA names"**
```mlir
// CHECK: %{{.*}} = some.operation
```

**Pattern 2: "Capture this value, check it's used later"**
```mlir
// CHECK: %[[V:.*]] = produce.value
// CHECK: consume.value %[[V]]
```

**Pattern 3: "This operation should be gone"**
```mlir
// CHECK-LABEL: @function
// CHECK-NOT: expensive.operation
```

**Pattern 4: "These constants exist, order doesn't matter"**
```mlir
// CHECK-DAG: arith.constant 0
// CHECK-DAG: arith.constant 1
// CHECK-DAG: arith.constant 2
```

**Pattern 5: "Test multiple functions independently"**
```mlir
// CHECK-LABEL: @function1
// CHECK: ...function1 stuff...
// CHECK-LABEL: @function2
// CHECK: ...function2 stuff...
```

### The Debugging Flow

When a FileCheck test fails:

1. **Read the error message** - It shows what FileCheck expected vs what it got
2. **Run manually** - `tutorial-opt input.mlir --pass > output.mlir`
3. **Inspect output.mlir** - See what actually happened
4. **Compare** - Is the output wrong, or is the CHECK pattern wrong?
5. **Fix whichever is wrong**

Most CHECK failures aren't bugs—they're patterns that were too strict. Learning to write resilient patterns is an art.

### Example: Testing Loop Unrolling

```mlir
// RUN: tutorial-opt %s --affine-full-unroll | FileCheck %s

func.func @simple_loop() {
  affine.for %i = 0 to 4 {
    // Loop body
  }
  return
}

// CHECK-LABEL: func.func @simple_loop
// CHECK-NOT: affine.for
// CHECK: // Iteration 0
// CHECK: // Iteration 1
// CHECK: // Iteration 2
// CHECK: // Iteration 3
```

## Running the Test Suite

### Using CMake/Ninja

```powershell
# Build and run all tests
cd build
ninja check-mlir-tutorial
```

**Output:**
```
Testing Time: 2.34s
  Passed: 15
  Failed: 0
```

### Running Individual Tests

```powershell
# Run specific test
lit -v .\tests\ctlz_simple.mlir

# Run tests matching pattern
lit .\tests\poly*.mlir

# Show detailed output
lit -v -a .\tests\
```

### Understanding lit Configuration

The test infrastructure is set up in `tests/CMakeLists.txt`:

```cmake
configure_lit_site_cfg(
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.cmake.site.cfg.py.in
  ${CMAKE_CURRENT_BINARY_DIR}/lit.cmake.site.cfg.py
  MAIN_CONFIG
  ${CMAKE_CURRENT_SOURCE_DIR}/lit.cmake.cfg.py
)

add_lit_testsuite(check-mlir-tutorial "Running the MLIR tutorial tests"
  ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS tutorial-opt
)
```

**What this does:**
1. **Configures lit** - Substitutes CMake variables into `lit.cmake.site.cfg.py`
2. **Finds tools** - Locates `tutorial-opt`, `mlir-opt`, etc.
3. **Sets up PATH** - Adds tool directories to environment
4. **Creates target** - `check-mlir-tutorial` runs all tests

### lit Configuration Files

**`tests/lit.cmake.cfg.py`** - Main configuration:
```python
config.name = "MLIR_TUTORIAL"
config.test_format = lit.formats.ShTest(not llvm_config.use_lit_shell)
config.suffixes = [".mlir"]

tools = [
    "mlir-opt",
    "tutorial-opt"
]
llvm_config.add_tool_substitutions(tools, tool_dirs)
```

**Key settings:**
- **Test format:** `ShTest` - Shell script style tests
- **Suffixes:** `.mlir` - Only test these files
- **Tools:** Defines `%tutorial-opt` substitution

## Comparing to Bazel Testing: Lessons in Pragmatism

This is a good moment to reflect on **why build systems matter** and **when to optimize for what**.

### Original Tutorial (Bazel)

```python
# BUILD file
py_test(
    name = "ctlz_simple",
    srcs = ["@llvm-project//mlir:run_lit.py"],
    data = ["ctlz_simple.mlir", "//tools:tutorial-opt"],
    env = {
        "RUNFILES_DIR": "$(BINDIR)",
    },
)
```

**What's happening here:**

Bazel treats tests as **first-class build targets**. Each test is a `py_test` rule that:
- Depends on source files (`data` attribute)
- Runs a Python script (`srcs`)
- Sets up environment variables (`env`)
- Integrates with Bazel's caching and sandboxing

**The Problems:**

1. **Boilerplate**: Every test file needs a `py_test` rule
2. **Ceremony**: You declare dependencies explicitly: "this test depends on tutorial-opt"
3. **Non-obviousness**: The relationship between `.mlir` files and `py_test` rules is implicit

For a tutorial with 10-20 test files, this means **10-20 BUILD rule declarations**. It's maintainable, but it's work.

**Why Bazel Does This:**

Bazel's hermetic builds require explicit dependency graphs. If you don't declare that `ctlz_simple` depends on `tutorial-opt`, Bazel can't guarantee build order. The verbosity enables:
- Precise incremental rebuilds (only re-run tests whose deps changed)
- Distributed test execution (run tests on different machines)
- Caching across machines (your teammate's test results can skip your runs)

For **Google-scale infrastructure**, these benefits outweigh verbosity.

### This Tutorial (CMake + lit)

```cmake
# CMakeLists.txt
add_lit_testsuite(check-mlir-tutorial "Running tests"
  ${CMAKE_CURRENT_BINARY_DIR}
  DEPENDS tutorial-opt
)
```

**What's happening here:**

CMake uses **convention over configuration**. The `add_lit_testsuite` call:
- Finds all `.mlir` files in the directory automatically
- Configures lit to know where `tutorial-opt` is
- Creates a `check-mlir-tutorial` target that runs all tests

**One line replaces 20 Bazel rules.**

**The Benefits:**

1. **Convention**: Just put `.mlir` files in `tests/`, they're automatically discovered
2. **Simplicity**: One declaration for the entire test suite
3. **Obviousness**: The CMake structure mirrors LLVM upstream

**The Tradeoff:**

You lose Bazel's granular caching and distribution. CMake's incremental test runs are coarser—if any test changes, you might re-run more tests than necessary.

For **learning MLIR**, where you have dozens (not thousands) of tests, this tradeoff is acceptable.

### The Design Philosophy Lesson

The Bazel vs CMake choice illustrates a broader principle: **optimize for your constraints**.

**Bazel optimizes for:**
- Large codebases (millions of lines)
- Distributed teams (thousands of developers)
- Expensive builds (hours to compile)
- Hermetic environments (same build everywhere)

**CMake optimizes for:**
- Medium codebases (tens of thousands of lines)
- Smaller teams (dozens of developers)
- Faster builds (minutes to compile with packages)
- Local development (get started quickly)

Neither is "better"—they solve different problems. This tutorial chooses CMake because **your constraint is learning time**, not build infrastructure at scale.

When you build a production MLIR compiler, re-evaluate. If you're at Google, use Bazel. If you're at a startup, maybe CMake. If you're building open-source tools, consider both. The concepts transfer; the build system is just scaffolding.

## Writing Your Own Tests

### Step 1: Create Test File

Create `tests/my_test.mlir`:

```mlir
// RUN: tutorial-opt %s --canonicalize | FileCheck %s

func.func @my_function(%arg0: i32) -> i32 {
  %c1 = arith.constant 1 : i32
  %sum = arith.addi %arg0, %c1 : i32
  %redundant = arith.addi %sum, %c1 : i32  // This will be folded
  %final = arith.subi %redundant, %c1 : i32
  return %final : i32
}

// CHECK-LABEL: func.func @my_function
// CHECK: %[[C1:.*]] = arith.constant 1
// CHECK: %[[SUM:.*]] = arith.addi %arg0, %[[C1]]
// CHECK: return %[[SUM]]
```

### Step 2: Run the Test

```powershell
# Test manually
tutorial-opt .\tests\my_test.mlir --canonicalize | FileCheck .\tests\my_test.mlir

# Or with lit
cd build
lit ..\tests\my_test.mlir
```

### Step 3: Test Automatically

No changes needed! CMake automatically discovers `*.mlir` files in `tests/`.

```powershell
ninja check-mlir-tutorial
```

## Debugging Test Failures

### Common Issues

**Test fails with "expected string not found":**

```powershell
# See what mlir-opt actually produces
mlir-opt .\tests\my_test.mlir --canonicalize

# Compare with CHECK patterns
# Adjust patterns to match actual output
```

**Tool not found:**

```powershell
# Check lit can find tools
lit --show-suites

# Verify PATH
$env:PATH -split ';' | Select-String mlir
```

**Wrong output format:**

```mlir
// Use -v for verbose lit output
lit -v .\tests\my_test.mlir

// Check IR printing options
mlir-opt --help | Select-String print
```

## Running Code with mlir-cpu-runner

For tests that need to execute (not just transform), use `mlir-cpu-runner`:

```mlir
// RUN: mlir-cpu-runner %s \
// RUN:   --entry-point-result=i32 \
// RUN:   -e main \
// RUN:   --shared-libs=%mlir_runner_utils \
// RUN:   | FileCheck %s

func.func @main() -> i32 {
  %result = arith.constant 42 : i32
  return %result : i32
}

// CHECK: 42
```

**Windows-specific:**

```powershell
mlir-cpu-runner .\tests\example.mlir `
  --entry-point-result=i32 `
  -e main `
  --shared-libs=C:\msys64\mingw64\bin\mlir_runner_utils.dll
```

## Best Practices

### 1. Test One Thing at a Time

```mlir
// Good: Tests specific transformation
// RUN: mlir-opt %s --cse | FileCheck %s

// Bad: Tests too many things
// RUN: mlir-opt %s --canonicalize --cse --inline | FileCheck %s
```

### 2. Use CHECK-LABEL for Context

```mlir
// CHECK-LABEL: func.func @test1
// CHECK: operation1
// CHECK-LABEL: func.func @test2
// CHECK: operation2
```

This prevents operations from `test1` matching against `test2`.

### 3. Capture SSA Names

```mlir
// Good: Flexible to SSA renaming
// CHECK: %[[VAR:.*]] = arith.constant
// CHECK: arith.addi %[[VAR]], %[[VAR]]

// Bad: Brittle
// CHECK: %0 = arith.constant
// CHECK: arith.addi %0, %0
```

### 4. Test Negative Cases

```mlir
// Ensure transformation didn't happen when it shouldn't
// CHECK-NOT: math.ctlz
```

## Design Tradeoffs: Syntactic vs Semantic Lowering

Before we wrap up, let's address an important limitation that Jeremy Kun highlighted in his original article.

### MLIR Lowering is Primarily Syntactic

When you run a lowering pass like `--convert-math-to-llvm`, MLIR is performing **syntactic transformation**. It's replacing operations that look like this:

```mlir
%result = math.ctlz %input : i32
```

with operations that look like this:

```mlir
%result = llvm.ctlz %input : i32
```

But here's the key insight: **MLIR doesn't verify functional correctness**. The transformation could be:

```mlir
%wrong = llvm.ctpop %input : i32  // Count population, not leading zeros!
```

And MLIR would happily accept it, because **types match**. MLIR's verifier checks:
- Operand types match operation requirements
- SSA dominance is correct
- Control flow is well-formed

But it doesn't check "does this actually compute leading zeros?"

### Why This Matters

This limitation means:
- **FileCheck tests** verify structure, not semantics
- **mlir-cpu-runner tests** verify execution, confirming correctness
- You need **both kinds of tests** for confidence

The Bazel vs CMake tradeoff makes sense in this light. MLIR's testing philosophy already layers structural tests (FileCheck) with semantic tests (execution). Each layer has a purpose.

### The Design Philosophy

MLIR's approach reflects a deeper principle: **separate concerns**.

- **The IR framework** (MLIR itself) ensures structural correctness
- **The dialect implementations** ensure semantic correctness
- **The tests** verify both

By keeping these separate, MLIR stays flexible. You can define dialects with arbitrary semantics, and MLIR doesn't need to understand quantum mechanics or tensor algebra or FHE to verify your IR. It just checks structure.

This is both **powerful** (you can define any semantics) and **risky** (you can define wrong semantics). The testing infrastructure exists to catch the risks.

## Key Takeaways: What You've Really Learned

Beyond the mechanics of writing tests, here's what you should internalize:

### 1. Progressive Lowering Enables Better Optimizations

Traditional compilers lose high-level structure early. MLIR preserves it through multiple abstraction levels. This isn't academic—it's the difference between "can't vectorize this loop" and "automatic vectorization."

When you build compilers, think: **what structure do my optimizations need?** Design dialects that preserve that structure.

### 2. Dialects Coexist During Lowering

You don't lower "all at once." A single function might have:
- `tensor` operations for high-level arrays
- `affine` loops for structured iteration
- `arith` for scalar math
- `llvm` for low-level memory operations

This coexistence is intentional. Lower each operation **when you're ready**, not before.

### 3. Testing is About Trust, Not Proof

MLIR's testing can't prove your transformation is correct. But it can:
- Document intended behavior (FileCheck)
- Catch regressions (when changes break tests)
- Verify execution (mlir-cpu-runner)

This combination builds **confidence**, which is what you need for production compilers.

### 4. Build Systems Are About Tradeoffs

Bazel and CMake make different tradeoffs. Understanding **why** helps you choose appropriately:
- Learning? Use CMake (low friction)
- Production at scale? Consider Bazel (better caching)
- Open source? Support both (wider adoption)

The concepts are the same; the infrastructure differs.

### 5. Literate Testing Scales

Embedding tests in source files seems weird at first. But LLVM's 20+ years of experience proves it works. When tests document code, both improve together.

### 6. Structural vs Semantic Testing

MLIR tests structure; you test semantics. This separation of concerns is intentional. Design your testing strategy accordingly:
- Quick feedback: FileCheck (milliseconds)
- Correctness proof: Execution tests (seconds)
- Both are necessary

### 7. The Learning Curve is Worth It

Testing infrastructure feels like overhead when you're learning. But once you internalize the patterns:
- Adding tests becomes automatic
- Debugging is faster (tests pinpoint issues)
- Refactoring is safer (tests catch breakage)

The investment pays off exponentially as your compiler grows.

## Next Steps

Now that you understand testing:

1. **[Tutorial 03: Writing Your First Pass](03-writing-first-pass.md)** - Create custom transformations
2. **Explore existing tests** - Look at `tests/*.mlir` for more examples
3. **Add your own tests** - Practice with FileCheck patterns

## Additional Resources

- **FileCheck Documentation:** [llvm.org/docs/CommandGuide/FileCheck.html](https://llvm.org/docs/CommandGuide/FileCheck.html)
- **lit Documentation:** [llvm.org/docs/CommandGuide/lit.html](https://llvm.org/docs/CommandGuide/lit.html)
- **MLIR Testing Guide:** [mlir.llvm.org/getting_started/TestingGuide/](https://mlir.llvm.org/getting_started/TestingGuide/)
- **Original Article:** [jeremykun.com](https://jeremykun.com/2023/08/10/mlir-running-and-testing-a-lowering/)

---

**Previous:** [← Tutorial 01: Getting Started](01-getting-started.md)
**Next:** [Tutorial 03: Writing Your First Pass →](03-writing-first-pass.md)
