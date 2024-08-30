# ./allocs/check-alloc.sh $RPC_URL

rpc=$1
chainid=$(cast chain-id --rpc-url $rpc)

# Pull the current alloc JSON 
contents=$(cat allocs/$chainid/alloc.json)

# Get all addresses JSON
addrs=$(echo $contents | jq -r '.alloc | keys[]')

# For each contract,
for addr in $addrs; do
    # Get the code using `cast`
    code=$(cast code $addr --rpc-url $rpc)
    # replace the value in the JSON with the queried code
    contents=$(echo $contents | jq --arg addy "$addr" --arg newCode "$code" '.alloc[$addy].code = $newCode')
    
    # Get the storage slots in the JSON
    slots=$(echo $contents | jq -r --arg addy "$addr" '.alloc[$addy].storage | select(. != null) | keys[]')
    for slot in $slots; do
        # Get the storage value using `cast`
        value=$(cast storage $addr $slot --rpc-url $rpc)
        # replace the value in the JSON with the queried storage value
        contents=$(echo $contents | jq --arg addy "$addr" --arg slot "$slot" --arg newValue "$value" '.alloc[$addy].storage[$slot] = $newValue')
    done
done

echo "$contents" > ./allocs/$chainid/alloc.json
echo "Done - allocs re-written to alloc.json!"