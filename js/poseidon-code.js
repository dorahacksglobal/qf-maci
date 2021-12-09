const poseidonGenContract = require('circom/src/poseidon_gencontract.js')

if (process.argv.length != 3) {
  console.log("Usage: node poseidon_gencontract.js [numberOfInputs]")
  process.exit(1)
}

const nInputs = Number(process.argv[2])

console.log(nInputs)

console.log(poseidonGenContract.createCode(nInputs))

// local ganache deployed
// PoseidonT3: 0x0049aace27f85e898b1e3cbc31c5b8c00a1c1182
// PoseidonT6: 0x6f616794e9c4fdd27b6a9a74fd16348ac4884095
