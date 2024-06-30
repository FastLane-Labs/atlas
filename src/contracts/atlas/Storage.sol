//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";

/// @title Storage
/// @author FastLane Labs
/// @notice Storage manages all storage variables and constants for the Atlas smart contract.
contract Storage is AtlasEvents, AtlasErrors, AtlasConstants {
    uint256 public immutable ESCROW_DURATION;
    AtlasVerification public immutable VERIFICATION;
    address public immutable SIMULATOR;

    // AtlETH ERC-20 public constants
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    // Gas Accounting public constants
    uint256 public constant ATLAS_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant BUNDLER_SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant SURCHARGE_SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 public constant FIXED_GAS_OFFSET = 100_000;

    // AtlETH EIP-2612 constants
    uint256 internal immutable _INITIAL_CHAIN_ID;
    bytes32 internal immutable _INITIAL_DOMAIN_SEPARATOR;

    // AtlETH storage
    uint256 internal S_totalSupply;
    uint256 internal S_bondedTotalSupply;

    mapping(address => uint256) internal S_nonces;
    mapping(address => EscrowAccountBalance) internal s_balanceOf; // public balanceOf will return a uint256
    mapping(address => EscrowAccountAccessData) internal S_accessData;
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

    constructor(
        uint256 escrowDuration,
        address verification,
        address simulator,
        address surchargeRecipient
    )
        payable
    {
        ESCROW_DURATION = escrowDuration;
        VERIFICATION = AtlasVerification(verification);
        SIMULATOR = simulator;
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Gas Accounting
        // Initialized with msg.value to seed flash loan liquidity
        S_cumulativeSurcharge = msg.value;
        S_surchargeRecipient = surchargeRecipient;

        // TODO remove these when transient storage behaviour is implemented
        // Gas Accounting - transient storage (delete this from constructor post dencun)
        T_lock = Lock({ activeEnvironment: _UNLOCKED, phase: uint8(ExecutionPhase.Uninitialized), callConfig: uint32(0) });

        T_solverLock = _UNLOCKED_UINT;
        T_claims = type(uint256).max;
        T_fees = type(uint256).max;
        T_writeoffs = type(uint256).max;
        T_withdrawals = type(uint256).max;
        T_deposits = type(uint256).max;

        emit SurchargeRecipientTransferred(surchargeRecipient);
    }

    function totalSupply() external view returns (uint256) {
        return S_totalSupply;
    }

    function bondedTotalSupply() external view returns (uint256) {
        return S_bondedTotalSupply;
    }

    function nonces(address account) external view returns (uint256) {
        return S_nonces[account];
    }

    function accessData(uint256 account) external view returns (EscrowAccountAccessData memory) {
        return S_accessData[account];
    }

    function solverOpHashes(bytes32 opHash) external view returns (bool) {
        return S_solverOpHashes[opHash];
    }

    function lock() external view returns (Lock memory) {
        return T_lock;
    }

    function solverLock() external view returns (uint256) {
        return T_solverLock;
    }

    function claims() external view returns (uint256) {
        return T_claims;
    }

    function fees() external view returns (uint256) {
        return T_fees;
    }

    function writeoffs() external view returns (uint256) {
        return T_writeoffs;
    }

    function withdrawals() external view returns (uint256) {
        return T_withdrawals;
    }

    function deposits() external view returns (uint256) {
        return T_deposits;
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

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled) {
        return _solverLockData();
    }

    /// @notice Returns the address of the current solver.
    /// @return Address of the current solver.
    function solver() public view returns (address) {
        return address(uint160(T_solverLock));
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function _solverLockData() internal view returns (address currentSolver, bool calledBack, bool fulfilled) {
        uint256 _solverLock = T_solverLock;
        currentSolver = address(uint160(_solverLock));
        calledBack = _solverLock & _SOLVER_CALLED_BACK_MASK != 0;
        fulfilled = _solverLock & _SOLVER_FULFILLED_MASK != 0;
    }

    /// @notice Returns the EIP-712 domain separator for permit signatures, implemented in AtlETH.
    /// @return bytes32 Domain separator hash.
    function _computeDomainSeparator() internal view virtual returns (bytes32) { }
}
