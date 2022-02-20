#!/bin/bash

start=`date +%s`

# need enter a random text
snarkjs zkc build/zkey/msg_0.zkey build/zkey/msg_1.zkey --name="DoraHacks" -v

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`

echo -e "\nMsg zkey contribute"
echo "Spend time: $time seconds"

snarkjs zkev build/zkey/msg_1.zkey build/msg_verification_key.json

echo -e "\nExport successfully"

exec /bin/bash
