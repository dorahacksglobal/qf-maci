#!/bin/bash

start=`date +%s`

# need enter a random text
snarkjs zkc build/zkey/tally_0.zkey build/zkey/tally_1.zkey --name="DoraHacks" -v

end=`date +%s`

time=`echo $start $end | awk '{print $2-$1}'`

echo -e "\nTally zkey contribute"
echo "Spend time: $time seconds"

snarkjs zkev build/zkey/tally_1.zkey build/tally_verification_key.json

echo -e "\nExport successfully"

exec /bin/bash
