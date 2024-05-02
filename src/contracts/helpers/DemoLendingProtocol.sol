// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

// A super basic Mock Lending Protocol to demo OEV captured through liquidations with Atlas.
// Liquidatable positions are created
contract DemoLendingProtocol is Ownable {
    address public immutable DEPOSIT_TOKEN;
    address public oracle;

    constructor(address depositToken) Ownable() {
        DEPOSIT_TOKEN = depositToken;
    }

    // ---------------------------------------------------- //
    //                     User Functions                   //
    // ---------------------------------------------------- //

    function deposit(uint256 amount, uint256 liquidationPrice) external {
        // Deposit funds into the lending protocol
    }

    function withdraw() external {
        // Withdraw funds from the lending protocol
    }

    // ---------------------------------------------------- //
    //                    Solver Functions                  //
    // ---------------------------------------------------- //

    function liquidate(address user) external {
        // Liquidate a user's position
    }

    // ---------------------------------------------------- //
    //                     Owner Functions                  //
    // ---------------------------------------------------- //

    function setOracle(address newOracle) external onlyOwner {
        oracle = newOracle;
    }
}
