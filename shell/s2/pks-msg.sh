#!/bin/bash

if [ ! -d "build/zkey" ]; then
  mkdir build/zkey
fi

export NODE_OPTIONS=--max-old-space-size=8192

start=`date +%s`

snarkjs pks build/msg.r1cs ptau/powersOfTau28_hez_final_22.ptau build/zkey/msg_p.zkey

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`

echo -e "\nMsg groth16 setup"
echo "Spend time: $time seconds"

exec /bin/bash
