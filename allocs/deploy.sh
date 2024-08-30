# ./allocs/deploy.sh $RPC_URL $PRIVATE_KEY
# NOTE: before running, setup the forge scripts that will run at `allocs/deploy-scripts.json`

rpc=$1
privateKey=$2

# parse array of script commands `allocs/deploy-scripts.json``
scripts=$(cat allocs/deploy-scripts.json | jq -c '.[]')

echo "$scripts" | while IFS= read -r script; do
    # pull the script vars
    relativePath=$(echo "$script" | jq -r '.relativePath')
    deployFilePath=$(echo "$script" | jq -r '.deployFilePath')
    deployFile=$(echo "$script" | jq -r '.deployFile')
    deployContract=$(echo "$script" | jq -r '.deployContract')
    deploySignature=$(echo "$script" | jq -r '.deploySignature')

    # cd to a new repo if necessary
    cd $relativePath

    # run the deploy script
    forge script $deployFilePath/${deployFile}:${deployContract} --sig $deploySignature --rpc-url $rpc --private-key $privateKey --broadcast
done

# write the addresses 
./allocs/write-output.sh $rpc