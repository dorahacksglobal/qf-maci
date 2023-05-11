pragma circom 2.0.0;

include "../addNewKey.circom";

// state_tree_depth

component main {
  public [
    inputHash
  ]
} = AddNewKey(2);
