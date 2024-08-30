# ./allocs/write-addresses.sh $RPC_URL
# NOTE: before running, setup the forge scripts to inspect outputs from at `allocs/deploy-scripts.json`

rpc=$1
chainid=$(cast chain-id --rpc-url $rpc)

contracts="[]"
blocks="[]"

workingdir=$(pwd)
mkdir -p ./allocs/$chainid

# parse array of script commands `allocs/deploy-scripts.json``
scripts=$(cat allocs/deploy-scripts.json | jq -c '.[]')

echo "$scripts" | while IFS= read -r script; do
    # pull the script vars
    relativePath=$(echo "$script" | jq -r '.relativePath')
    deployFile=$(echo "$script" | jq -r '.deployFile')
    deployContract=$(echo "$script" | jq -r '.deployContract')
    deploySignature=$(echo "$script" | jq -r '.deploySignature')

    # cd to the script repo
    cd $relativePath
    
    # get contracts deployed via CREATE or CREATE2
    newContracts=$(cat broadcast/${deployFile}/${chainid}/${deploySignature}-latest.json | jq '[.transactions[] | select(.transactionType == ("CREATE", "CREATE2")) | {contractName, contractAddress}]')
    # get contracts deployed in sub-calls
    additionalContracts=$(cat broadcast/${deployFile}/${chainid}/${deploySignature}-latest.json | jq '[.transactions[].additionalContracts[] | {contractAddress: .address}]')
    # append all new contracts to the running total
    contracts=$(echo "$contracts" "$newContracts" "$additionalContracts" | jq -s '.[0] + .[1] + .[2]')
    # write addresses to file
    echo "$contracts" > $workingdir/allocs/$chainid/addresses.json

    # get blocks 
    newBlocks=$(cat broadcast/${deployFile}/${chainid}/${deploySignature}-latest.json | jq '[.receipts[].blockNumber]')
    # append new blocks to the running total
    blocks=$(echo "$blocks" "$newBlocks" | jq -s '.[0] + .[1] | sort | unique')
    # write blocks to file
    echo "$blocks" > $workingdir/allocs/$chainid/blocks.json
done

echo "Done! Outputs written to ./allocs/$chainid/"