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
    uint256 public constant SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant SURCHARGE_SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 public constant FIXED_GAS_OFFSET = 100_000;

    // AtlETH EIP-2612 constants
    uint256 internal immutable _INITIAL_CHAIN_ID;
    bytes32 internal immutable _INITIAL_DOMAIN_SEPARATOR;

    // AtlETH ERC-20 storage
    uint256 public totalSupply;
    uint256 public bondedTotalSupply;

    mapping(address => uint256) public nonces;
    mapping(address => EscrowAccountBalance) internal _balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => EscrowAccountAccessData) public accessData;
    mapping(bytes32 => bool) internal _solverOpHashes; // NOTE: Only used for when allowTrustedOpHash is enabled

    // atlETH GasAccounting storage
    uint256 public cumulativeSurcharge; // Cumulative gas surcharges collected
    address public surchargeRecipient; // Fastlane surcharge recipient
    address public pendingSurchargeRecipient; // For 2-step transfer process

    // Atlas SafetyLocks (transient storage)
    address public lock; // transient storage
    uint256 public claims; // transient storage
    uint256 public withdrawals; // transient storage
    uint256 public deposits; // transient storage
    uint256 internal _solverLock; // transient storage

    constructor(
        uint256 _escrowDuration,
        AtlasVerification _verification,
        address _simulator,
        address _surchargeRecipient
    )
        payable
    {
        ESCROW_DURATION = _escrowDuration;
        VERIFICATION = _verification;
        SIMULATOR = _simulator;
        _INITIAL_CHAIN_ID = block.chainid;
        _INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Gas Accounting
        // Initialized with msg.value to seed flash loan liquidity
        cumulativeSurcharge = msg.value;
        surchargeRecipient = _surchargeRecipient;

        // TODO remove these when transient storage behaviour is implemented
        // Gas Accounting - transient storage (delete this from constructor post dencun)
        lock = _UNLOCKED;
        _solverLock = _UNLOCKED_UINT;
        claims = type(uint256).max;
        withdrawals = type(uint256).max;
        deposits = type(uint256).max;

        emit SurchargeRecipientTransferred(_surchargeRecipient);
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function solverLockData() external view returns (address currentSolver, bool calledBack, bool fulfilled) {
        return _solverLockData();
    }

    /// @notice Returns information about the current state of the solver lock.
    /// @return currentSolver Address of the current solver.
    /// @return calledBack Boolean indicating whether the solver has called back via `reconcile`.
    /// @return fulfilled Boolean indicating whether the solver's outstanding debt has been repaid via `reconcile`.
    function _solverLockData() internal view returns (address currentSolver, bool calledBack, bool fulfilled) {
        uint256 solverLock = _solverLock;
        currentSolver = address(uint160(solverLock));
        calledBack = solverLock & _SOLVER_CALLED_BACK_MASK != 0;
        fulfilled = solverLock & _SOLVER_FULFILLED_MASK != 0;
    }

    /// @notice Returns the address of the current solver.
    /// @return Address of the current solver.
    function solver() public view returns (address) {
        return address(uint160(_solverLock));
    }

    /// @notice Returns the EIP-712 domain separator for permit signatures, implemented in AtlETH.
    /// @return bytes32 Domain separator hash.
    function _computeDomainSeparator() internal view virtual returns (bytes32) { }
}
