set -e
cp .env-local .env
cp .env-local contracts/.env

source .env

cd downstream
ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .

cd ../contracts
forge script --rpc-url $RPC_LOCAL --broadcast -vvv script/InitTurfWars.s.sol