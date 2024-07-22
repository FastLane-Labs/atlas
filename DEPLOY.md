# Deploying Atlas

This is a guide to getting the Atlas smart contracts deployed on an EVM chain.

## Atlas Deployment Process

1. Check that the contracts compile and all tests pass.

```bash
forge test
```

2. Set up your `.env` file with the variables relevant to the chain to which you are trying to deploy. Note: the `GOV_PRIVATE_KEY` is the private key to the public address from which the contracts will be deployed. You must also set the `DEPLOY_TO` variable to a valid chain option: `SEPOLIA`, `MAINNET`, `AMOY`, `POLYGON`, or `LOCAL`. In this example we would be deploying to Polygon mainnet.

```bash
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/XXXXXXXXXXXXXXXXXXXX
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/XXXXXXXXXXXXXXXXXXXX
AMOY_RPC_URL=https://polygon-amoy.g.alchemy.com/v2/XXXXXXXXXXXXXXXXXXXX
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/XXXXXXXXXXXXXXXXXXXX
ETHERSCAN_API_KEY=XXXXXXXXXXXXXXXXXXXX
POLYGONSCAN_API_KEY=XXXXXXXXXXXXXXXXXXXX

GOV_PRIVATE_KEY=0x123456789...

DEPLOY_TO=POLYGON
```

3. Run the deployment script in simulation mode to verify everything works. Note: exclude the `--broadcast` flag to run the script in simulation mode. See Foundry's [script command options](https://book.getfoundry.sh/reference/cli/forge/script).

```bash
source .env && forge script script/deploy-atlas.s.sol:DeployAtlasScript --rpc-url ${POLYGON_RPC_URL} --legacy
```

4. Run the deployment script again, this time in broadcast mode to actually send the transactions to deploy the contracts. Note: include the `--broadcast` flag to run the script in broadcast mode. We also include `--etherscan-api-key ${POLYGONSCAN_API_KEY} --verify` to verify the contracts on Polygonscan.

```bash
source .env && forge script script/deploy-atlas.s.sol:DeployAtlasScript --rpc-url ${POLYGON_RPC_URL} --legacy --broadcast --etherscan-api-key ${POLYGONSCAN_API_KEY} --verify
```

If all goes well, the script will output the addresses of the deployed contracts, and handle verification through Etherscan or Polygonscan automatically. These addresses will also be saved in the `deployments.json` file.

## DAppControl Deployment Process

Coming soon...