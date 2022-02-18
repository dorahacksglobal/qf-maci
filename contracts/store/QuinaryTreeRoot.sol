// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { MerkleZeros } from "./zeros/MerkleQuinary0.sol";

library PoseidonT6 {
    function poseidon(uint256[5] memory input) public pure returns (uint256) {}
}

contract QuinaryTreeRoot is MerkleZeros {
    uint256 public constant DEGREE = 5;

    function rootOf(uint256 _depth, uint256[] memory _nodes) public view returns (uint256) {
        uint256 capacity = DEGREE ** _depth;
        uint256 length = _nodes.length;

        require(capacity >= length, "overflow");

        uint256 c = capacity / DEGREE;
        uint256 pl = (length - 1) / DEGREE + 1;
        for (uint256 i = 0; i < _depth; i++) {
            uint256 zero = getZero(i);
            // number of non-zero parent nodes
            for (uint256 j = 0; j < c; j ++) {
                if (j >= length) {
                    continue;
                }
                uint256 h = 0;
                if (j < pl) {
                    uint256[5] memory inputs;
                    uint256 s = 0;
                    for (uint256 k = 0; k < 5; k++) {
                        uint256 node = 0;
                        uint256 idx = j * 5 + k;
                        if (idx < length) {
                            node = _nodes[idx];
                        }
                        s += node;
                        if (node == 0) {
                            node = zero;
                        }
                        inputs[k] = node;
                    }
                    if (s > 0) {
                        h = PoseidonT6.poseidon(inputs);
                    }
                }
                _nodes[j] = h;
            }

            pl = (pl - 1) / DEGREE + 1;
            c = c / DEGREE;
        }

        uint256 result = _nodes[0];
        if (result == 0) {
            result = getZero(_depth);
        }
        return result;
    }

    function getZero(uint256 _height) internal view returns (uint256) {
        return zeros[_height];
    }
}
