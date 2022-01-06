// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { DomainObjs } from "./DomainObjs.sol";
import { Ownable } from "./Ownable.sol";
import { VkRegistry } from "./VkRegistry.sol";
import { Verifier } from "./crypto/Verifier.sol";
import { SnarkCommon } from "./crypto/SnarkCommon.sol";
import { QuinaryTreeBlankSl } from "./store/SimpleQuinaryTree.sol";
import { QuinaryTreeRoot } from "./store/QuinaryTreeRoot.sol";
// import { SnarkConstants } from "./crypto/SnarkConstants.sol"; // SnarkConstants -> Hasher -> DomainObjs


contract SimpleMACI is DomainObjs, SnarkCommon, Ownable {
    struct MaciParameters {
        uint256 stateTreeDepth;
        uint256 intStateTreeDepth;
        uint256 messageBatchSize;
        uint256 voteOptionTreeDepth;
    }

    enum Period {
        Pending,
        Voting,
        Processing,
        Tallying,
        Ended
    }

    uint256 constant private STATE_TREE_ARITY = 5;

    uint256 public coordinatorHash;

    // The verifying key registry. There may be multiple verifying keys stored
    // on chain, and Poll contracts must select the correct VK based on the
    // circuit's compile-time parameters, such as tree depths and batch sizes.
    VkRegistry public vkRegistry;

    // Verify the results at the final counting stage.
    QuinaryTreeRoot public qtrLib;

    Verifier public verifier;

    MaciParameters public parameters;

    Period public period;

    uint256 public numSignUps;
    uint256 public maxVoteOptions;

    uint256 public msgChainLength;
    mapping (uint256 => uint256) public msgHashes;
    uint256 public currentStateCommitment;
    uint256 private _processedMsgCount;

    uint256 public currentTallyCommitment;
    uint256 private _processedUserCount;

    QuinaryTreeBlankSl public stateTree;
    uint256 public maxStateIdx;

    mapping (uint256 => uint256) public result;

    event SignUp(uint256 indexed _stateIdx, PubKey _userPubKey, uint256 _voiceCreditBalance);
    event PublishMessage(uint256 indexed _msgIdx, Message _message, PubKey _encPubKey);

    modifier atPeriod(Period _p) {
        require(_p == period, "MACI: period error");
        _;
    }
    
    function init(
        address _admin,
        VkRegistry _vkRegistry,
        QuinaryTreeRoot _qtrLib,
        Verifier _verifier,
        QuinaryTreeBlankSl _stateTree,
        MaciParameters memory _parameters,
        PubKey memory _coordinator
    ) public atPeriod(Period.Pending) {
        admin = _admin;
        vkRegistry = _vkRegistry;
        qtrLib = _qtrLib;
        verifier = _verifier;
        stateTree = _stateTree;
        parameters = _parameters;
        coordinatorHash = hash2([_coordinator.x,  _coordinator.y]);

        _stateTree.init();

        period = Period.Voting;
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
        numSignUps = stateIndex + 1;

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

    function stopVotingPeriod(uint256 _maxVoteOptions) public onlyOwner atPeriod(Period.Voting) {
        maxVoteOptions = _maxVoteOptions;
        period = Period.Processing;

        currentStateCommitment = hash2([stateTree.root() , 0]);
    }

    // Transfer state root according to message queue.
    function processMessage(
        uint256 newStateCommitment,
        uint256[8] memory _proof
    ) public atPeriod(Period.Processing) {
        require(_processedMsgCount < msgChainLength, "all messages have been processed");

        uint256 batchSize = parameters.messageBatchSize;

        uint256[] memory input = new uint256[](6);
        input[0] = (numSignUps << uint256(32)) + maxVoteOptions;    // packedVals
        input[1] = coordinatorHash;                                 // coordPubKeyHash

        uint256 batchStartIndex = (msgChainLength - _processedMsgCount - 1) / batchSize * batchSize;
        uint256 batchEndIdx = batchStartIndex + batchSize;
        if (batchEndIdx > msgChainLength) {
            batchEndIdx = msgChainLength;
        }
        input[2] = msgHashes[batchStartIndex];                      // batchStartHash
        input[3] = msgHashes[batchEndIdx];                          // batchEndHash

        input[4] = currentStateCommitment;
        input[5] = newStateCommitment;

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) % SNARK_SCALAR_FIELD;

        VerifyingKey memory vk = vkRegistry.getProcessVk(
            parameters.stateTreeDepth,
            parameters.voteOptionTreeDepth,
            batchSize
        );

        bool isValid = verifier.verify(_proof, vk, inputHash);
        require(isValid, "invalid proof");

        // Proof success, update commitment and progress.
        currentStateCommitment = newStateCommitment;
        _processedMsgCount += batchEndIdx - batchStartIndex;
    }

    function stopProcessingPeriod() public atPeriod(Period.Processing) {
        require(_processedMsgCount == msgChainLength);
        period = Period.Tallying;

        // unnecessary writes
        // currentTallyCommitment = 0;
    }

    function processTally(
        uint256 newTallyCommitment,
        uint256[8] memory _proof
    ) public atPeriod(Period.Tallying) {
        require(_processedUserCount < numSignUps, "all users have been processed");
    
        uint256 batchSize = 5 ** parameters.intStateTreeDepth;
        uint256 batchNum = _processedUserCount / batchSize;

        uint256[] memory input = new uint256[](4);
        input[0] = (numSignUps << uint256(32)) + batchNum;          // packedVals

        // The state commitment will not change after
        // the end of the processing period.
        input[1] = currentStateCommitment;                          // stateCommitment
        input[2] = currentTallyCommitment;                          // tallyCommitment
        input[3] = newTallyCommitment;                              // newTallyCommitment

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) % SNARK_SCALAR_FIELD;

        VerifyingKey memory vk = vkRegistry.getTallyVk(
            parameters.stateTreeDepth,
            parameters.intStateTreeDepth,
            parameters.voteOptionTreeDepth
        );

        bool isValid = verifier.verify(_proof, vk, inputHash);
        require(isValid, "invalid proof");

        // Proof success, update commitment and progress.
        currentTallyCommitment = newTallyCommitment;
        _processedUserCount += batchSize;
    }

    function stopTallyingPeriod(uint256[] memory _results, uint256 _salt) public atPeriod(Period.Tallying) {
        require(_processedUserCount >= numSignUps);
        require(_results.length <= maxVoteOptions);

        uint256 resultsRoot = qtrLib.rootOf(parameters.voteOptionTreeDepth, _results);
        uint256 tallyCommitment = hash2([resultsRoot, _salt]);
        
        require(tallyCommitment == currentTallyCommitment);

        for (uint256 i = 0; i < _results.length; i++) {
            result[i] = _results[i];
        }

        period = Period.Ended;
    }
}
