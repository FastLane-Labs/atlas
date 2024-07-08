//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/libraries/AccountingMath.sol";

import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";

/// @title Storage
/// @author FastLane Labs
/// @notice Storage manages all storage variables and constants for the Atlas smart contract.
contract Storage is AtlasEvents, AtlasErrors, AtlasConstants {
    IAtlasVerification public immutable VERIFICATION;
    address public immutable SIMULATOR;
    uint256 public immutable ESCROW_DURATION;

    // AtlETH public constants
    // These constants double as interface functions for the ERC20 standard, hence the lowercase naming convention.
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    // Gas Accounting public constants
    uint256 public constant ATLAS_SURCHARGE_RATE = AccountingMath._ATLAS_SURCHARGE_RATE;
    uint256 public constant BUNDLER_SURCHARGE_RATE = AccountingMath._BUNDLER_SURCHARGE_RATE;
    uint256 public constant SCALE = AccountingMath._SCALE;
    uint256 public constant FIXED_GAS_OFFSET = AccountingMath._FIXED_GAS_OFFSET;

    // Transient storage slots
    bytes32 private constant _T_LOCK_SLOT = keccak256("LOCK");
    bytes32 private constant _T_SOLVER_LOCK_SLOT = keccak256("SOLVER_LOCK");
    bytes32 private constant _T_SOLVER_TO_SLOT = keccak256("SOLVER_TO");
    bytes32 private constant _T_CLAIMS_SLOT = keccak256("CLAIMS");
    bytes32 private constant _T_FEES_SLOT = keccak256("FEES");
    bytes32 private constant _T_WRITEOFFS_SLOT = keccak256("WRITEOFFS");
    bytes32 private constant _T_WITHDRAWALS_SLOT = keccak256("WITHDRAWALS");
    bytes32 private constant _T_DEPOSITS_SLOT = keccak256("DEPOSITS");

    // AtlETH storage
    uint256 internal S_totalSupply;
    uint256 internal S_bondedTotalSupply;

    mapping(address => EscrowAccountBalance) internal s_balanceOf; // public balanceOf will return a uint256
    mapping(address => EscrowAccountAccessData) internal S_accessData;
    mapping(bytes32 => bool) internal S_solverOpHashes; // NOTE: Only used for when allowTrustedOpHash is enabled

    // atlETH GasAccounting storage
    uint256 internal S_cumulativeSurcharge; // Cumulative gas surcharges collected
    address internal S_surchargeRecipient; // Fastlane surcharge recipient
    address internal S_pendingSurchargeRecipient; // For 2-step transfer process

    constructor(
        uint256 escrowDuration,
        address verification,
        address simulator,
        address initialSurchargeRecipient
    )
        payable
    {
        VERIFICATION = IAtlasVerification(verification);
        SIMULATOR = simulator;
        ESCROW_DURATION = escrowDuration;

        // Gas Accounting
        // Initialized with msg.value to seed flash loan liquidity
        S_cumulativeSurcharge = msg.value;
        S_surchargeRecipient = initialSurchargeRecipient;

        emit SurchargeRecipientTransferred(initialSurchargeRecipient);
    }

    // ---------------------------------------------------- //
    //                     Storage Getters                  //
    // ---------------------------------------------------- //
    function totalSupply() external view returns (uint256) {
        return S_totalSupply;
    }

    function bondedTotalSupply() external view returns (uint256) {
        return S_bondedTotalSupply;
    }

    function accessData(address account)
        external
        view
        returns (uint112 bonded, uint32 lastAccessedBlock, uint24 auctionWins, uint24 auctionFails, uint64 totalGasUsed)
    {
        EscrowAccountAccessData memory _aData = S_accessData[account];

        bonded = _aData.bonded;
        lastAccessedBlock = _aData.lastAccessedBlock;
        auctionWins = _aData.auctionWins;
        auctionFails = _aData.auctionFails;
        totalGasUsed = _aData.totalGasUsed;
    }

    function solverOpHashes(bytes32 opHash) external view returns (bool) {
        return S_solverOpHashes[opHash];
    }

    function cumulativeSurcharge() external view returns (uint256) {
        return S_cumulativeSurcharge;
    }

    function surchargeRecipient() external view returns (address) {
        return S_surchargeRecipient;
    }

    function pendingSurchargeRecipient() external view returns (address) {
        return S_pendingSurchargeRecipient;
    }

    // ---------------------------------------------------- //
    //              Transient External Getters              //
    // ---------------------------------------------------- //

    function lock() external view returns (address activeEnvironment, uint32 callConfig, uint8 phase) {
        return _lock();
    }

    /// @notice Returns the current lock state of Atlas.
    /// @return Boolean indicating whether Atlas is in a locked state or not.
    function isUnlocked() external view returns (bool) {
        return _isUnlocked();
    }

    function claims() public view returns (uint256) {
        return uint256(_tload(_T_CLAIMS_SLOT));
    }

    function fees() public view returns (uint256) {
        return uint256(_tload(_T_FEES_SLOT));
    }

    function writeoffs() public view returns (uint256) {
        return uint256(_tload(_T_WRITEOFFS_SLOT));
    }

    function withdrawals() public view returns (uint256) {
        return uint256(_tload(_T_WITHDRAWALS_SLOT));
    }

    function deposits() public view returns (uint256) {
        return uint256(_tload(_T_DEPOSITS_SLOT));
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled) {
        return _solverLockData();
    }

    // ---------------------------------------------------- //
    //              Transient Internal Getters              //
    // ---------------------------------------------------- //

    function _lock() internal view returns (address activeEnvironment, uint32 callConfig, uint8 phase) {
        bytes32 _lockData = _tload(_T_LOCK_SLOT);
        activeEnvironment = address(uint160(uint256(_lockData >> 40)));
        callConfig = uint32(uint256(_lockData >> 8));
        phase = uint8(uint256(_lockData));
    }

    function _activeEnvironment() internal view returns (address) {
        // right shift 40 bits to remove the callConfig and phase, only activeEnvironment remains
        return address(uint160(uint256(_tload(_T_LOCK_SLOT) >> 40)));
    }

    function _activeCallConfig() internal view returns (uint32) {
        // right shift 8 bits to remove the phase, cast to uint32 to remove the activeEnvironment
        return uint32(uint256(_tload(_T_LOCK_SLOT) >> 8));
    }

    function _phase() internal view returns (uint8) {
        // right-most 8 bits of Lock are the phase
        return uint8(uint256(_tload(_T_LOCK_SLOT)));
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function _solverLockData() internal view returns (address currentSolver, bool calledBack, bool fulfilled) {
        uint256 _solverLock = uint256(_tload(_T_SOLVER_LOCK_SLOT));
        currentSolver = address(uint160(_solverLock));
        calledBack = _solverLock & _SOLVER_CALLED_BACK_MASK != 0;
        fulfilled = _solverLock & _SOLVER_FULFILLED_MASK != 0;
    }

    function _solverTo() internal view returns (address) {
        return address(uint160(uint256(_tload(_T_SOLVER_TO_SLOT))));
    }

    function _isUnlocked() internal view returns (bool) {
        return _tload(_T_LOCK_SLOT) == bytes32(0);
    }

    // ---------------------------------------------------- //
    //                   Transient Setters                  //
    // ---------------------------------------------------- //

    function _setLock(Lock memory newLock) internal {
        // Pack the lock slot from the right:
        // [   56 bits   ][     160 bits      ][  32 bits   ][ 8 bits ]
        // [ unused bits ][ activeEnvironment ][ callConfig ][ phase  ]
        _tstore(
            _T_LOCK_SLOT,
            bytes32(uint256(uint160(newLock.activeEnvironment))) << 40 | bytes32(uint256(newLock.callConfig)) << 8
                | bytes32(uint256(newLock.phase))
        );
    }

    // Sets the Lock phase without changing the activeEnvironment or callConfig.
    function _setLockPhase(uint8 newPhase) internal {
        _tstore(_T_LOCK_SLOT, (_tload(_T_LOCK_SLOT) & _LOCK_PHASE_MASK) | bytes32(uint256(newPhase)));
    }

    function _setSolverLock(uint256 newSolverLock) internal {
        _tstore(_T_SOLVER_LOCK_SLOT, bytes32(newSolverLock));
    }

    function _setSolverTo(address newSolverTo) internal {
        _tstore(_T_SOLVER_TO_SLOT, bytes32(uint256(uint160(newSolverTo))));
    }

    function _setClaims(uint256 newClaims) internal {
        _tstore(_T_CLAIMS_SLOT, bytes32(newClaims));
    }

    function _setFees(uint256 newFees) internal {
        _tstore(_T_FEES_SLOT, bytes32(newFees));
    }

    function _setWriteoffs(uint256 newWriteoffs) internal {
        _tstore(_T_WRITEOFFS_SLOT, bytes32(newWriteoffs));
    }

    function _setWithdrawals(uint256 newWithdrawals) internal {
        _tstore(_T_WITHDRAWALS_SLOT, bytes32(newWithdrawals));
    }

    function _setDeposits(uint256 newDeposits) internal {
        _tstore(_T_DEPOSITS_SLOT, bytes32(newDeposits));
    }

    // ------------------------------------------------------ //
    //                Transient Storage Helpers               //
    // ------------------------------------------------------ //

    function _tstore(bytes32 slot, bytes32 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    function _tload(bytes32 slot) internal view returns (bytes32 value) {
        assembly {
            value := tload(slot)
        }
        return value;
    }
}
