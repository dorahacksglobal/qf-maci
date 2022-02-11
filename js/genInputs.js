const fs = require('fs')
const path = require('path')
const { stringizing } = require('./keypair')
const MACI = require('./maci')

const logsPath = process.argv[2]
const outputPath = process.argv[3]
if (!outputPath) {
  console.log('no output directory is specified')
  process.exit(1)
}

// * DEV *
const main = new MACI(
  7, 3, 3, 125,               // tree config
  10323336771310894148508984336434564969715880830427060157568539544440860700904n,                   // coordinator
  6,
  30
)

function toBigInt(list) {
  return list.map(n => BigInt(n))
}

const rawdata = fs.readFileSync(logsPath)
const logs = JSON.parse(rawdata)

for (const state of logs.states) {
  main.initStateTree(Number(state.idx), toBigInt(state.pubkey), state.balance)
}

for (const msg of logs.messages) {
  main.pushMessage(toBigInt(msg.msg), toBigInt(msg.pubkey))
}

main.endVotePeriod()

const commitments = {}

// PROCESSING
let i = 0
while (main.states === 1) {
  const input = main.processMessage(1234567890n)
  commitments['msg_' + i.toString().padStart(4, '0')] = main.stateCommitment

  fs.writeFileSync(
    path.join(outputPath, `msg-input_${i.toString().padStart(4, '0')}.json`),
    JSON.stringify(stringizing(input), undefined, 2)
  )
  i++
}

// TALLYING
i = 0
while (main.states === 2) {
  const input = main.processTally(1234567890n)
  commitments['tally_' + i.toString().padStart(4, '0')] = main.tallyCommitment

  fs.writeFileSync(
    path.join(outputPath, `tally-input_${i.toString().padStart(4, '0')}.json`),
    JSON.stringify(stringizing(input), undefined, 2)
  )
  i++
}

fs.writeFileSync(
  path.join(outputPath, 'result.json'),
  JSON.stringify(stringizing(main.tallyResults.leaves()), undefined, 2)
)

fs.writeFileSync(
  path.join(outputPath, 'commitments.json'),
  JSON.stringify(stringizing(commitments), undefined, 2)
)
