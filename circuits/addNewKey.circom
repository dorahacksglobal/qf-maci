pragma circom 2.0.0;

include "./hasherSha256.circom";
include "./hasherPoseidon.circom";
include "./ecdh.circom";
include "./trees/incrementalQuinTree.circom";
include "../node_modules/circomlib/circuits/mux1.circom";

/*
 * Proves the correctness of processing a batch of messages.
 */
template AddNewKey(
    stateTreeDepth
) {
    // stateTreeDepth: the depth of the state tree

    assert(stateTreeDepth > 0);

    var TREE_ARITY = 5;

    signal input inputHash;

    // The cooordinator's public key from the contract.
    signal input coordPubKey[2];

    signal input deactivateRoot;

    signal input deactivateIndex;

    signal input deactivateLeaf;

    signal input deactivateLeafPathElements[stateTreeDepth][TREE_ARITY - 1];

    signal input nullifier;

    signal input oldPrivateKey;

    // 1.
    component nullifierHasher = HashLeftRight(); 
    nullifierHasher.left <== oldPrivateKey;
    nullifierHasher.right <== 1444992409218394441042; // 'NULLIFIER'
    nullifierHasher.hash === nullifier;

    // 2.
    component ecdh = Ecdh();
    ecdh.privKey <== oldPrivateKey;
    ecdh.pubKey[0] <== coordPubKey[0];
    ecdh.pubKey[1] <== coordPubKey[1];

    component deactivateLeafHasher = HashLeftRight();
    deactivateLeafHasher.left <== ecdh.sharedKey[0];
    deactivateLeafHasher.right <== ecdh.sharedKey[1];

    deactivateLeafHasher.hash === deactivateLeaf;

    // 3.
    component deactivateLeafPathIndices = QuinGeneratePathIndices(stateTreeDepth);
    deactivateLeafPathIndices.in <== deactivateIndex;

    component deactivateQie = QuinLeafExists(stateTreeDepth);
    deactivateQie.leaf <== deactivateLeaf;
    deactivateQie.root <== deactivateRoot;
    for (var i = 0; i < stateTreeDepth; i ++) {
        deactivateQie.path_index[i] <== deactivateLeafPathIndices.out[i];
        for (var j = 0; j < TREE_ARITY - 1; j++) {
            deactivateQie.path_elements[i][j] <== deactivateLeafPathElements[i][j];
        }
    }

    // Verify "public" inputs and assign unpacked values
    component inputHasher = AddNewKeyInputHasher();
    inputHasher.deactivateRoot <== deactivateRoot;
    inputHasher.coordPubKey[0] <== coordPubKey[0];
    inputHasher.coordPubKey[1] <== coordPubKey[1];
    inputHasher.nullifier <== nullifier;

    inputHasher.hash === inputHash;
}


template AddNewKeyInputHasher() {
    signal input deactivateRoot;
    signal input coordPubKey[2];
    signal input nullifier;

    signal output hash;

    // 1. Hash coordPubKey
    component pubKeyHasher = HashLeftRight();
    pubKeyHasher.left <== coordPubKey[0];
    pubKeyHasher.right <== coordPubKey[1];

    // 2. Hash the 3 inputs with SHA256
    component hasher = Sha256Hasher(3);
    hasher.in[0] <== deactivateRoot;
    hasher.in[1] <== pubKeyHasher.hash;
    hasher.in[2] <== nullifier;

    hash <== hasher.hash;
}
