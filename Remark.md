# Data structure

## Trees

| tree name | degree | depth | capacity |
| - | - | - | - |
| message tree | 5 | 10 | 9,765,625 |
| state tree | 5 | 8 | 390,625 |
| vote option tree | 5 | 3 | 125 |

## Data

```
State: [
  publicKeyX
  publicKeyY
  voiceCreditBalance
  voteOptionTreeRoot
  nonce
]

Command: [
  packagedInfo: [
    salt
    newVoteWeight
    voteOptionIndex
    stateIndex
    nonce
  ]
  newPublicKeyX
  newPublicKeyY

  sigR8X
  sigR8Y
  sigS
]

Message: [
  ciphertext_0
  ciphertext_1
  ciphertext_2
  ciphertext_3
  ciphertext_4
  ciphertext_5
  ciphertext_6

  encPublicKeyX
  encPublicKeyY
]

```