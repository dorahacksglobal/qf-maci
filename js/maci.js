const { eddsa, poseidon, poseidonDecrypt } = require('circom')
const { utils } = require('ethers')
const { stringizing, genKeypair, genEcdhSharedKey } = require('./keypair')
const Tree = require('./tree')

const SNARK_FIELD_SIZE = 21888242871839275222246405745257275088548364400416034343698204186575808495617n
const UINT96 = 2n ** 96n
const UINT32 = 2n ** 32n

const MACI_STATES = {
  FILLING: 0,           // sign up & publish message
  PROCESSING: 1,        // batch process message
  TALLYING: 2,          // tally votes
  ENDED: 3,             // ended
}

class MACI {
  constructor(
    stateTreeDepth,
    voteOptionTreeDepth,
    batchSize,
    coordPriKey,
    maxVoteOptions,
    numSignUps,
  ) {
    this.stateTreeDepth = stateTreeDepth
    this.voteOptionTreeDepth = voteOptionTreeDepth
    this.batchSize = batchSize
    this.maxVoteOptions = maxVoteOptions
    this.numSignUps = numSignUps

    this.coordinator = genKeypair(coordPriKey)
    this.pubKeyHasher = poseidon(this.coordinator.pubKey)

    const emptyVOTree = new Tree(5, voteOptionTreeDepth, 0n)
    const blankStateHash = poseidon([0, 0, 0, 0, 0])

    const stateTree = new Tree(5, stateTreeDepth, blankStateHash)

    console.log([
      '',
      'init MACI '.padEnd(40, '='),
      '- vo tree root:\t\t' + emptyVOTree.root,
      '- state tree root:\t' + stateTree.root,
      '',
    ].join('\n'))

    this.voTreeZeroRoot = emptyVOTree.root
    this.stateTree = stateTree

    this.stateLeaves = new Map()
    this.commands = []
    this.messages = []
    this.states = MACI_STATES.FILLING
    this.logs = []
  }

  emptyMessage() {
    return {
      ciphertext: [0n, 0n, 0n, 0n, 0n, 0n, 0n],
      encPubKey: [0n, 0n],
      prevHash: 0n,
      hash: 0n,
    }
  }

  emptyState() {
    return {
      pubKey: [0n, 0n],
      balance: 0n,
      voTree: new Tree(5, this.voteOptionTreeDepth, 0n),
      nonce: 0n,
      voted: false,
    }
  }

  initStateTree(leafIdx, pubKey, balance) {
    if (this.states !== MACI_STATES.FILLING) throw new Error('vote period ended')

    const stateTreeRoot = this.stateTree.root
  
    const s = this.stateLeaves.get(leafIdx) || this.emptyState()
    s.pubKey = [...pubKey]
    s.balance = BigInt(balance)

    this.stateLeaves.set(leafIdx, s)

    const hash = poseidon([
      ...s.pubKey,
      s.balance,
      s.voted ? s.voTree.root : 0n,
      s.nonce
    ])
    this.stateTree.updateLeaf(leafIdx, hash)

    console.log([
      `set State { idx: ${leafIdx} } `.padEnd(40, '='),
      '- leaf hash:\t\t' + hash,
      '- new tree root:\t' + this.stateTree.root,
      '',
    ].join('\n'))
    this.logs.push({
      type: 'setStateLeaf',
      data: stringizing(arguments)
    })
  }

  pushMessage(ciphertext, encPubKey) {
    if (this.states !== MACI_STATES.FILLING) throw new Error('vote period ended')

    const msgIdx = this.messages.length
    const prevHash = msgIdx > 0 ?
      this.messages[msgIdx - 1].hash :
      0n
    
    const hash = poseidon([
      poseidon(ciphertext.slice(0, 5)),
      poseidon([...ciphertext.slice(5), ...encPubKey, prevHash])
    ])

    this.messages.push({
      ciphertext: [...ciphertext],
      encPubKey: [...encPubKey],
      prevHash,
      hash,
    })

    const sharedKey = genEcdhSharedKey(this.coordinator.privKey, encPubKey)
    try {
      const plaintext = poseidonDecrypt(ciphertext, sharedKey, 0n, 6)
      const packaged = plaintext[0]

      const nonce = packaged % UINT32
      const stateIdx = (packaged >> 32n) % UINT32
      const voIdx = (packaged >> 64n) % UINT32
      const newVotes = (packaged >> 96n) % UINT96

      const cmd = {
        nonce, stateIdx, voIdx, newVotes,
        newPubKey: [plaintext[1], plaintext[2]],
        signature: {
          R8: [plaintext[3], plaintext[4]],
          S: plaintext[5],
        },
        msgHash: poseidon(plaintext.slice(0, 3))
      }
      this.commands.push(cmd)
    } catch (e) {
      // !discard
      this.commands.push(null)
      console.log('[dev] msg decrypt error')
    }

    console.log([
      `push Message { idx: ${msgIdx} } `.padEnd(40, '='),
      '- old msg hash:\t' + prevHash,
      '- new msg hash:\t' + hash,
      '',
    ].join('\n'))
    this.logs.push({
      type: 'publishMessage',
      data: stringizing(arguments)
    })
  }

  endVotePeriod() {
    if (this.states !== MACI_STATES.FILLING) throw new Error('vote period ended')
    this.states = MACI_STATES.PROCESSING

    this.msgEndIdx = this.messages.length
    this.stateSalt = 0n
    this.stateCommitment = poseidon([this.stateTree.root, 0n])

    console.log([
      'Vote End '.padEnd(60, '='),
      '',
    ].join('\n'))
  }

