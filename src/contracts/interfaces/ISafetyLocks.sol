//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/SolverOperation.sol";
import "../types/UserOperation.sol";
import "../types/ConfigTypes.sol";
import "../types/LockTypes.sol";

interface ISafetyLocks {
    function activeEnvironment() external view returns (address);

    function isUnlocked() external view returns (bool);

    function getLockState() external view returns (Context memory);

    function confirmSafetyCallback() external view returns (bool);
}
