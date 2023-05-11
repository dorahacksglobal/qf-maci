pragma circom 2.0.0;

include "./hasherSha256.circom";
include "./messageHasher.circom";
include "./messageToCommand.circom";
include "./verifySignature.circom";
include "./privToPubKey.circom";
include "./trees/incrementalQuinTree.circom";
include "../node_modules/circomlib/circuits/mux1.circom";

template ProcessDeactivateMessages(
    stateTreeDepth,
    batchSize
) {
    // stateTreeDepth: the depth of the state tree
    // voteOptionTreeDepth: depth of the vote option tree
    // batchSize: number of messages processed at one time

    assert(stateTreeDepth > 0);
    assert(batchSize > 0);

    var TREE_ARITY = 5;

    var MSG_LENGTH = 7;
    var PACKED_CMD_LENGTH = 3;

    // var BALLOT_LENGTH = 2;
    // var BALLOT_NONCE_IDX = 0;
    // var BALLOT_VO_ROOT_IDX = 1;

    var STATE_LEAF_LENGTH = 5;

    var STATE_LEAF_PUB_X_IDX = 0;
    var STATE_LEAF_PUB_Y_IDX = 1;
    var STATE_LEAF_VOICE_CREDIT_BALANCE_IDX = 2;
    var STATE_LEAF_VO_ROOT_IDX = 3;
    var STATE_LEAF_NONCE_IDX = 4;
    
    // Note that we sha256 hash some values from the contract, pass in the hash
    // as a public input, and pass in said values as private inputs. This saves
    // a lot of gas for the verifier at the cost of constraints for the prover.

    //  ----------------------------------------------------------------------- 
    // The only public input, which is the SHA256 hash of a values provided
    // by the contract
    signal input inputHash;

    signal input currentActiveStateRoot;
    signal input currentDeactivateRoot;

    signal input batchStartHash;
    signal input batchEndHash;

    // The coordinator's private key
    signal input coordPrivKey;

    // The cooordinator's public key from the contract.
    signal input coordPubKey[2];

    // The messages
    signal input msgs[batchSize][MSG_LENGTH];

    // The ECDH public key per message
    signal input encPubKeys[batchSize][2];

    // Random number
    signal input nonce[batchSize];

    signal input currentActiveState[batchSize];
    signal input newActiveState[batchSize];

    signal input deactivateIndex0;

    // The signup state root
    signal input currentStateRoot;

    // The state leaves upon which messages are applied.
    signal input currentStateLeaves[batchSize][STATE_LEAF_LENGTH];
    signal input currentStateLeavesPathElements[batchSize][stateTreeDepth][TREE_ARITY - 1];

    signal input activeStateLeavesPathElements[batchSize][stateTreeDepth][TREE_ARITY - 1];

    signal input deactivateLeavesPathElements[batchSize][stateTreeDepth][TREE_ARITY - 1];

    //
    signal input currentDeactivateCommitment;

    //
    signal input newDeactivateRoot;
    signal input newDeactivateCommitment;

    // Verify "public" inputs and assign unpacked values
    component inputHasher = ProcessDeactivateMessagesInputHasher();
    inputHasher.newDeactivateRoot <== newDeactivateRoot;
    inputHasher.coordPubKey[0] <== coordPubKey[0];
    inputHasher.coordPubKey[1] <== coordPubKey[1];
    inputHasher.batchStartHash <== batchStartHash;
    inputHasher.batchEndHash <== batchEndHash;
    inputHasher.currentDeactivateCommitment <== currentDeactivateCommitment;
    inputHasher.newDeactivateCommitment <== newDeactivateCommitment;
    inputHasher.currentStateRoot <== currentStateRoot;

    inputHasher.hash === inputHash;
    //  ----------------------------------------------------------------------- 
    //  Check whether each message exists in the message hash chain. Throw
    //  if otherwise (aka create a constraint that prevents such a proof).

    component messageHashers[batchSize];
    component isEmptyMsg[batchSize];
    component muxes[batchSize];

    signal msgHashChain[batchSize + 1];
    msgHashChain[0] <== batchStartHash;

    // msgChainHash[m] = isEmptyMessage
    //   ? msgChainHash[m - 1]
    //   : hash( hash(msg[m]) , msgChainHash[m - 1] )

    for (var i = 0; i < batchSize; i ++) {
        messageHashers[i] = MessageHasher();
        for (var j = 0; j < MSG_LENGTH; j ++) {
            messageHashers[i].in[j] <== msgs[i][j];
        }
        messageHashers[i].encPubKey[0] <== encPubKeys[i][0];
        messageHashers[i].encPubKey[1] <== encPubKeys[i][1];
        messageHashers[i].prevHash <== msgHashChain[i];

        isEmptyMsg[i] = IsZero();
        isEmptyMsg[i].in <== msgs[i][0];

        muxes[i] = Mux1();
        muxes[i].s <== isEmptyMsg[i].out;
        muxes[i].c[0] <== messageHashers[i].hash;
        muxes[i].c[1] <== msgHashChain[i];

        msgHashChain[i + 1] <== muxes[i].out;
    }
    msgHashChain[batchSize] === batchEndHash;

    //  ----------------------------------------------------------------------- 
    //  Decrypt each Message to a Command

    // MessageToCommand derives the ECDH shared key from the coordinator's
    // private key and the message's ephemeral public key. Next, it uses this
    // shared key to decrypt a Message to a Command.

    // Ensure that the coordinator's public key from the contract is correct
    // based on the given private key - that is, the prover knows the
    // coordinator's private key.
    component derivedPubKey = PrivToPubKey();
    derivedPubKey.privKey <== coordPrivKey;
    derivedPubKey.pubKey[0] === coordPubKey[0];
    derivedPubKey.pubKey[1] === coordPubKey[1];

    // Decrypt each Message into a Command
    component commands[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        commands[i] = MessageToCommand();
        commands[i].encPrivKey <== coordPrivKey;
        commands[i].encPubKey[0] <== encPubKeys[i][0];
        commands[i].encPubKey[1] <== encPubKeys[i][1];
        for (var j = 0; j < MSG_LENGTH; j ++) {
            commands[i].message[j] <== msgs[i][j];
        }
    }

    //  ----------------------------------------------------------------------- 
    //  Process messages in reverse order
    component currentDeactivateCommitmentHasher = HashLeftRight();
    currentDeactivateCommitmentHasher.left <== currentActiveStateRoot;
    currentDeactivateCommitmentHasher.right <== currentDeactivateRoot;

    currentDeactivateCommitmentHasher.hash === currentDeactivateCommitment;

    signal activeStateRoot[batchSize + 1];
    signal deactivateRoot[batchSize + 1];

    activeStateRoot[0] <== currentActiveStateRoot;
    deactivateRoot[0] <== currentDeactivateRoot;

    component processors[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        processors[i] = ProcessOne(stateTreeDepth);

        processors[i].isEmptyMsg <== isEmptyMsg[i].out;

        processors[i].currentActiveStateRoot <== activeStateRoot[i];
        processors[i].currentDeactivateRoot <== deactivateRoot[i];

        processors[i].coordPrivKey <== coordPrivKey;
        processors[i].currentStateRoot <== currentStateRoot;
        processors[i].nonce <== nonce[i];

        for (var j = 0; j < STATE_LEAF_LENGTH; j ++) {
            processors[i].stateLeaf[j] <== currentStateLeaves[i][j];
        }

        for (var j = 0; j < stateTreeDepth; j ++) {
            for (var k = 0; k < TREE_ARITY - 1; k ++) {
                processors[i].stateLeafPathElements[j][k] 
                    <== currentStateLeavesPathElements[i][j][k];
                processors[i].activeStateLeafPathElements[j][k] 
                    <== activeStateLeavesPathElements[i][j][k];
                processors[i].deactivateLeafPathElements[j][k] 
                    <== deactivateLeavesPathElements[i][j][k];
            }
        }

        processors[i].currentActiveState <== currentActiveState[i];
        processors[i].newActiveState <== newActiveState[i];

        processors[i].cmdStateIndex <== commands[i].stateIndex;
        // processors[i].cmdNewPubKey[0] <== commands[i].newPubKey[0];
        // processors[i].cmdNewPubKey[1] <== commands[i].newPubKey[1];
        // processors[i].cmdVoteOptionIndex <== commands[i].voteOptionIndex;
        // processors[i].cmdNewVoteWeight <== commands[i].newVoteWeight;
        // processors[i].cmdNonce <== commands[i].nonce;
        processors[i].cmdSigR8[0] <== commands[i].sigR8[0];
        processors[i].cmdSigR8[1] <== commands[i].sigR8[1];
        processors[i].cmdSigS <== commands[i].sigS;
        for (var j = 0; j < PACKED_CMD_LENGTH; j ++) {
            processors[i].packedCmd[j] <== commands[i].packedCommandOut[j];
        }

        processors[i].deactivateIndex <== i + deactivateIndex0;

        activeStateRoot[i + 1] <== processors[i].newActiveStateRoot;
        deactivateRoot[i + 1] <== processors[i].newDeactivateRoot;
    }

    newDeactivateRoot === deactivateRoot[batchSize];

    component newDeactivateCommitmentHasher = HashLeftRight();
    newDeactivateCommitmentHasher.left <== activeStateRoot[batchSize];
    newDeactivateCommitmentHasher.right <== deactivateRoot[batchSize];

    newDeactivateCommitmentHasher.hash === newDeactivateCommitment;
}

