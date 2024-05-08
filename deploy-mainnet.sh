set -e
cp .env-mainnet .env
cp .env-mainnet contracts/.env

source .env

ROOT=$(pwd)

# cd $ROOT/downstream
# ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .

cd $ROOT/contracts

forge script --rpc-url $RPC_URL --slow --broadcast -vvv script/InitTurfWars.s.sol
# forge script --rpc-url $RPC_URL -vvv script/InitTurfWars.s.sol