//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";
import "../types/LockTypes.sol";

interface IAtlas {
    // Atlas.sol
    function metacall(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool auctionWon);

    // Factory.sol
    function createExecutionEnvironment(address control) external returns (address executionEnvironment);
    function getExecutionEnvironment(
        address user,
        address dAppControl
    )
        external
        view
        returns (address executionEnvironment, uint32 callConfig, bool exists);

    // AtlETH.sol
    function balanceOf(address account) external view returns (uint256);
    function balanceOfBonded(address account) external view returns (uint256);
    function balanceOfUnbonding(address account) external view returns (uint256);
    function accountLastActiveBlock(address account) external view returns (uint256);
    function unbondingCompleteBlock(address account) external view returns (uint256);
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function bond(uint256 amount) external;
    function depositAndBond(uint256 amountToBond) external payable;
    function unbond(uint256 amount) external;
    function redeem(uint256 amount) external;
    function withdrawSurcharge() external;
    function transferSurchargeRecipient(address newRecipient) external;
    function becomeSurchargeRecipient() external;

    // Permit69.sol
    function transferUserERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control
    )
        external;
    function transferDAppERC20(
        address token,
        address destination,
        uint256 amount,
        address user,
        address control
    )
        external;

    // GasAccounting.sol
    function contribute() external payable;
    function borrow(uint256 amount) external payable;
    function shortfall() external view returns (uint256);
    function reconcile(
        address environment,
        address solverFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (uint256 owed);

    // SafetyLocks.sol
    function activeEnvironment() external view returns (address);
    function phase() external view returns (ExecutionPhase);
    function isUnlocked() external view returns (bool);

    // Storage.sol
    function VERIFICATION() external view returns (address);
    function lock() external returns (address);
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled);
}