template ProcessOne(stateTreeDepth) {
    var MSG_LENGTH = 7;
    var PACKED_CMD_LENGTH = 3;
    var TREE_ARITY = 5;

    var MAX_INDEX = 5 ** stateTreeDepth;

    var STATE_LEAF_LENGTH = 5;

    var STATE_LEAF_PUB_X_IDX = 0;
    var STATE_LEAF_PUB_Y_IDX = 1;
    var STATE_LEAF_VOICE_CREDIT_BALANCE_IDX = 2;
    var STATE_LEAF_VO_ROOT_IDX = 3;
    var STATE_LEAF_NONCE_IDX = 4;

    signal input isEmptyMsg;

    signal input coordPrivKey;

    signal input currentStateRoot;

    signal input nonce;

    signal input currentActiveStateRoot;
    signal input currentDeactivateRoot;

    signal input stateLeaf[STATE_LEAF_LENGTH];
    signal input stateLeafPathElements[stateTreeDepth][TREE_ARITY - 1];

    signal input activeStateLeafPathElements[stateTreeDepth][TREE_ARITY - 1];

    signal input currentActiveState;
    signal input newActiveState;

    signal input cmdStateIndex;
    signal input cmdSigR8[2];
    signal input cmdSigS;
    signal input packedCmd[PACKED_CMD_LENGTH];

    signal input deactivateIndex;
    signal input deactivateLeafPathElements[stateTreeDepth][TREE_ARITY - 1];

    // signal input deactivateLeaf;

    signal output newActiveStateRoot;
    signal output newDeactivateRoot;

    // 1.1
    component validSignature = VerifySignature();
    validSignature.pubKey[0] <== stateLeaf[STATE_LEAF_PUB_X_IDX];
    validSignature.pubKey[1] <== stateLeaf[STATE_LEAF_PUB_Y_IDX];
    validSignature.R8[0] <== cmdSigR8[0];
    validSignature.R8[1] <== cmdSigR8[1];
    validSignature.S <== cmdSigS;
    for (var i = 0; i < PACKED_CMD_LENGTH; i ++) {
        validSignature.preimage[i] <== packedCmd[i];
    }
    // 1.2
    component validStateLeafIndex = LessEqThan(252);
    validStateLeafIndex.in[0] <== cmdStateIndex;
    validStateLeafIndex.in[1] <== MAX_INDEX;

    component valid = IsEqual();
    valid.in[0] <== 2;
    valid.in[1] <== validSignature.valid +
                    validStateLeafIndex.out;

    //  ----------------------------------------------------------------------- 
    // . Verify that the state leaf exists in the given state root
    component stateIndexMux = Mux1();
    stateIndexMux.s <== valid.out;
    stateIndexMux.c[0] <== 0;
    stateIndexMux.c[1] <== cmdStateIndex;

    component stateLeafPathIndices = QuinGeneratePathIndices(stateTreeDepth);
    stateLeafPathIndices.in <== stateIndexMux.out;

    component stateLeafQip = QuinTreeInclusionProof(stateTreeDepth);
    component stateLeafHasher = Hasher5();
    for (var i = 0; i < STATE_LEAF_LENGTH; i++) {
        stateLeafHasher.in[i] <== stateLeaf[i];
    }
    stateLeafQip.leaf <== stateLeafHasher.hash;
    for (var i = 0; i < stateTreeDepth; i ++) {
        stateLeafQip.path_index[i] <== stateLeafPathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            stateLeafQip.path_elements[i][j] <== stateLeafPathElements[i][j];
        }
    }
    stateLeafQip.root === currentStateRoot;

    //  ----------------------------------------------------------------------- 
    // .
    component ecdh = Ecdh();
    ecdh.privKey <== coordPrivKey;
    ecdh.pubKey[0] <== stateLeaf[STATE_LEAF_PUB_X_IDX];
    ecdh.pubKey[1] <== stateLeaf[STATE_LEAF_PUB_Y_IDX];

    component deactivateLeafHasher = HashLeftRight();
    deactivateLeafHasher.left <== ecdh.sharedKey[0];
    deactivateLeafHasher.right <== ecdh.sharedKey[1];

    component randomHasher = HashLeftRight();
    randomHasher.left <== nonce;
    randomHasher.right <== coordPrivKey;

    component deactivateLeafMux = Mux1();
    deactivateLeafMux.s <== valid.out;
    deactivateLeafMux.c[0] <== randomHasher.hash;
    deactivateLeafMux.c[1] <== deactivateLeafHasher.hash;

    // deactivateLeafMux.out === deactivateLeaf;

    //  ----------------------------------------------------------------------- 
    // .
    component activeStateIsZero = IsZero();
    activeStateIsZero.in <== newActiveState;

    activeStateIsZero.out === 0;

    component activeStateMux = Mux1();
    activeStateMux.s <== valid.out;
    activeStateMux.c[0] <== currentActiveState;
    activeStateMux.c[1] <== newActiveState;

    //  ----------------------------------------------------------------------- 
    // .
    component activeStateQie = QuinLeafExists(stateTreeDepth);
    activeStateQie.leaf <== currentActiveState;
    activeStateQie.root <== currentActiveStateRoot;
    for (var i = 0; i < stateTreeDepth; i ++) {
        activeStateQie.path_index[i] <== stateLeafPathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            activeStateQie.path_elements[i][j] <== activeStateLeafPathElements[i][j];
        }
    }

    component newActiveStateQip = QuinTreeInclusionProof(stateTreeDepth);
    newActiveStateQip.leaf <== activeStateMux.out;
    for (var i = 0; i < stateTreeDepth; i ++) {
        newActiveStateQip.path_index[i] <== stateLeafPathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            newActiveStateQip.path_elements[i][j] <== activeStateLeafPathElements[i][j];
        }
    }
    newActiveStateRoot <== newActiveStateQip.root;

    //  ----------------------------------------------------------------------- 
    // .
    component deactivatePathIndices = QuinGeneratePathIndices(stateTreeDepth);
    deactivatePathIndices.in <== deactivateIndex;

    component deactivateLeafQie = QuinLeafExists(stateTreeDepth);
    deactivateLeafQie.leaf <== 0;
    deactivateLeafQie.root <== currentDeactivateRoot;
    for (var i = 0; i < stateTreeDepth; i ++) {
        deactivateLeafQie.path_index[i] <== deactivatePathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            deactivateLeafQie.path_elements[i][j] <== deactivateLeafPathElements[i][j];
        }
    }

    component newDeactivateLeafQip = QuinTreeInclusionProof(stateTreeDepth);
    newDeactivateLeafQip.leaf <== deactivateLeafMux.out * (1 - isEmptyMsg);
    for (var i = 0; i < stateTreeDepth; i ++) {
        newDeactivateLeafQip.path_index[i] <== deactivatePathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            newDeactivateLeafQip.path_elements[i][j] <== deactivateLeafPathElements[i][j];
        }
    }
    newDeactivateRoot <== newDeactivateLeafQip.root;
}

template ProcessDeactivateMessagesInputHasher() {
    signal input newDeactivateRoot;
    signal input coordPubKey[2];
    signal input batchStartHash;
    signal input batchEndHash;
    signal input currentDeactivateCommitment;
    signal input newDeactivateCommitment;
    signal input currentStateRoot;

    signal output hash;

    // 1. Hash coordPubKey
    component pubKeyHasher = HashLeftRight();
    pubKeyHasher.left <== coordPubKey[0];
    pubKeyHasher.right <== coordPubKey[1];

    // 2. Hash the 7 inputs with SHA256
    component hasher = Sha256Hasher(7);
    hasher.in[0] <== newDeactivateRoot;
    hasher.in[1] <== pubKeyHasher.hash;
    hasher.in[2] <== batchStartHash;
    hasher.in[3] <== batchEndHash;
    hasher.in[4] <== currentDeactivateCommitment;
    hasher.in[5] <== newDeactivateCommitment;
    hasher.in[6] <== currentStateRoot;

    hash <== hasher.hash;
}
