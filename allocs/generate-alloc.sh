# ./allocs/generate.sh $ARCHIVE_RPC_URL

rpc=$1
chainid=$(cast chain-id --rpc-url $rpc)

# set empty allocs
alloc="{}"

# parse the JSON at `addresses.json` and get an array of addresses
addresses=$(cat allocs/$chainid/addresses.json | jq -r '.[] | .contractAddress')
fromBlock=$(printf "%d\n" $(cat allocs/$chainid/blocks.json | jq -r 'sort | .[0]'))
toBlock=$(printf "%d\n" $(cat allocs/$chainid/blocks.json | jq -r 'sort | .[-1]'))

# loop through addresses,
for addr in $addresses; do
    # CODE
    # Get the code using `cast`
    code=$(cast code $addr --rpc-url $rpc --block $toBlock)
    # replace the value in the JSON with the queried code
    alloc=$(echo $alloc | jq --arg addy "$addr" --arg newCode "$code" '.alloc[$addy].code = $newCode')

    # STORAGE
    # Get the storage slots using heimdall
    echo "Dumping storage for $addr..."
    heimdall dump $addr --from-block $fromBlock --to-block $toBlock --rpc-url $rpc --output ./allocs/$chainid/$addr
    # parse the .csv output to json
    storage=$(awk -F, 'NR>1 {printf "\"%s\": \"%s\", ", $1, $2}' ./allocs/$chainid/$addr/dump.csv | sed 's/, $//')
    # replace the value in the JSON with the queried storage values
    alloc=$(echo $alloc | jq --arg addy "$addr" --argjson storage "{$storage}" '.alloc[$addy].storage = $storage')
    # remove the .csv files
    rm -rf ./allocs/$chainid/$addr/
done

touch ./allocs/$chainid/alloc.json
echo "$alloc" | jq '.' > ./allocs/$chainid/alloc.json
echo "Done - generated allocs written to ./allocs/$chainid/alloc.json!"