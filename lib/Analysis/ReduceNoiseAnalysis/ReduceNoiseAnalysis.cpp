#include "lib/Analysis/ReduceNoiseAnalysis/ReduceNoiseAnalysis.h"

#include "lib/Dialect/Noisy/NoisyOps.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/Support/Debug.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/TypeSwitch.h"

namespace mlir {
namespace tutorial {

#define DEBUG_TYPE "ReduceNoiseAnalysis"

// Simple greedy algorithm to replace or-tools ILP solver
// This implementation teaches the same MLIR dataflow analysis concepts
// without requiring external dependencies

ReduceNoiseAnalysis::ReduceNoiseAnalysis(Operation *op) {
  // Track noise levels at each SSA value
  llvm::DenseMap<Value, int> noiseMap;

  // Forward pass: compute noise at each operation
  op->walk([&](Operation *operation) {
    // Only process noisy arithmetic operations
    if (!isa<noisy::AddOp, noisy::SubOp, noisy::MulOp>(operation)) {
      return;
    }

    // Calculate input noise from operands
    int inputNoise = 0;
    for (Value operand : operation->getOperands()) {
      // Initial values (block arguments and encode ops) start with INITIAL_NOISE
      if (isa<BlockArgument>(operand) ||
          isa<noisy::EncodeOp>(operand.getDefiningOp())) {
        inputNoise = std::max(inputNoise, INITIAL_NOISE);
      } else {
        inputNoise = std::max(inputNoise, noiseMap.lookup(operand));
      }
    }

    // Compute output noise based on operation type
    int outputNoise = inputNoise;

    llvm::TypeSwitch<Operation *>(operation)
        .Case<noisy::MulOp>([&](auto mulOp) {
          // For multiplication: noise is sum of input noises
          int lhsNoise = 0;
          int rhsNoise = 0;

          Value lhs = mulOp.getLhs();
          Value rhs = mulOp.getRhs();

          if (isa<BlockArgument>(lhs) || isa<noisy::EncodeOp>(lhs.getDefiningOp())) {
            lhsNoise = INITIAL_NOISE;
          } else {
            lhsNoise = noiseMap.lookup(lhs);
          }

          if (isa<BlockArgument>(rhs) || isa<noisy::EncodeOp>(rhs.getDefiningOp())) {
            rhsNoise = INITIAL_NOISE;
          } else {
            rhsNoise = noiseMap.lookup(rhs);
          }

          outputNoise = lhsNoise + rhsNoise;
        })
        .Case<noisy::AddOp, noisy::SubOp>([&](auto addOrSub) {
          // For addition/subtraction: noise is max of inputs + 1
          int lhsNoise = 0;
          int rhsNoise = 0;

          Value lhs = addOrSub.getLhs();
          Value rhs = addOrSub.getRhs();

          if (isa<BlockArgument>(lhs) || isa<noisy::EncodeOp>(lhs.getDefiningOp())) {
            lhsNoise = INITIAL_NOISE;
          } else {
            lhsNoise = noiseMap.lookup(lhs);
          }

          if (isa<BlockArgument>(rhs) || isa<noisy::EncodeOp>(rhs.getDefiningOp())) {
            rhsNoise = INITIAL_NOISE;
          } else {
            rhsNoise = noiseMap.lookup(rhs);
          }

          outputNoise = std::max(lhsNoise, rhsNoise) + 1;
        });

    // Greedy decision: insert reduce_noise if threshold exceeded
    if (outputNoise > MAX_NOISE) {
      solution[operation] = true;
      outputNoise = INITIAL_NOISE;  // Reset noise after reduction
      LLVM_DEBUG(llvm::dbgs() << "Inserting reduce_noise after "
                              << operation->getName() << " at "
                              << operation->getLoc() << "\n");
    } else {
      solution[operation] = false;
    }

    // Propagate noise to result values
    for (Value result : operation->getResults()) {
      noiseMap[result] = outputNoise;
    }
  });

  LLVM_DEBUG(llvm::dbgs() << "ReduceNoiseAnalysis completed (greedy algorithm)\n");
}

} // namespace tutorial
} // namespace mlir
