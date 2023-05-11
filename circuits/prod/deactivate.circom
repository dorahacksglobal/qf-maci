pragma circom 2.0.0;

include "../processDeactivate.circom";

// state_tree_depth,
// batch_size

component main {
  public [
    inputHash
  ]
} = ProcessDeactivateMessages(2, 5);
