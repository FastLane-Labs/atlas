//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {GasParty} from "../types/EscrowTypes.sol";

interface IEscrow {
    function validateBalances() external view returns (bool valid);
    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool);
    function contribute(GasParty party) external payable;
    function deposit(GasParty party) external payable;
    function contributeTo(GasParty donor, GasParty recipient, uint256 amt) external;
    function requestFrom(GasParty donor, GasParty recipient, uint256 amt) external;
    function finalize(GasParty party, address partyAddress) external returns (bool);
}
