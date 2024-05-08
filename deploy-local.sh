set -e
cp .env-local .env
cp .env-local contracts/.env

source .env

ROOT=$(pwd)

rm -rf $ROOT/deployments/deploy-local.json

if [ "$DEPLOY_DS" = "true" ]
then
    cd $ROOT/downstream
    ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .
fi

cd $ROOT/contracts
forge script --rpc-url $RPC_URL --broadcast -vvv script/InitTurfWars.s.sol