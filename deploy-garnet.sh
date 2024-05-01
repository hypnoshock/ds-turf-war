set -e
cp .env-garnet .env
cp .env-garnet contracts/.env

source .env

ROOT=$(pwd)

cd $ROOT/downstream
ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .

cd $ROOT/contracts
# forge script --rpc-url $RPC_URL --broadcast -vvv script/InitTurfWars.s.sol

forge script --rpc-url $RPC_URL -vvv script/InitTurfWars.s.sol