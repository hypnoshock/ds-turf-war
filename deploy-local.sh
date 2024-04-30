set -e
source .env

cd downstream
ds -z $DS_ZONE -k $DS_DEPLOY_KEY -n local apply -R -f .

cd ../contracts
forge script --rpc-url http://localhost:8545 --broadcast -vvv script/InitTurfWars.s.sol