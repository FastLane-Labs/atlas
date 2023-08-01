//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface ITokenTransfers {
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user, 
        address protocolControl,
        uint16 callConfig
    ) external;

    function transferProtocolERC20(
        address token,
        address destination,
        uint256 amount,
        address user, 
        address protocolControl,
        uint16 callConfig
    ) external;
}
