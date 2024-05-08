set -e
cp .env-garnet .env
cp .env-garnet contracts/.env

source .env

ROOT=$(pwd)

if [ "$DEPLOY_DS" = "true" ]
then
    cd $ROOT/downstream
    sed "/^const NETWORK.*/c\\
    const NETWORK = \"$DS_NETWORK\";" base.js > base-deploy.js
    ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n $DS_NETWORK apply -R -f .
fi

cd $ROOT/contracts

# --gas-price 0.00010005
forge script --rpc-url $RPC_URL --slow --broadcast -vvv script/InitTurfWars.s.sol
# forge script --rpc-url $RPC_URL -vvv script/InitTurfWars.s.sol