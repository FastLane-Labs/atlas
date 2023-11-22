//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { SafetyLocks } from "../atlas/SafetyLocks.sol";
import { GasAccountingLib } from "./GasAccountingLib.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

// import {EscrowBits} from "../libraries/EscrowBits.sol";

// import "forge-std/Test.sol"; //TODO remove

abstract contract GasAccounting is SafetyLocks {
    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _safetyLocksLib,
        address _simulator
    )
        SafetyLocks(_escrowDuration, _factory, _verification, _gasAccLib, _safetyLocksLib, _simulator)
    { }

    // ---------------------------------------
    //          EXTERNAL FUNCTIONS
    // ---------------------------------------

    // Returns true if Solver status is Finalized and the caller (Execution Environment) is in surplus
    // NOTE: This was a view function until logic got moved to delegatecalled contract - still should only be view
    function validateBalances() external returns (bool valid) {
        valid = ledgers[uint256(Party.Solver)].status == LedgerStatus.Finalized && _isInSurplus(msg.sender);
    }

    function deposit(Party party) external payable {
        (bool success,) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.deposit.selector, party));
        if (!success) revert GasAccountingLibError();
    }

    function contributeTo(Party donor, Party recipient, uint256 amt) external payable {
        (bool success,) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.contributeTo.selector, msg.sender, donor, recipient, amt)
        );
        if (!success) revert GasAccountingLibError();
    }

    function requestFrom(Party donor, Party recipient, uint256 amt) external {
        (bool success,) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.requestFrom.selector, msg.sender, donor, recipient, amt)
        );
        if (!success) revert GasAccountingLibError();
    }

    function reconcile(
        address environment,
        address searcherFrom,
        uint256 maxApprovedGasSpend
    )
        external
        payable
        returns (bool)
    {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.reconcile.selector, environment, searcherFrom, maxApprovedGasSpend)
        );
        if (!success) revert GasAccountingLibError();
        return abi.decode(data, (bool));
    }

    // ---------------------------------------
    //          INTERNAL FUNCTIONS
    // ---------------------------------------

    function _setSolverLedger(address solverFrom, uint256 solverOpValue) internal {
        (bool success,) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.setSolverLedger.selector, solverFrom, solverOpValue));
        if (!success) revert GasAccountingLibError();
    }

    function _releaseSolverLedger(SolverOperation calldata solverOp, uint256 gasWaterMark, uint256 result) internal {
        (bool success,) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.releaseSolverLedger.selector, solverOp, gasWaterMark, result));
        if (!success) revert GasAccountingLibError();
    }

    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        (bool success,) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.requestFrom.selector, address(this), donor, recipient, amt)
        );
        if (!success) revert GasAccountingLibError();
    }

    function _contributeTo(Party donor, Party recipient, uint256 amt) internal {
        (bool success,) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.contributeTo.selector, address(this), donor, recipient, amt)
        );
        if (!success) revert GasAccountingLibError();
    }

    function _isInSurplus(address environment) internal returns (bool) {
        (bool success, bytes memory data) =
            GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.isInSurplus.selector, environment));
        if (!success) revert GasAccountingLibError();
        return abi.decode(data, (bool));
    }

    function _balance(
        uint256 accruedGasRebate,
        address user,
        address dapp,
        address winningSolver,
        address bundler
    )
        internal
    {
        (bool success,) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(
                GasAccountingLib.balance.selector, accruedGasRebate, user, dapp, winningSolver, bundler
            )
        );
        if (!success) revert GasAccountingLibError();
    }

    function _validParties(address environment, Party partyOne, Party partyTwo) internal returns (bool) {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(
            abi.encodeWithSelector(GasAccountingLib.validParties.selector, environment, partyOne, partyTwo)
        );
        if (!success) revert GasAccountingLibError();
        return abi.decode(data, (bool));
    }
}
