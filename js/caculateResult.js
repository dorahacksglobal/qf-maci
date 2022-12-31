const fs = require('fs')
const path = require('path')

const MATCHING_POOL = 10000
const MAX_VOTES = 10n ** 24n

const rawdata = fs.readFileSync(path.join(__dirname, '../build/inputs/result.json'))
const result = JSON.parse(rawdata)

let totalArea = 0n
const output = []
for (let i = 0; i < result.length; i++) {
  const r = BigInt(result[i])
  const v = r / MAX_VOTES
  const v2 = r % MAX_VOTES
  const area = v * v - v2
  totalArea += area
  output.push({
    maciId: i,
    v: Number(v),
    area,
    matching: 0,
  })
}

for (const item of output) {
  item.matching = (MATCHING_POOL * Number(item.area) / Number(totalArea)).toFixed(2)
}

let csv = 'buidl_id, maci_id, votes, matcing\n'
csv += output.map((item) => [0, item.maciId + 1, item.v, item.matching].join(', ')).join('\n')

fs.writeFileSync(path.join(__dirname, '../build/inputs/result.csv'), csv)
