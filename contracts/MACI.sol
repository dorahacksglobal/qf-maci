// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import {DomainObjs} from "./DomainObjs.sol";
import {Ownable} from "./Ownable.sol";
import {VkRegistry} from "./VkRegistry.sol";
import {Verifier} from "./crypto/Verifier.sol";
import {SnarkCommon} from "./crypto/SnarkCommon.sol";
import {SignUpGatekeeper} from "./gatekeepers/SignUpGatekeeper.sol";
import {QuinaryTreeRoot} from "./store/QuinaryTreeRoot.sol";

// import { SnarkConstants } from "./crypto/SnarkConstants.sol"; // SnarkConstants -> Hasher -> DomainObjs

contract MACI is DomainObjs, SnarkCommon, Ownable {
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

    uint256 private constant STATE_TREE_ARITY = 5;

    uint256 public coordinatorHash;

    SignUpGatekeeper public gateKeeper;

    // The verifying key registry. There may be multiple verifying keys stored
    // on chain, and Poll contracts must select the correct VK based on the
    // circuit's compile-time parameters, such as tree depths and batch sizes.
    VkRegistry public vkRegistry;

    // Verify the results at the final counting stage.
    QuinaryTreeRoot public qtrLib;

    Verifier public verifier;

    MaciParameters public parameters;

    Period public period;

    mapping(address => uint256) public _discard_stateIdxInc; // disacrd
    mapping(uint256 => uint256) private _discard_voiceCreditBalance; // disacrd

    uint256 public numSignUps;
    uint256 public maxVoteOptions;

    uint256 public msgChainLength;
    mapping(uint256 => uint256) public msgHashes;
    uint256 public currentStateCommitment;
    uint256 private _processedMsgCount;

    uint256 public currentTallyCommitment;
    uint256 private _processedUserCount;

    mapping(uint256 => uint256) public result;

    uint256 private _maxLeavesCount;
    uint256 private _leafIdx0;
    uint256[8] private _zeros;
    /*
     *  length: (5 ** (depth + 1) - 1) / 4
     *
     *  hashes(leaves) at depth D: nodes[n]
     *  n => [ (5**D-1)/4 , (5**(D+1)-1)/4 )
     */
    mapping(uint256 => uint256) private _nodes;

    uint256 public totalResult;

    /** A-MACI */
    uint256 public voiceCreditBalance;

    uint256 public dmsgChainLength;
    mapping(uint256 => uint256) public dmsgHashes;
    mapping(uint256 => uint256) private _stateRootByDMsg;
    uint256 private _processedDMsgCount;

    mapping(uint256 => uint256) private _dnodes;
    uint256 public deactivatedCount;

    mapping(uint256 => bool) public nullifiers;

    uint256 public currentDeactivateCommitment;

    event SignUp(
        uint256 indexed _stateIdx,
        PubKey _userPubKey,
        uint256 _voiceCreditBalance
    );
    event PublishDeactivateMessage(
        uint256 indexed _msgIdx,
        uint256 numSignUps,
        Message _message,
        PubKey _encPubKey
    );
    event PublishMessage(
        uint256 indexed _msgIdx,
        Message _message,
        PubKey _encPubKey
    );

    modifier atPeriod(Period _p) {
        require(_p == period, "MACI: period error");
        _;
    }

    function init(
        address _admin,
        uint256 _voiceCreditBalance,
        VkRegistry _vkRegistry,
        QuinaryTreeRoot _qtrLib,
        Verifier _verifier,
        SignUpGatekeeper _gateKeeper,
        MaciParameters memory _parameters,
        PubKey memory _coordinator
    ) public atPeriod(Period.Pending) {
        admin = _admin;
        voiceCreditBalance = _voiceCreditBalance;
        vkRegistry = _vkRegistry;
        qtrLib = _qtrLib;
        verifier = _verifier;
        gateKeeper = _gateKeeper;
        parameters = _parameters;
        coordinatorHash = hash2([_coordinator.x, _coordinator.y]);

        // _stateTree.init();
        _maxLeavesCount = 5 ** _parameters.stateTreeDepth;
        _leafIdx0 = (_maxLeavesCount - 1) / 4;

        _zeros[
            0
        ] = 14655542659562014735865511769057053982292279840403315552050801315682099828156;
        _zeros[
            1
        ] = 19261153649140605024552417994922546473530072875902678653210025980873274131905;
        _zeros[
            2
        ] = 21526503558325068664033192388586640128492121680588893182274749683522508994597;
        _zeros[
            3
        ] = 20017764101928005973906869479218555869286328459998999367935018992260318153770;
        _zeros[
            4
        ] = 16998355316577652097112514691750893516081130026395813155204269482715045879598;
        _zeros[
            5
        ] = 2612442706402737973181840577010736087708621987282725873936541279764292204086;
        _zeros[
            6
        ] = 17716535433480122581515618850811568065658392066947958324371350481921422579201;
        _zeros[
            7
        ] = 17437916409890180001398333108882255895598851862997171508841759030332444017770;

        currentDeactivateCommitment = hash2(
            [
                _zeros[_parameters.stateTreeDepth - 1],
                _zeros[_parameters.stateTreeDepth - 1]
            ]
        );

        period = Period.Voting;
    }

    function setParameters(MaciParameters memory _parameters) public onlyOwner {
        parameters = _parameters;
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

    function stateOf(address _signer) public view returns (uint256, uint256) {
        uint256 ii = _discard_stateIdxInc[_signer];
        require(ii >= 1);
        uint256 stateIdx = ii - 1;
        // uint256 balance = voiceCreditBalance[stateIdx];
        return (stateIdx, voiceCreditBalance);
    }

    function signUp(
        PubKey memory _pubKey,
        bytes memory _data
    ) public atPeriod(Period.Voting) {
        require(numSignUps < _maxLeavesCount, "full");
        require(
            _pubKey.x < SNARK_SCALAR_FIELD && _pubKey.y < SNARK_SCALAR_FIELD,
            "MACI: _pubKey values should be less than the snark scalar field"
        );

        (bool valid, uint256 _balance) = gateKeeper.register(msg.sender, _data);
        _balance;

        require(valid, "401");

        uint256 stateLeaf = hashStateLeaf(
            StateLeaf(_pubKey, voiceCreditBalance, 0, 0)
        );
        uint256 stateIndex = numSignUps;
        _stateEnqueue(stateLeaf);

        // _discard_stateIdxInc[msg.sender] = numSignUps;
        // voiceCreditBalance[stateIndex] = balance;

        emit SignUp(stateIndex, _pubKey, voiceCreditBalance);
    }

    function publishDeactivateMessage(
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

        dmsgHashes[dmsgChainLength + 1] = hashMessageAndEncPubKey(
            _message,
            _encPubKey,
            dmsgHashes[dmsgChainLength]
        );
        _stateRootByDMsg[dmsgChainLength + 1] = _stateRoot();

        emit PublishDeactivateMessage(
            dmsgChainLength,
            numSignUps,
            _message,
            _encPubKey
        );
        dmsgChainLength++;
    }

    function processDeactivateMessage(
        uint256 size,
        uint256 newDeactivateCommitment,
        uint256[] memory _newDeactivated,
        uint256[8] memory _proof
    ) public atPeriod(Period.Voting) {
        require(
            _processedDMsgCount < dmsgChainLength,
            "all messages have been processed"
        );

        uint256 batchSize = parameters.messageBatchSize;
        require(size <= batchSize);

        uint256 c = deactivatedCount + _leafIdx0;
        for (uint256 i = 0; i < _newDeactivated.length; i++) {
            _dnodes[c] = _newDeactivated[i];
            c++;
        }
        _dUpdateBetween(deactivatedCount + _leafIdx0, c - 1);
        deactivatedCount = c - _leafIdx0;
        // uint256 newDeactivateRoot = _dnodes[0];

        uint256[] memory input = new uint256[](7);
        input[0] = _dnodes[0]; // newDeactivateRoot
        input[1] = coordinatorHash; // coordPubKeyHash

        uint256 batchStartIndex = _processedDMsgCount;
        uint256 batchEndIdx = batchStartIndex + size;
        if (batchEndIdx > dmsgChainLength) {
            batchEndIdx = dmsgChainLength;
        }
        input[2] = dmsgHashes[batchStartIndex]; // batchStartHash
        input[3] = dmsgHashes[batchEndIdx]; // batchEndHash

        input[4] = currentDeactivateCommitment;
        input[5] = newDeactivateCommitment;
        input[6] = _stateRootByDMsg[batchEndIdx];

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) %
            SNARK_SCALAR_FIELD;

        VerifyingKey memory vk = vkRegistry.getDeactivateVk(
            parameters.stateTreeDepth,
            batchSize
        );

        bool isValid = verifier.verify(_proof, vk, inputHash);
        require(isValid, "invalid proof");

        // Proof success, update commitment and progress.
        currentDeactivateCommitment = newDeactivateCommitment;
        _processedDMsgCount += batchEndIdx - batchStartIndex;
    }

    function addNewKey(
        PubKey memory _pubKey,
        uint256 _nullifier,
        uint256[8] memory _proof
    ) public atPeriod(Period.Voting) {
        require(!nullifiers[_nullifier]);
        nullifiers[_nullifier] = true;

        require(numSignUps < _maxLeavesCount, "full");
        require(
            _pubKey.x < SNARK_SCALAR_FIELD && _pubKey.y < SNARK_SCALAR_FIELD,
            "MACI: _pubKey values should be less than the snark scalar field"
        );

        uint256[] memory input = new uint256[](3);
        input[0] = _dnodes[0]; // newDeactivateRoot
        input[1] = coordinatorHash; // coordPubKeyHash
        input[2] = _nullifier;

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) %
            SNARK_SCALAR_FIELD;

        VerifyingKey memory vk = vkRegistry.getNewkeyVkBy(
            parameters.stateTreeDepth
        );

        bool isValid = verifier.verify(_proof, vk, inputHash);
        require(isValid, "invalid proof");

        uint256 stateLeaf = hashStateLeaf(
            StateLeaf(_pubKey, voiceCreditBalance, 0, 0)
        );
        uint256 stateIndex = numSignUps;
        _stateEnqueue(stateLeaf);

        // _discard_stateIdxInc[msg.sender] = numSignUps;

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

    function batchPublishMessage(
        Message[] memory _messages,
        PubKey[] memory _encPubKeys
    ) public {
        require(_messages.length == _encPubKeys.length);
        for (uint256 i = 0; i < _messages.length; i++) {
            publishMessage(_messages[i], _encPubKeys[i]);
        }
    }

    function stopVotingPeriod(
        uint256 _maxVoteOptions
    ) public onlyOwner atPeriod(Period.Voting) {
        maxVoteOptions = _maxVoteOptions;
        period = Period.Processing;

        currentStateCommitment = hash2([_stateRoot(), 0]);
    }

    // Transfer state root according to message queue.
    function processMessage(
        uint256 newStateCommitment,
        uint256[8] memory _proof
    ) public atPeriod(Period.Processing) {
        require(
            _processedMsgCount < msgChainLength,
            "all messages have been processed"
        );

        uint256 batchSize = parameters.messageBatchSize;

        uint256[] memory input = new uint256[](7);
        input[0] = (numSignUps << uint256(32)) + maxVoteOptions; // packedVals
        input[1] = coordinatorHash; // coordPubKeyHash

        uint256 batchStartIndex = ((msgChainLength - _processedMsgCount - 1) /
            batchSize) * batchSize;
        uint256 batchEndIdx = batchStartIndex + batchSize;
        if (batchEndIdx > msgChainLength) {
            batchEndIdx = msgChainLength;
        }
        input[2] = msgHashes[batchStartIndex]; // batchStartHash
        input[3] = msgHashes[batchEndIdx]; // batchEndHash

        input[4] = currentStateCommitment;
        input[5] = newStateCommitment;
        input[6] = currentDeactivateCommitment;

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) %
            SNARK_SCALAR_FIELD;

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
        require(
            _processedUserCount < numSignUps,
            "all users have been processed"
        );

        uint256 batchSize = 5 ** parameters.intStateTreeDepth;
        uint256 batchNum = _processedUserCount / batchSize;

        uint256[] memory input = new uint256[](4);
        input[0] = (numSignUps << uint256(32)) + batchNum; // packedVals

        // The state commitment will not change after
        // the end of the processing period.
        input[1] = currentStateCommitment; // stateCommitment
        input[2] = currentTallyCommitment; // tallyCommitment
        input[3] = newTallyCommitment; // newTallyCommitment

        uint256 inputHash = uint256(sha256(abi.encodePacked(input))) %
            SNARK_SCALAR_FIELD;

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

    function stopTallyingPeriod(
        uint256[] memory _results,
        uint256 _salt
    ) public atPeriod(Period.Tallying) {
        require(_processedUserCount >= numSignUps);
        require(_results.length <= maxVoteOptions);

        uint256 resultsRoot = qtrLib.rootOf(
            parameters.voteOptionTreeDepth,
            _results
        );
        uint256 tallyCommitment = hash2([resultsRoot, _salt]);

        require(tallyCommitment == currentTallyCommitment);

        uint256 sum = 0;
        for (uint256 i = 0; i < _results.length; i++) {
            result[i] = _results[i];
            sum += _results[i];
        }
        totalResult = sum;

        period = Period.Ended;
    }

    function stopTallyingPeriodWithoutResults()
        public
        onlyOwner
        atPeriod(Period.Tallying)
    {
        require(_processedUserCount >= numSignUps);
        period = Period.Ended;
    }

    function _stateRoot() private view returns (uint256) {
        return _nodes[0];
    }

    function _stateEnqueue(uint256 _leaf) private {
        uint256 leafIdx = _leafIdx0 + numSignUps;
        _nodes[leafIdx] = _leaf;
        _stateUpdateAt(leafIdx);
        numSignUps++;
    }

    function _stateUpdateAt(uint256 _index) private {
        require(_index >= _leafIdx0, "must update from height 0");

        uint256 idx = _index;
        uint256 height = 0;
        while (idx > 0) {
            uint256 parentIdx = (idx - 1) / 5;
            uint256 childrenIdx0 = parentIdx * 5 + 1;

            uint256 zero = _zeros[height];

            uint256[5] memory inputs;
            for (uint256 i = 0; i < 5; i++) {
                uint256 child = _nodes[childrenIdx0 + i];
                if (child == 0) {
                    child = zero;
                }
                inputs[i] = child;
            }
            _nodes[parentIdx] = hash5(inputs);

            height++;
            idx = parentIdx;
        }
    }

    function _dUpdateBetween(uint256 _left, uint256 _right) private {
        require(_left >= _leafIdx0, "must update from height 0");
        require(_right >= _left);

        uint256 l = _left;
        uint256 r = _right;
        uint256 height = 0;
        while (l > 0) {
            uint256 zero = height == 0 ? 0 : _zeros[height - 1];

            l = (l - 1) / 5;
            r = (r - 1) / 5;

            for (uint256 idx = l; idx <= r; idx++) {
                uint256 childrenIdx0 = idx * 5 + 1;

                uint256[5] memory inputs;
                for (uint256 i = 0; i < 5; i++) {
                    uint256 child = _nodes[childrenIdx0 + i];
                    if (child == 0) {
                        child = zero;
                    }
                    inputs[i] = child;
                }
                _nodes[idx] = hash5(inputs);
            }

            height++;
        }
    }
}
