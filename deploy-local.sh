set -e
cp .env-local .env
cp .env-local contracts/.env

source .env

ROOT=$(pwd)

# cd $ROOT/downstream
# ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .

cd $ROOT/contracts
forge script --rpc-url $RPC_URL --broadcast -vvv script/InitTurfWars.s.sol