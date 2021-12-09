// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { DomainObjs } from "./DomainObjs.sol";
import { Ownable } from "./Ownable.sol";
import { SnarkCommon } from "./crypto/SnarkCommon.sol";
import { QuinaryTreeBlankSl } from "./store/SimpleQuinaryTree.sol";
// import { SnarkConstants } from "./crypto/SnarkConstants.sol"; // SnarkConstants -> Hasher -> DomainObjs


contract SimpleMACI is DomainObjs, SnarkCommon, Ownable {
    enum Period {
        Pending,
        Voting,
        Processing,
        Tallying,
        Ended
    }

    uint256 constant private STATE_TREE_ARITY = 5;

    Period public period;
    uint256 public batchSize;
    uint256 public msgChainLength;
    mapping (uint256 => uint256) public msgHashes;

    uint256 public numSignUps;

    QuinaryTreeBlankSl public stateTree;
    uint256 public maxStateIdx;

    event SignUp(uint256 indexed _stateIdx, PubKey _userPubKey, uint256 _voiceCreditBalance);
    event PublishMessage(uint256 indexed _msgIdx, Message _message, PubKey _encPubKey);

    modifier atPeriod(Period _p) {
        require(_p == period, "MACI: period error");
        _;
    }
    
    function init(
        address _admin,
        QuinaryTreeBlankSl _stateTree,
        uint256 _batchSize
    ) public atPeriod(Period.Pending) {
        admin = _admin;
        stateTree = _stateTree;
        batchSize = _batchSize;

        _stateTree.init();

        period = Period.Voting;
    }

    function signUp(
        PubKey memory _pubKey,
        uint256 _balance
    ) public atPeriod(Period.Voting) {
        require(
            _pubKey.x < SNARK_SCALAR_FIELD && _pubKey.y < SNARK_SCALAR_FIELD,
            "MACI: _pubKey values should be less than the snark scalar field"
        );

        /** DEV **/
        uint256 voiceCreditBalance = _balance;

        uint256 stateLeaf = hashStateLeaf(
            StateLeaf(_pubKey, voiceCreditBalance, 0, 0)
        );
        uint256 stateIndex = stateTree.enqueue(stateLeaf);

        emit SignUp(stateIndex, _pubKey, voiceCreditBalance);
    }

    function publishMessage(
        Message memory _message,
        PubKey memory _encPubKey
    ) public atPeriod(Period.Voting) {
        require(
            _encPubKey.x != 0 &&
            _encPubKey.y != 1 &&
            _encPubKey.x < SNARK_SCALAR_FIELD &&
            _encPubKey.y < SNARK_SCALAR_FIELD,
            "MACI: invalid _encPubKey"
        );

        msgHashes[msgChainLength + 1] = hashMessageAndEncPubKey(
            _message,
            _encPubKey,
            msgHashes[msgChainLength]
        );

        emit PublishMessage(msgChainLength, _message, _encPubKey);
        msgChainLength++;
    }

    function hashMessageAndEncPubKey(
        Message memory _message,
        PubKey memory _encPubKey,
        uint256 _prevHash
    ) public pure returns (uint256) {
        uint256[5] memory m;
        m[0] = _message.data[0];
        m[1] = _message.data[1];
        m[2] = _message.data[2];
        m[3] = _message.data[3];
        m[4] = _message.data[4];

        uint256[5] memory n;
        n[0] = _message.data[5];
        n[1] = _message.data[6];
        n[2] = _encPubKey.x;
        n[3] = _encPubKey.y;
        n[4] = _prevHash;

        return hash2([hash5(m), hash5(n)]);
    }

    function stopVotingPeriod() public onlyOwner atPeriod(Period.Voting) {
        period = Period.Processing;
    }
}