  checkCommandNow(cmd) {
    if (!cmd) {
      return 'empty command'
    }
    if (cmd.stateIdx > BigInt(this.numSignUps)) {
      return 'state leaf index overflow'
    }
    if (cmd.voIdx > BigInt(this.maxVoteOptions)) {
      return 'vote option index overflow'
    }
    const stateIdx = Number(cmd.stateIdx)
    const voIdx = Number(cmd.voIdx)
    const s = this.stateLeaves.get(stateIdx) || this.emptyState()

    if (s.nonce + 1n !== cmd.nonce) {
      return 'nonce error'
    }
    const verified = eddsa.verifyPoseidon(cmd.msgHash, cmd.signature, s.pubKey)
    if (!verified) {
      return 'signature error'
    }
    const currVotes = s.voTree.leaf(voIdx)
    if (s.balance + currVotes * currVotes < cmd.newVotes * cmd.newVotes) {
      return 'insufficient balance'
    }
  }

  processMessage(newStateSalt = 0n) {
    if (this.states !== MACI_STATES.PROCESSING) throw new Error('period error')

    const batchSize = this.batchSize
    const batchStartIdx = Math.floor((this.msgEndIdx - 1) / batchSize) * batchSize
    const batchEndIdx = Math.min(batchStartIdx + batchSize, this.msgEndIdx)
  
    console.log(`Process message [${batchStartIdx}, ${batchEndIdx})`.padEnd(40, '='))

    const messages = this.messages.slice(batchStartIdx, batchEndIdx)
    const commands = this.commands.slice(batchStartIdx, batchEndIdx)

    while (messages.length < batchSize) {
      messages.push(this.emptyMessage())
      commands.push(null)
    }

    const currentStateRoot = this.stateTree.root

    // PROCESS ================================================================
    const currentStateLeaves = new Array(batchSize)
    const currentStateLeavesPathElements = new Array(batchSize)
    const currentVoteWeights = new Array(batchSize)
    const currentVoteWeightsPathElements = new Array(batchSize)
    for (let i = batchSize - 1; i >= 0; i--) {
      const cmd = commands[i]
      const error = this.checkCommandNow(cmd)

      let stateIdx = 0
      let voIdx = 0
      if (!error) {
        stateIdx = Number(cmd.stateIdx)
        voIdx = Number(cmd.voIdx)
      }

      const s = this.stateLeaves.get(stateIdx) || this.emptyState()
      const currVotes = s.voTree.leaf(voIdx)
      currentStateLeaves[i] = [
        ...s.pubKey,
        s.balance,
        s.voted ? s.voTree.root : 0n,
        s.nonce
      ]
      currentStateLeavesPathElements[i] = this.stateTree.pathElementOf(stateIdx)
      currentVoteWeights[i] = currVotes
      currentVoteWeightsPathElements[i] = s.voTree.pathElementOf(voIdx)

      if (!error) {
        // UPDATE STATE =======================================================
        s.pubKey = [...cmd.newPubKey]
        s.balance = s.balance + currVotes * currVotes - cmd.newVotes * cmd.newVotes
        s.voTree.updateLeaf(voIdx, cmd.newVotes)
        s.nonce = cmd.nonce
        s.voted = true

        this.stateLeaves.set(stateIdx, s)

        const hash = poseidon([...s.pubKey, s.balance, s.voTree.root, s.nonce])
        this.stateTree.updateLeaf(stateIdx, hash)
      }

      console.log(`- message <${i}> ${error || '√'}`)
    }

    const newStateRoot = this.stateTree.root
    const newStateCommitment = poseidon([newStateRoot, newStateSalt])

    // GEN INPUT JSON =========================================================
    const packedVals =
      BigInt(this.maxVoteOptions) +
      (BigInt(this.numSignUps) << 32n)
    const batchStartHash = this.messages[batchStartIdx].prevHash
    const batchEndHash = this.messages[batchEndIdx - 1].hash

    const inputHash = BigInt(utils.soliditySha256(
      new Array(6).fill('uint256'),
      stringizing([
        packedVals,
        this.pubKeyHasher,
        batchStartHash,
        batchEndHash,
        this.stateCommitment,
        newStateCommitment
      ])
    )) % SNARK_FIELD_SIZE

    const msgs = messages.map(msg => msg.ciphertext)
    const encPubKeys = messages.map(msg => msg.encPubKey)
    const input = {
      inputHash,
      packedVals,
      batchStartHash,
      batchEndHash,
      msgs,
      coordPrivKey: this.coordinator.formatedPrivKey,
      coordPubKey: this.coordinator.pubKey,
      encPubKeys,
      currentStateRoot,
      currentStateLeaves,
      currentStateLeavesPathElements,
      currentStateCommitment: this.stateCommitment,
      currentStateSalt: this.stateSalt,
      newStateCommitment,
      newStateSalt,
      currentVoteWeights,
      currentVoteWeightsPathElements,
    }

    this.msgEndIdx = batchStartIdx
    this.stateCommitment = newStateCommitment
    this.stateSalt = newStateSalt

    console.log([
      '',
      '* new state root:\n\n' + newStateRoot,
      '',
    ].join('\n'))

    if (batchStartIdx === 0) {
      this.states = MACI_STATES.TALLYING
      console.log([
        'Process Finished '.padEnd(60, '='),
        '',
      ].join('\n'))
    }

    return input
  }
}

module.exports = MACI