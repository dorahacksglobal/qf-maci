#!/bin/bash

# proof.sh msg/tally 0000

cd "$(dirname "$0")"
cd ../../build

if [ ! -d "wtns" ]; then
  mkdir wtns
fi

if [ ! -d "outputs" ]; then
  mkdir outputs
fi

wtns="./wtns/${1}_${2}.wtns"

node "./${1}_js/generate_witness.js" "./${1}_js/${1}.wasm" "./inputs/${1}-input_${2}.json" $wtns

snarkjs g16p "./zkey/${1}_1.zkey" $wtns "./outputs/${1}_${2}.json" __temp-public.json
