// node genProof.js [msg_proof_count] [tally_proof_count]

const util = require('util')
const path = require('path')
const fs = require('fs')
const child_process = require('child_process')

const exec = util.promisify(child_process.exec)

const msgBatchSize = Number(process.argv[2])
const tallyBatchSize = Number(process.argv[3])
if (!msgBatchSize || !tallyBatchSize) {
  console.log('no proof count specified')
  process.exit(1)
}

function getProof(type, idx) {
  const rawdata = fs.readFileSync(path.join(__dirname, `../../build/outputs/${type}_${idx}.json`))
  const data = JSON.parse(rawdata)

  const output = []

  output.push(...data.pi_a.slice(0, 2))

  output.push(...data.pi_b[0].reverse())
  output.push(...data.pi_b[1].reverse())

  output.push(...data.pi_c.slice(0, 2))

  return output
}

const commitments = (() => {
  const rawdata = fs.readFileSync(path.join(__dirname, '../../build/inputs/commitments.json'))
  const data = JSON.parse(rawdata)
  return data
})()

// run('msg/tally', 0)
async function run(type, id) {
  console.time('Time used')

  const idx = id.toString().padStart(4, '0')
  await exec(`./proof.sh ${type} ${idx}`, { cwd: __dirname })

  const proof = getProof(type, idx)
  const commitment = commitments[`${type}_${idx}`]

  console.log(type, id)
  console.log(proof, commitment)
  console.timeEnd('Time used')
  console.log()
}

async function main() {
  for (let i = 0; i < msgBatchSize; i++) {
    await run('msg', i)
  }
  for (let i = 0; i < tallyBatchSize; i++) {
    await run('tally', i)
  }
}

main()
