const fs = require('fs')
const path = require('path')
const { stringizing, genKeypair, genEcdhSharedKey } = require('./keypair')
const MACI = require('./maci')
const { genMessage } = require('./client')

const outputPath = process.argv[2]
if (!outputPath) {
  console.log('no output directory is specified')
  process.exit(1)
}

const USER_IDX = 1        // state leaf idx

const privateKeys = [
  111111n, // coordinator
  222222n, // user 1
  333333n, // share key for message 1
  444444n, // share key for message 2
  555555n,
  666666n,
]
const coordinator = genKeypair(privateKeys[0])
const user1 = genKeypair(privateKeys[1])

const main = new MACI(
  4, 2, 4,               // tree config
  privateKeys[0],         // coordinator
  20,
  5
)

main.initStateTree(USER_IDX, user1.pubKey, 100)

const enc1 = genKeypair(privateKeys[2])
const message1 = genMessage(enc1.privKey, coordinator.pubKey)(
  USER_IDX, 1, 12, 10, user1.pubKey, user1.privKey, 1234567890n
)
main.pushMessage(message1, enc1.pubKey)

console.log(message1, enc1.pubKey)

const enc2 = genKeypair(privateKeys[3])
const message2 = genMessage(enc2.privKey, coordinator.pubKey)(
  USER_IDX, 1, 8, 10, user1.pubKey, user1.privKey, 9876543210n
)
main.pushMessage(message2, enc2.pubKey)

main.endVotePeriod()

while (main.msgEndIdx > 0) {
  let i = 0
  const input = main.processMessage(1234567890n)

  fs.writeFileSync(
    path.join(outputPath, `input_${i.toString().padStart(4, '0')}.json`),
    JSON.stringify(stringizing(input), undefined, 2)
  )
}
