//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {ProtocolCall, SearcherCall} from "../types/CallTypes.sol";

interface IEscrow {
    function donateToBundler(address surplusRecipient) external payable;
    function cumulativeDonations() external view returns (uint256);
    function deposit(address searcherMetaTxSigner) external payable returns (uint256 newBalance);
    function nextSearcherNonce(address searcherMetaTxSigner) external view returns (uint256 nextNonce);
    function searcherEscrowBalance(address searcherMetaTxSigner) external view returns (uint256 balance);
    function searcherLastActiveBlock(address searcherMetaTxSigner) external view returns (uint256 lastBlock);

    function verifySearcherStorage(ProtocolCall calldata protocolCall, SearcherCall calldata searcherCall)
        external
        returns (bool invalid, uint128 gasCost);
}
