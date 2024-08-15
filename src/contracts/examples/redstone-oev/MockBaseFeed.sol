//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { MergedPriceFeedAdapterWithRounds } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/price-feeds/with-rounds/MergedPriceFeedAdapterWithRounds.sol";

contract MockBaseFeed is MergedPriceFeedAdapterWithRounds {
    error UnauthorizedSigner();

    address public AUTHORIZED_SIGNER;

    constructor(address authorizedSigner) {
        AUTHORIZED_SIGNER = authorizedSigner;
    }

    function getAuthorisedSignerIndex(address receivedSigner) public view virtual override returns (uint8) {
        if (receivedSigner == AUTHORIZED_SIGNER) {
            return 0;
        }
        revert UnauthorizedSigner();
    }

    function getDataFeedId() public view virtual override returns (bytes32) {
        return bytes32("ATLAS-DEMO-MOCK-FEED");
    }
}
