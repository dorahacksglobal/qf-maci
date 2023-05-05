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

snarkjs pkf "./inputs/${1}-input_${2}.json" "./${1}_js/${1}.wasm" "./zkey/${1}_p.zkey" $wtns "./outputs/${1}_${2}.json" __temp-public.json
