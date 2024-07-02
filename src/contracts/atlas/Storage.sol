//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";

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
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    // Gas Accounting public constants
    uint256 public constant ATLAS_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant BUNDLER_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant SURCHARGE_SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 public constant FIXED_GAS_OFFSET = 100_000;

    // AtlETH storage
    uint256 public S_totalSupply;
    uint256 public S_bondedTotalSupply;

    mapping(address => EscrowAccountBalance) internal s_balanceOf; // public balanceOf will return a uint256
    mapping(address => EscrowAccountAccessData) public S_accessData;
    mapping(bytes32 => bool) internal S_solverOpHashes; // NOTE: Only used for when allowTrustedOpHash is enabled

    // atlETH GasAccounting storage
    uint256 internal S_cumulativeSurcharge; // Cumulative gas surcharges collected
    address internal S_surchargeRecipient; // Fastlane surcharge recipient
    address internal S_pendingSurchargeRecipient; // For 2-step transfer process

    // Atlas SafetyLocks (transient storage)
    Lock internal T_lock; // transient storage
    uint256 internal T_solverLock; // transient storage

    uint256 internal T_claims; // transient storage
    uint256 internal T_fees; // transient storage
    uint256 internal T_writeoffs; // transient storage
    uint256 internal T_withdrawals; // transient storage
    uint256 internal T_deposits; // transient storage

    // TODO refactor to constants once PR is ready
    bytes32 private constant _T_LOCK_SLOT = keccak256("LOCK");
    bytes32 private constant _T_SOLVER_LOCK_SLOT = keccak256("SOLVER_LOCK");
    bytes32 private constant _T_CLAIMS_SLOT = keccak256("CLAIMS");
    bytes32 private constant _T_FEES_SLOT = keccak256("FEES");
    bytes32 private constant _T_WRITEOFFS_SLOT = keccak256("WRITEOFFS");
    bytes32 private constant _T_WITHDRAWALS_SLOT = keccak256("WITHDRAWALS");
    bytes32 private constant _T_DEPOSITS_SLOT = keccak256("DEPOSITS");

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

    /// @notice Returns the EIP-712 domain separator for permit signatures, implemented in AtlETH.
    /// @return bytes32 Domain separator hash.
    function _computeDomainSeparator() internal view virtual returns (bytes32) { }

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

    function lock() public view returns (address activeEnvironment, uint32 callConfig, uint8 phase) {
        bytes32 _lockData = _tload(_T_LOCK_SLOT);
        activeEnvironment = address(uint160(uint256(_lockData >> 40)));
        callConfig = uint32(uint256(_lockData >> 8));
        phase = uint8(uint256(_lockData));
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

    function _isUnlocked() internal view returns (bool) {
        return _tload(_T_LOCK_SLOT) == bytes32(0);
    }

    // ---------------------------------------------------- //
    //                   Transient Setters                  //
    // ---------------------------------------------------- //

    function _setLock(Lock memory lock) internal {
        // Pack the lock slot from the right:
        // [   56 bits   ][     160 bits      ][  32 bits   ][ 8 bits ]
        // [ unused bits ][ activeEnvironment ][ callConfig ][ phase  ]
        _tstore(
            _T_LOCK_SLOT,
            bytes32(uint256(uint160(lock.activeEnvironment))) << 40 | bytes32(uint256(lock.callConfig)) << 8
                | bytes32(uint256(lock.phase))
        );
    }

    // Sets the Lock phase without changing the activeEnvironment or callConfig.
    function _setLockPhase(uint8 phase) internal {
        _tstore(_T_LOCK_SLOT, (_tload(_T_LOCK_SLOT) & (_LOCK_PHASE_MASK | bytes32(uint256(phase)))));
    }

    function _setSolverLock(uint256 solverLock) internal {
        _tstore(_T_SOLVER_LOCK_SLOT, bytes32(solverLock));
    }

    function _setClaims(uint256 claims) internal {
        _tstore(_T_CLAIMS_SLOT, bytes32(claims));
    }

    function _setFees(uint256 fees) internal {
        _tstore(_T_FEES_SLOT, bytes32(fees));
    }

    function _setWriteoffs(uint256 writeoffs) internal {
        _tstore(_T_WRITEOFFS_SLOT, bytes32(writeoffs));
    }

    function _setWithdrawals(uint256 withdrawals) internal {
        _tstore(_T_WITHDRAWALS_SLOT, bytes32(withdrawals));
    }

    function _setDeposits(uint256 deposits) internal {
        _tstore(_T_DEPOSITS_SLOT, bytes32(deposits));
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
