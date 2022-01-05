pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/comparators.circom";
include "./trees/incrementalQuinTree.circom";
include "./trees/calculateTotal.circom";
include "./trees/checkRoot.circom";
include "./trees/zeroRoot.circom";
include "./hasherSha256.circom";
include "./hasherPoseidon.circom";
include "./unpackElement.circom";

/*
 * Tally votes in the ballots, batch by batch.
 */
template TallyVotes(
    stateTreeDepth,
    intStateTreeDepth,
    voteOptionTreeDepth
) {
    assert(voteOptionTreeDepth > 0);
    assert(intStateTreeDepth > 0);
    assert(intStateTreeDepth < stateTreeDepth);

    var TREE_ARITY = 5;

    // The number of ballots in this batch
    var batchSize = TREE_ARITY ** intStateTreeDepth;
    var numVoteOptions = TREE_ARITY ** voteOptionTreeDepth;

    var STATE_LEAF_LENGTH = 5;
    var STATE_LEAF_VO_ROOT_IDX = 3;
    var STATE_LEAF_NONCE_IDX = 4;

    // stateCommitment (also stateRoot & stateSalt) will not change
    // throughout the tally votes period.
    signal input stateRoot;
    signal input stateSalt;

    // The only public input (inputHash) is the hash of the following:
    signal input packedVals;
    signal input stateCommitment;
    signal input currentTallyCommitment;
    signal input newTallyCommitment;
    
    // A tally commitment is the hash of the following salted values:
    //   - the vote results
    //   - the number of voice credits spent per vote option
    //   - the total number of spent voice credits

    signal input inputHash;

    var k = stateTreeDepth - intStateTreeDepth;
    // The states
    signal input stateLeaf[batchSize][STATE_LEAF_LENGTH];
    signal input statePathElements[k][TREE_ARITY - 1];
    signal input votes[batchSize][numVoteOptions];

    signal input currentResults[numVoteOptions];
    signal input currentResultsRootSalt;
    signal input newResultsRootSalt;

    signal input currentPerVOVotes[numVoteOptions];
    signal input currentPerVOVotesRootSalt;
    signal input newPerVOVotesRootSalt;

    signal input currentPerVOSpentVoiceCredits[numVoteOptions];
    signal input currentPerVOSpentVoiceCreditsRootSalt;
    signal input newPerVOSpentVoiceCreditsRootSalt;

    //  ----------------------------------------------------------------------- 
    // Verify stateCommitment
    component stateCommitmentHasher = HashLeftRight();
    stateCommitmentHasher.left <== stateRoot;
    stateCommitmentHasher.right <== stateSalt;
    stateCommitmentHasher.hash === stateCommitment;

    //  ----------------------------------------------------------------------- 
    // Verify inputHash
    component inputHasher = TallyVotesInputHasher();
    inputHasher.stateCommitment <== stateCommitment;
    inputHasher.currentTallyCommitment <== currentTallyCommitment;
    inputHasher.newTallyCommitment <== newTallyCommitment;
    inputHasher.packedVals <== packedVals;
    inputHasher.hash === inputHash;

    signal numSignUps;
    signal batchStartIndex;

    numSignUps <== inputHasher.numSignUps;
    batchStartIndex <== inputHasher.batchNum * batchSize;

    //  ----------------------------------------------------------------------- 
    // Validate batchStartIndex and numSignUps
    // batchStartIndex should be less than numSignUps
    component validNumSignups = LessEqThan(32);
    validNumSignups.in[0] <== batchStartIndex;
    validNumSignups.in[1] <== numSignUps;
    validNumSignups.out === 1;

    //  ----------------------------------------------------------------------- 
    // Verify the states

    // Hash each state and generate the subroot of the states
    component stateSubroot = QuinCheckRoot(intStateTreeDepth);
    component stateLeafHasher[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        stateLeafHasher[i] = Hasher5();

        for (var j = 0; j < STATE_LEAF_LENGTH; j ++) {
            stateLeafHasher[i].in[j] <== stateLeaf[i][j];
        }

        stateSubroot.leaves[i] <== stateLeafHasher[i].hash;
    }

    component stateQle = QuinLeafExists(k);
    component statePathIndices = QuinGeneratePathIndices(k);
    statePathIndices.in <== inputHasher.batchNum;
    stateQle.leaf <== stateSubroot.root;
    stateQle.root <== stateRoot;
    for (var i = 0; i < k; i ++) {
        stateQle.path_index[i] <== statePathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j ++) {
            stateQle.path_elements[i][j] <== statePathElements[i][j];
        }
    }

    //  ----------------------------------------------------------------------- 
    // vote option tree zero root
    component calculateVOTreeZeroRoot = ZeroRoot(voteOptionTreeDepth);
    signal voTreeZeroRoot;
    voTreeZeroRoot <== calculateVOTreeZeroRoot.out;

    // Verify the vote option roots
    component voteTree[batchSize];
    component slvoRootIsZero[batchSize];
    component voRootMux[batchSize];
    for (var i = 0; i < batchSize; i ++) {
        voteTree[i] = QuinCheckRoot(voteOptionTreeDepth);
        for (var j = 0; j < TREE_ARITY ** voteOptionTreeDepth; j ++) {
            voteTree[i].leaves[j] <== votes[i][j];
        }

        slvoRootIsZero[i] = IsZero();
        slvoRootIsZero[i].in <== stateLeaf[i][STATE_LEAF_VO_ROOT_IDX];
        voRootMux[i] = Mux1();
        voRootMux[i].s <== slvoRootIsZero[i].out;
        voRootMux[i].c[0] <== stateLeaf[i][STATE_LEAF_VO_ROOT_IDX];
        voRootMux[i].c[1] <== voTreeZeroRoot;

        voteTree[i].root === voRootMux[i].out;
    }

    component isFirstBatch = IsZero();
    isFirstBatch.in <== batchStartIndex;
    
    component iz = IsZero();
    iz.in <== isFirstBatch.out;

    //  ----------------------------------------------------------------------- 
    // Tally the new results
    // Tally the spent voice credits per vote option
    component resultCalc[numVoteOptions];
    for (var i = 0; i < numVoteOptions; i ++) {
        resultCalc[i] = CalculateArea(batchSize);
        resultCalc[i].currentVotes <== currentPerVOVotes[i] * iz.out;
        resultCalc[i].currentArea <== currentResults[i] * iz.out;
        for (var j = 0; j < batchSize; j ++) {
            resultCalc[i].v[j] <== votes[j][i];
        }
    }

    // Tally the spent voice credits per vote option
    component newPerVOSpentVoiceCredits[numVoteOptions];
    for (var i = 0; i < numVoteOptions; i ++) {
        newPerVOSpentVoiceCredits[i] = CalculateTotal(batchSize + 1);
        newPerVOSpentVoiceCredits[i].nums[batchSize] <== currentPerVOSpentVoiceCredits[i] * iz.out;
        for (var j = 0; j < batchSize; j ++) {
            newPerVOSpentVoiceCredits[i].nums[j] <== votes[j][i] * votes[j][i];
        }
    }

    // Verify the current and new tally
    component rcv = ResultCommitmentVerifier(voteOptionTreeDepth);
    rcv.isFirstBatch <== isFirstBatch.out;
    rcv.currentTallyCommitment <== currentTallyCommitment;
    rcv.newTallyCommitment <== newTallyCommitment;

    rcv.currentResultsRootSalt <== currentResultsRootSalt;
    rcv.newResultsRootSalt <== newResultsRootSalt;

    rcv.currentPerVOVotesRootSalt <== currentPerVOVotesRootSalt;
    rcv.newPerVOVotesRootSalt <== newPerVOVotesRootSalt;

    rcv.currentPerVOSpentVoiceCreditsRootSalt <== currentPerVOSpentVoiceCreditsRootSalt;
    rcv.newPerVOSpentVoiceCreditsRootSalt <== newPerVOSpentVoiceCreditsRootSalt;

    for (var i = 0; i < numVoteOptions; i ++) {
        rcv.currentResults[i] <== currentResults[i];
        rcv.newResults[i] <== resultCalc[i].area;
        rcv.currentPerVOVotes[i] <== currentPerVOVotes[i];
        rcv.newPerVOVotes[i] <== resultCalc[i].votes;
        rcv.currentPerVOSpentVoiceCredits[i] <== currentPerVOSpentVoiceCredits[i];
        rcv.newPerVOSpentVoiceCredits[i] <== newPerVOSpentVoiceCredits[i].sum;
    }
}

