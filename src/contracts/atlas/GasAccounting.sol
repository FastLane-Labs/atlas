//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {SafetyLocks} from "../atlas/SafetyLocks.sol";
import {GasAccountingLib} from "./GasAccountingLib.sol";

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import {EscrowBits} from "../libraries/EscrowBits.sol";
import {PartyMath} from "../libraries/GasParties.sol";

import "forge-std/Test.sol"; //TODO remove

abstract contract GasAccounting is SafetyLocks {
    using PartyMath for Party;
    using PartyMath for uint256;
    using PartyMath for Ledger[LEDGER_LENGTH];

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _simulator
    ) SafetyLocks(_escrowDuration, _factory, _verification, _gasAccLib, _simulator) {}

    // ---------------------------------------
    //          EXTERNAL FUNCTIONS
    // ---------------------------------------

    // Returns true if Solver status is Finalized and the caller (Execution Environment) is in surplus
    // NOTE: This was a view function until logic got moved to delegatecalled contract - still should only be view
    function validateBalances() external returns (bool valid) {
        valid = ledgers[uint256(Party.Solver)].status == LedgerStatus.Finalized && _isInSurplus(msg.sender);
    }

    function deposit(Party party) external payable {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.deposit.selector, party));
    }

    function contribute(Party recipient) external payable {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.contribute.selector, recipient));
    }

    function contributeTo(Party donor, Party recipient, uint256 amt) external {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.contributeTo.selector, msg.sender, donor, recipient, amt));
    }

    function requestFrom(Party donor, Party recipient, uint256 amt) external {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.requestFrom.selector, msg.sender, donor, recipient, amt));
    }

    function finalize(Party party, address partyAddress) external {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.finalize.selector, party, partyAddress));
    }

    function reconcile(address environment, address searcherFrom, uint256 maxApprovedGasSpend) external payable returns (bool) {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.reconcile.selector, environment, searcherFrom, maxApprovedGasSpend));
        return abi.decode(data, (bool));
    }

    // ---------------------------------------
    //          INTERNAL FUNCTIONS
    // ---------------------------------------

    function _updateSolverProxy(address solverFrom, address bundler, bool solverSuccessful) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.updateSolverProxy.selector, solverFrom, bundler, solverSuccessful));
    }

    function _checkSolverProxy(address solverFrom, address bundler) internal returns (bool validSolver) {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.checkSolverProxy.selector, solverFrom, bundler));
        return abi.decode(data, (bool));
    }

    function _borrow(Party party, uint256 amt) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.borrow.selector, party, amt));
    }

    function _tradeCorrection(Party party, uint256 amt) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.tradeCorrection.selector, party, amt));
    }

    function _use(Party party, address partyAddress, uint256 amt) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.use.selector, party, partyAddress, amt));
    }

    function _requestFrom(Party donor, Party recipient, uint256 amt) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.requestFrom.selector, address(this), donor, recipient, amt));
    }

    function _contributeTo(Party donor, Party recipient, uint256 amt) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.contributeTo.selector, address(this), donor, recipient, amt));
    }

    function _isInSurplus(address environment) internal returns (bool) {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.isInSurplus.selector, environment));
        return abi.decode(data, (bool));
    }

    function _balance(uint256 accruedGasRebate, address user, address dapp, address winningSolver, address bundler) internal {
        GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.balance.selector, accruedGasRebate, user, dapp, winningSolver, bundler));
    }

    function _validParties(address environment, Party partyOne, Party partyTwo) internal returns (bool) {
        (bool success, bytes memory data) = GAS_ACC_LIB.delegatecall(abi.encodeWithSelector(GasAccountingLib.validParties.selector, environment, partyOne, partyTwo));
        return abi.decode(data, (bool));
    }

}