# Deploying Atlas

This is a guide to getting the Atlas smart contracts deployed on an EVM chain.

## Atlas Deployment Process

1. Checkout to [this commit hash](https://github.com/FastLane-Labs/atlas/commit/dca0b9946e8f59347610cd24a0bca5e84ddea00e) on the `main` branch. This was the commit hash represents the state of the codebase at the time that the Spearbit audit was finalized.

```bash
git checkout dca0b9946e8f59347610cd24a0bca5e84ddea00e
```

2. Set up your `.env` file with the variables relevant to the chain to which you are trying to deploy. Note: the `GOV_PRIVATE_KEY` is the private key to the public address from which the contracts will be deployed. You must also set the `DEPLOY_TO` variable to a valid chain option: `SEPOLIA`, `MAINNET`, `AMOY`, `POLYGON`, or `LOCAL`. In this example we would be deploying to Polygon mainnet. Check out the [Wallet List docs](https://github.com/FastLane-Labs/knowledge-base/blob/main/playbooks/wallets/wallet_list.md) if in doubt about which address to deploy from.

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

## Latest Deployments


### Polygon Amoy Testnet

Commit hash of deployment: [dca0b99](https://github.com/FastLane-Labs/atlas/commit/dca0b9946e8f59347610cd24a0bca5e84ddea00e)

| Contract           | Address                                                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Atlas              | [0x282BdDFF5e58793AcAb65438b257Dbd15A8745C9](https://amoy.polygonscan.com/address/0x282BdDFF5e58793AcAb65438b257Dbd15A8745C9) |
| AtlasVerification  | [0x3b7B38362bB7E2F000Cd2432343F3483F785F435](https://amoy.polygonscan.com/address/0x3b7B38362bB7E2F000Cd2432343F3483F785F435) |
| Simulator          | [0x3efbaBE0ee916A4677D281c417E895a3e7411Ac2](https://amoy.polygonscan.com/address/0x3efbaBE0ee916A4677D281c417E895a3e7411Ac2) |
| Sorter             | [0xa55051bd82eFeA1dD487875C84fE9c016859659B](https://amoy.polygonscan.com/address/0xa55051bd82eFeA1dD487875C84fE9c016859659B) |

| DAppControl        | Address                                                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| FastLane Online    | [0xf0E388C7DFfE14a61280a4E5b84d77be3d2875e3](https://amoy.polygonscan.com/address/0xf0E388C7DFfE14a61280a4E5b84d77be3d2875e3) |


### Polygon Mainnet

Commit hash of deployment: [7b8530f](https://github.com/FastLane-Labs/atlas/pull/398/commits/7b8530f55b1719cf51a582ba04fea39085a4c20c)

| Contract           | Address                                                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Atlas              | [0x20eA1943264FED9471f4E9430C935986A60905E3](https://polygonscan.com/address/0x20eA1943264FED9471f4E9430C935986A60905E3)      |
| AtlasVerification  | [0xd72A38636d88B7F7326340add69a1A494E74c913](https://polygonscan.com/address/0xd72A38636d88B7F7326340add69a1A494E74c913)      |
| Simulator          | [0xADA8c0ab7486dF16c40eF03EE972ff62CF8B4CAF](https://polygonscan.com/address/0xADA8c0ab7486dF16c40eF03EE972ff62CF8B4CAF)      |
| Sorter             | [0x6e1886aEca75160BAa5610B7c1D3a895198C61cf](https://polygonscan.com/address/0x6e1886aEca75160BAa5610B7c1D3a895198C61cf)      |

| DAppControl        | Address                                                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| FastLane Online    | [0x3BF81d7D921E7a6A1999ce3dfa3B348c50fE8DFd](https://amoy.polygonscan.com/address/0x3BF81d7D921E7a6A1999ce3dfa3B348c50fE8DFd) |


### Binance Smart Chain Mainnet

Commit hash of deployment: [3416300](https://github.com/FastLane-Labs/atlas/commit/3416300be0576f558b5f06c4aad095b9e76d1f3d)

| Contract           | Address                                                                                                                       |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Atlas              | [0xD72D821dA82964c0546a5501347a3959808E072f](https://bscscan.com/address/0xD72D821dA82964c0546a5501347a3959808E072f)          |
| AtlasVerification  | [0xae631aCDC436b9Dfd75C5629F825330d91459445](https://bscscan.com/address/0xae631aCDC436b9Dfd75C5629F825330d91459445)          |
| Simulator          | [0xAb665f032e6A20Ef7D43FfD4E92a2f4fd6d5771e](https://bscscan.com/address/0xAb665f032e6A20Ef7D43FfD4E92a2f4fd6d5771e)          |
| Sorter             | [0xb47387995e866908B25b49e8BaC7e499170461A6](https://bscscan.com/address/0xb47387995e866908B25b49e8BaC7e499170461A6)          |