template CalculateArea(voteOptionSize) {
    var n = voteOptionSize + 1;

    signal input currentVotes;
    signal input currentArea;
    signal input v[voteOptionSize];

    signal output votes;
    signal output area;

    signal sum[n];
    sum[0] <== currentVotes;

    signal a[n];
    a[0] <== currentArea;

    for (var i = 0; i < voteOptionSize; i ++) {
        sum[i + 1] <== sum[i] + v[i];
        a[i + 1] <== a[i] + sum[i] * v[i];
    }

    votes <== sum[voteOptionSize];
    area <== a[voteOptionSize];
}

/*
 * Verifies the commitment to the current results. Also computes and outputs a
 * commitment to the new results.
 */
template ResultCommitmentVerifier(voteOptionTreeDepth) {
    var TREE_ARITY = 5;
    var numVoteOptions = TREE_ARITY ** voteOptionTreeDepth;

    // 1 if this is the first batch, and 0 otherwise
    signal input isFirstBatch;
    signal input currentTallyCommitment;
    signal input newTallyCommitment;

    // Results
    signal input currentResults[numVoteOptions];
    signal input currentResultsRootSalt;

    signal input newResults[numVoteOptions];
    signal input newResultsRootSalt;

    // Votes per vote option
    signal input currentPerVOVotes[numVoteOptions];
    signal input currentPerVOVotesRootSalt;

    signal input newPerVOVotes[numVoteOptions];
    signal input newPerVOVotesRootSalt;

    // Spent voice credits per vote option
    signal input currentPerVOSpentVoiceCredits[numVoteOptions];
    signal input currentPerVOSpentVoiceCreditsRootSalt;

    signal input newPerVOSpentVoiceCredits[numVoteOptions];
    signal input newPerVOSpentVoiceCreditsRootSalt;

    // Compute the commitment to the current results
    component currentResultsRoot = QuinCheckRoot(voteOptionTreeDepth);

    component currentPerVOVotesRoot = QuinCheckRoot(voteOptionTreeDepth);
    // Compute the root of the spent voice credits per vote option
    component currentPerVOSpentVoiceCreditsRoot = QuinCheckRoot(voteOptionTreeDepth);

    for (var i = 0; i < numVoteOptions; i ++) {
        currentResultsRoot.leaves[i] <== currentResults[i];
        currentPerVOVotesRoot.leaves[i] <== currentPerVOVotes[i];
        currentPerVOSpentVoiceCreditsRoot.leaves[i] <== currentPerVOSpentVoiceCredits[i];
    }

    component currentResultsCommitment = HashLeftRight();
    currentResultsCommitment.left <== currentResultsRoot.root;
    currentResultsCommitment.right <== currentResultsRootSalt;

    component currentPerVOVotesCommitment = HashLeftRight();
    currentPerVOVotesCommitment.left <== currentPerVOVotesRoot.root;
    currentPerVOVotesCommitment.right <== currentPerVOVotesRootSalt;

    component currentPerVOSpentVoiceCreditsCommitment = HashLeftRight();
    currentPerVOSpentVoiceCreditsCommitment.left <== currentPerVOSpentVoiceCreditsRoot.root;
    currentPerVOSpentVoiceCreditsCommitment.right <== currentPerVOSpentVoiceCreditsRootSalt;

    // Commit to the current tally
    component currentTallyCommitmentHasher = Hasher3();
    currentTallyCommitmentHasher.in[0] <== currentResultsCommitment.hash;
    currentTallyCommitmentHasher.in[1] <== currentPerVOVotesCommitment.hash;
    currentTallyCommitmentHasher.in[2] <== currentPerVOSpentVoiceCreditsCommitment.hash;

    /*currentTallyCommitmentHasher.hash === currentTallyCommitment;*/
     // Check if the current tally commitment is correct only if this is not the first batch
     component iz = IsZero();
     iz.in <== isFirstBatch;
     // iz.out is 1 if this is not the first batch
     // iz.out is 0 if this is the first batch
 
     // hz is 0 if this is the first batch
     // currentTallyCommitment should be 0 if this is the first batch
 
     // hz is 1 if this is not the first batch
     // currentTallyCommitment should not be 0 if this is the first batch
     signal hz;
     hz <== iz.out * currentTallyCommitmentHasher.hash;
 
     hz === currentTallyCommitment;

    // Compute the root of the new results
    component newResultsRoot = QuinCheckRoot(voteOptionTreeDepth);

    component newPerVOVotesRoot = QuinCheckRoot(voteOptionTreeDepth);
    // Compute the root of the spent voice credits per vote option
    component newPerVOSpentVoiceCreditsRoot = QuinCheckRoot(voteOptionTreeDepth);

    for (var i = 0; i < numVoteOptions; i ++) {
        newResultsRoot.leaves[i] <== newResults[i];
        newPerVOVotesRoot.leaves[i] <== newPerVOVotes[i];
        newPerVOSpentVoiceCreditsRoot.leaves[i] <== newPerVOSpentVoiceCredits[i];
    }

    component newResultsCommitment = HashLeftRight();
    newResultsCommitment.left <== newResultsRoot.root;
    newResultsCommitment.right <== newResultsRootSalt;

    component newPerVOVotesCommitment = HashLeftRight();
    newPerVOVotesCommitment.left <== newPerVOVotesRoot.root;
    newPerVOVotesCommitment.right <== newPerVOVotesRootSalt;

    component newPerVOSpentVoiceCreditsCommitment = HashLeftRight();
    newPerVOSpentVoiceCreditsCommitment.left <== newPerVOSpentVoiceCreditsRoot.root;
    newPerVOSpentVoiceCreditsCommitment.right <== newPerVOSpentVoiceCreditsRootSalt;

    // Commit to the new tally
    component newTallyCommitmentHasher = Hasher3();
    newTallyCommitmentHasher.in[0] <== newResultsCommitment.hash;
    newTallyCommitmentHasher.in[1] <== newPerVOVotesCommitment.hash;
    newTallyCommitmentHasher.in[2] <== newPerVOSpentVoiceCreditsCommitment.hash;

    /*log(newResultsCommitment.hash);*/
    /*log(newSpentVoiceCreditsCommitment.hash);*/
    /*log(newPerVOSpentVoiceCreditsCommitment.hash);*/
    newTallyCommitmentHasher.hash === newTallyCommitment;
}

template TallyVotesInputHasher() {
    signal input stateCommitment;
    signal input currentTallyCommitment;
    signal input newTallyCommitment;
    signal input packedVals;

    signal output numSignUps;
    signal output batchNum;
    signal output hash;

    component unpack = UnpackElement(2);
    unpack.in <== packedVals;
    batchNum <== unpack.out[1];
    numSignUps <== unpack.out[0];

    component hasher = Sha256Hasher4();
    hasher.in[0] <== packedVals;
    hasher.in[1] <== stateCommitment;
    hasher.in[2] <== currentTallyCommitment;
    hasher.in[3] <== newTallyCommitment;

    hash <== hasher.hash;
}
