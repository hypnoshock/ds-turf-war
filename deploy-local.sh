set -e
cp .env-local .env
cp .env-local contracts/.env

source .env

# Setting to true will upgrade the TurfWars contract
export UPGRADE_TW="${UPGRADE_TW:=false}"

ROOT=$(pwd)

rm -rf $ROOT/contracts/deployments/deploy-local.json

if [ "$DEPLOY_DS" = "true" ]
then
    cd $ROOT/downstream
    sed "/^const NETWORK.*/c\\
    const NETWORK = \"$DS_NETWORK\";" base.js > base-deploy.js
    ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .
fi

cd $ROOT/contracts
forge script --rpc-url $RPC_URL --broadcast -vvv script/InitTurfWars.s.sol