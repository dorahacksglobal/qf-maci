// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { MerkleZeros } from "./zeros/MerkleQuinary0.sol";

library PoseidonT6 {
    function poseidon(uint256[5] memory input) public pure returns (uint256) {}
}

abstract contract SimpleQuinaryTree {
    uint256 public constant DEGREE = 5;
    uint256 public DEPTH;
    uint256 public MAX_LEAVES_COUNT;

    address public MACI;

    uint256 public leavesCount;
    uint256 private _leafIdx0;

    /*
     *  length: (5 ** (depth + 1) - 1) / 4
     *
     *  hashes(leaves) at depth D: nodes[n]
     *  n => [ (5**D-1)/4 , (5**(D+1)-1)/4 )
     */
    mapping (uint256 => uint256) public nodes;

    constructor(uint256 _depth) {
        require(_depth <= 12, "no special reason, just limit it");

        DEPTH = _depth;
        MAX_LEAVES_COUNT = 5 ** _depth;
        _leafIdx0 = (MAX_LEAVES_COUNT - 1) / 4;
    }

    modifier onlyMACI() {
        require(msg.sender == MACI);
        _;
    }

    function init() public {
        require(MACI == address(0));
        MACI = msg.sender;

        // initialize root
        nodes[0] = getZero(DEPTH);
    }

    /*
     * Returns the zero leaf at a specified level.
     * This is a virtual function as the hash function which the overriding
     * contract uses will be either hashLeftRight or hash5, which will produce
     * different zero values (e.g. hashLeftRight(0, 0) vs
     * hash5([0, 0, 0, 0, 0]). Moreover, the zero value may be a
     * nothing-up-my-sleeve value.
     */
    function getZero(uint256 _height) internal virtual view returns (uint256) {}

    function root() public view returns (uint256) {
        return nodes[0];
    }

    function pathIndexOf(uint256 _leafIdx) public view returns (uint256[] memory) {
        require(_leafIdx < MAX_LEAVES_COUNT, "not a leaf");

        uint256 idx = _leafIdx0 + _leafIdx;
        uint256[] memory pathIndex = new uint256[](DEPTH);

        for (uint256 i = 0; i < DEPTH; i++) {
            assert(idx > 0);

            uint256 parentIdx = (idx - 1) / 5;
            uint256 childrenIdx0 = parentIdx * 5 + 1;

            pathIndex[i] = idx - childrenIdx0;

            idx = parentIdx;
        }
        return pathIndex;
    }

    function pathElementOf(uint256 _leafIdx) public view returns (uint256[4][] memory) {
        require(_leafIdx < MAX_LEAVES_COUNT, "not a leaf");

        uint256 idx = _leafIdx0 + _leafIdx;
        uint256[4][] memory pathElement = new uint256[4][](DEPTH);
    
        for (uint256 height = 0; height < DEPTH; height++) {
            assert(idx > 0);

            uint256 zero = getZero(height);
            uint256 parentIdx = (idx - 1) / 5;
            uint256 childrenIdx0 = parentIdx * 5 + 1;
            
            uint256 i = 0;
            uint256 j = childrenIdx0;
            for (; j < idx; j++) {
                uint256 child = nodes[j];
                if (child == 0) {
                    child = zero;
                }

                pathElement[height][i] = child;
                i++;
            }

            for (j = idx + 1; j < childrenIdx0 + 5; j++) {
                uint256 child = nodes[j];
                if (child == 0) {
                    child = zero;
                }

                pathElement[height][i] = child;
                i++;
            }

            idx = parentIdx;
        }
        return pathElement;
    }

    function enqueue(uint256 _leaf) public onlyMACI returns (uint256 index) {
        require(leavesCount < MAX_LEAVES_COUNT, "tree is already full");

        index = leavesCount;
        uint256 leafIdx = _leafIdx0 + leavesCount;
        nodes[leafIdx] = _leaf;
        _updateAt(leafIdx);
        leavesCount++;
    }

    // function update(uint256 _index, uint256 _leaf) public onlyMACI {
    //     require(_index - _leafIdx0 < leavesCount, "must update from a leaf");

    //     nodes[_index] = _leaf;
    //     _updateAt(_index);
    // }

    function _updateAt(uint256 _index) private {
        require(_index >= _leafIdx0, "must update from height 0");

        uint256 idx = _index;
        uint256 height = 0;
        while (idx > 0) {
            uint256 parentIdx = (idx - 1) / 5;
            uint256 childrenIdx0 = parentIdx * 5 + 1;

            uint256 zero = getZero(height);

            uint256[5] memory inputs;
            for (uint256 i = 0; i < 5; i++) {
                uint256 child = nodes[childrenIdx0 + i];
                if (child == 0) {
                    child = zero;
                }
                inputs[i] = child;
            }
            nodes[parentIdx] = PoseidonT6.poseidon(inputs);

            height++;
            idx = parentIdx;
        }
    }
}

contract QuinaryTreeBlankSl is SimpleQuinaryTree, MerkleZeros {
    constructor(uint256 _depth) SimpleQuinaryTree(_depth) {}
    function getZero(uint256 _height) internal view override returns (uint256) { return zeros[_height + 1]; }
}
