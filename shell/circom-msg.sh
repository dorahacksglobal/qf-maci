#!/bin/bash

start=`date +%s`

circom circuits/prod/msg.circom --r1cs ---wasm -o build

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`
echo "Spend time: $time seconds"
