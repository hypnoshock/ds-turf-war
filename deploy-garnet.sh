set -e
cp .env-garnet .env
cp .env-garnet contracts/.env

source .env

# Setting to true will upgrade the TurfWars contract
export UPGRADE_TW="${UPGRADE_TW:=false}"

ROOT=$(pwd)

if [ "$DEPLOY_DS" = "true" ]
then
    cd $ROOT/downstream
    sed "/^const NETWORK.*/c\\
    const NETWORK = \"$DS_NETWORK\";" base.js > base-deploy.js
    ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .
fi

cd $ROOT/contracts

# 0.00010006(gwei) == 100060(wei)
if [ "$BROADCAST" = "true" ]
then
    forge script --rpc-url $RPC_URL --with-gas-price 100060 --slow --broadcast -vvv script/InitTurfWars.s.sol
else
    forge script --rpc-url $RPC_URL --with-gas-price 100060 --slow -vvv script/InitTurfWars.s.sol
fi
