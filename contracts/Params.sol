// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

contract Params {
    // This structs help to reduce the number of parameters to the constructor
    // and avoid a stack overflow error during compilation
    struct MaciInfo {
        uint8 stateTreeDepth;
        uint8 intStateTreeDepth;
        uint8 messageBatchSize;
        uint8 voteOptionTreeDepth;
    }
}
