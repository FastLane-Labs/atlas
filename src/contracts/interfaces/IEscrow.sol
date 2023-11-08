//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {Party} from "../types/EscrowTypes.sol";

interface IEscrow {
    function validateBalances() external view returns (bool valid);
    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool);
    function contribute(Party party) external payable;
    function deposit(Party party) external payable;
    function contributeTo(Party donor, Party recipient, uint256 amt) external;
    function requestFrom(Party donor, Party recipient, uint256 amt) external;
    function finalize(Party party, address partyAddress) external returns (bool);
}
