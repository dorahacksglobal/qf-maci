#!/bin/bash

if [ ! -d "build" ]; then
  mkdir build
fi

start=`date +%s`

circom circuits/prod/addKey.circom --r1cs ---wasm -o build

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`

echo -e "\nCompile msg.circom"
echo "spend time: $time seconds"

exec /bin/bash
