//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";
import "../libraries/AccountingMath.sol";

import { AtlasEvents } from "../types/AtlasEvents.sol";
import { AtlasErrors } from "../types/AtlasErrors.sol";
import { AtlasConstants } from "../types/AtlasConstants.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";

/// @title Storage
/// @author FastLane Labs
/// @notice Storage manages all storage variables and constants for the Atlas smart contract.
contract Storage is AtlasEvents, AtlasErrors, AtlasConstants {
    IAtlasVerification public immutable VERIFICATION;
    address public immutable SIMULATOR;
    address public immutable L2_GAS_CALCULATOR;
    uint256 public immutable ESCROW_DURATION;

    // AtlETH public constants
    // These constants double as interface functions for the ERC20 standard, hence the lowercase naming convention.
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    // Gas Accounting public constants
    uint256 public constant SCALE = AccountingMath._SCALE;
    uint256 public constant FIXED_GAS_OFFSET = AccountingMath._FIXED_GAS_OFFSET;

    // Transient storage slots
    uint256 internal transient t_lock; // contains activeAddress, callConfig, and phase
    uint256 internal transient t_solverLock; 
    address internal transient t_solverTo; // current solverOp.solver contract address

    // Tracks gas accounting vars - see GasAccLib.sol for more details
    uint256 internal transient t_gasLedger;

    // Tracks borrows and repayments of native token - see GasAccLib.sol for more details
    uint256 internal transient t_borrowsLedger;

    // AtlETH storage
    uint256 internal S_totalSupply;
    uint256 internal S_bondedTotalSupply;

    // Surcharge-related storage
    uint256 internal S_surchargeRates; // left 128 bits: Atlas rate, right 128 bits: Bundler rate
    uint256 internal S_cumulativeSurcharge; // Cumulative gas surcharges collected
    address internal S_surchargeRecipient; // Fastlane surcharge recipient
    address internal S_pendingSurchargeRecipient; // For 2-step transfer process

    mapping(address => EscrowAccountBalance) internal s_balanceOf; // public balanceOf will return a uint256
    mapping(address => EscrowAccountAccessData) internal S_accessData;
    mapping(bytes32 => bool) internal S_solverOpHashes; // NOTE: Only used for when allowTrustedOpHash is enabled
    
    constructor(
        uint256 escrowDuration,
        uint256 atlasSurchargeRate,
        uint256 bundlerSurchargeRate,
        address verification,
        address simulator,
        address initialSurchargeRecipient,
        address l2GasCalculator
    )
        payable
    {
        VERIFICATION = IAtlasVerification(verification);
        SIMULATOR = simulator;
        L2_GAS_CALCULATOR = l2GasCalculator;
        ESCROW_DURATION = escrowDuration;

        // Check Atlas and Bundler gas surcharges fit in 128 bits each
        if(atlasSurchargeRate > type(uint128).max || bundlerSurchargeRate > type(uint128).max) {
            revert SurchargeRateTooHigh();
        }

        S_surchargeRates = atlasSurchargeRate << 128 | bundlerSurchargeRate;
        S_cumulativeSurcharge = msg.value;
        S_surchargeRecipient = initialSurchargeRecipient;

        emit SurchargeRecipientTransferred(initialSurchargeRecipient);
    }

    // ---------------------------------------------------- //
    //                     Storage Setters                  //
    // ---------------------------------------------------- //

    function setSurchargeRates(uint256 newAtlasRate, uint256 newBundlerRate) external {
        _onlySurchargeRecipient();

        // Check Atlas and Bundler gas surcharges fit in 128 bits each
        if(newAtlasRate > type(uint128).max || newBundlerRate > type(uint128).max) {
            revert SurchargeRateTooHigh();
        }

        S_surchargeRates = newAtlasRate << 128 | newBundlerRate;
    }

    function _onlySurchargeRecipient() internal view {
        if (msg.sender != S_surchargeRecipient) {
            revert InvalidAccess();
        }
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
        returns (
            uint112 bonded,
            uint32 lastAccessedBlock,
            uint24 auctionWins,
            uint24 auctionFails,
            uint64 totalGasValueUsed
        )
    {
        EscrowAccountAccessData memory _aData = S_accessData[account];

        bonded = _aData.bonded;
        lastAccessedBlock = _aData.lastAccessedBlock;
        auctionWins = _aData.auctionWins;
        auctionFails = _aData.auctionFails;
        totalGasValueUsed = _aData.totalGasValueUsed;
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

    function atlasSurchargeRate() external view returns (uint256) {
        // Includes only the left 128 bits to isolate the Atlas rate
        return S_surchargeRates >> 128;
    }

    function bundlerSurchargeRate() external view returns (uint256) {
        // Includes only the right 128 bits to isolate the bundler rate
        return S_surchargeRates & ((1 << 128) - 1);
    }

    // ---------------------------------------------------- //
    //               Storage Internal Getters               //
    // ---------------------------------------------------- //

    function _surchargeRates() internal view returns (uint256 atlasRate, uint256 bundlerRate) {
        uint256 _bothRates = S_surchargeRates;
        atlasRate = _bothRates >> 128;
        bundlerRate = _bothRates & ((1 << 128) - 1);
    }

    function _totalSurchargeRate() internal view returns(uint256 totalSurchargeRate) {
        (uint256 atlasRate, uint256 bundlerRate) = _surchargeRates();
        totalSurchargeRate = atlasRate + bundlerRate;
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
        uint256 _lockData = t_lock;
        activeEnvironment = address(uint160(_lockData >> 40));
        callConfig = uint32(_lockData >> 8);
        phase = uint8(_lockData);
    }

    function _activeEnvironment() internal view returns (address) {
        // right shift 40 bits to remove the callConfig and phase, only activeEnvironment remains
        return address(uint160(t_lock >> 40));
    }

    function _activeCallConfig() internal view returns (uint32) {
        // right shift 8 bits to remove the phase, cast to uint32 to remove the activeEnvironment
        return uint32(t_lock >> 8);
    }

    function _phase() internal view returns (uint8) {
        // right-most 8 bits of Lock are the phase
        return uint8(t_lock);
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function _solverLockData() internal view returns (address currentSolver, bool calledBack, bool fulfilled) {
        uint256 _solverLock = t_solverLock;
        currentSolver = address(uint160(_solverLock));
        calledBack = _solverLock & _SOLVER_CALLED_BACK_MASK != 0;
        fulfilled = _solverLock & _SOLVER_FULFILLED_MASK != 0;
    }

    function _isUnlocked() internal view returns (bool) {
        return t_lock == _UNLOCKED;
    }

    // ---------------------------------------------------- //
    //                   Transient Setters                  //
    // ---------------------------------------------------- //

    function _setLock(address activeEnvironment, uint32 callConfig, uint8 phase) internal {
        // Pack the lock slot from the right:
        // [   56 bits   ][     160 bits      ][  32 bits   ][ 8 bits ]
        // [ unused bits ][ activeEnvironment ][ callConfig ][ phase  ]
        t_lock = uint256(uint160(activeEnvironment)) << 40 | uint256(callConfig) << 8 | uint256(phase);
    }

    function _releaseLock() internal {
        t_lock = _UNLOCKED;
    }

    // Sets the Lock phase without changing the activeEnvironment or callConfig.
    function _setLockPhase(uint8 newPhase) internal {
        t_lock = (t_lock & _LOCK_PHASE_MASK) | uint256(newPhase);
    }
}
