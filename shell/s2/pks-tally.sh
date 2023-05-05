#!/bin/bash

if [ ! -d "build/zkey" ]; then
  mkdir build/zkey
fi

export NODE_OPTIONS=--max-old-space-size=8192

start=`date +%s`

snarkjs pks build/tally.r1cs ptau/powersOfTau28_hez_final_22.ptau build/zkey/tally_p.zkey

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`

echo -e "\nTally groth16 setup"
echo "Spend time: $time seconds"

exec /bin/bash
