//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "src/contracts/types/EscrowTypes.sol";
import "src/contracts/types/LockTypes.sol";
import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";
import { AtlasConstants } from "src/contracts/types/AtlasConstants.sol";

/// @title Storage
/// @author FastLane Labs
/// @notice Storage manages all storage variables and constants for the Atlas smart contract.
contract Storage is AtlasEvents, AtlasErrors, AtlasConstants {
    // Atlas constants
    uint256 internal constant _GAS_USED_DECIMALS_TO_DROP = 1000;
    address internal constant _UNLOCKED = address(1);
    uint256 internal constant _UNLOCKED_UINT = 1;

    // Atlas constants used in `_bidFindingIteration()`
    uint256 internal constant BITS_FOR_INDEX = 16;
    uint256 internal constant FIRST_16_BITS_MASK = uint256(0xFFFF);
    uint256 internal constant FIRST_240_BITS_MASK =
        uint256(0x0000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    uint256 public immutable ESCROW_DURATION;
    address public immutable VERIFICATION;
    address public immutable SIMULATOR;

    // AtlETH ERC-20 constants
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

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

    // Escrow constants
    uint256 internal constant _VALIDATION_GAS_LIMIT = 500_000;
    uint256 internal constant _SOLVER_GAS_LIMIT_BUFFER_PERCENTAGE = 5; // out of 100 = 5%
    uint256 internal constant _SOLVER_GAS_LIMIT_SCALE = 100; // out of 100 = 100%
    uint256 internal constant _FASTLANE_GAS_BUFFER = 125_000; // integer amount

    // Gas Accounting constants
    uint256 public constant SURCHARGE_RATE = 1_000_000; // 1_000_000 / 10_000_000 = 10%
    uint256 public constant SURCHARGE_SCALE = 10_000_000; // 10_000_000 / 10_000_000 = 100%
    uint256 internal constant _CALLDATA_LENGTH_PREMIUM = 32; // 16 (default) * 2
    uint256 internal constant _SOLVER_OP_BASE_CALLDATA = 608; // SolverOperation calldata length excluding solverOp.data
    uint256 internal constant _SOLVER_LOCK_GAS_BUFFER = 5000; // Base gas charged to solver in `_releaseSolverLock()`

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

    // First 160 bits of _solverLock are the address of the current solver.
    // The 161st bit represents whether the solver has called back via `reconcile`.
    // The 162nd bit represents whether the solver's outstanding debt has been repaid via `reconcile`.
    uint256 internal constant _SOLVER_CALLED_BACK_MASK = 1 << 161;
    uint256 internal constant _SOLVER_FULFILLED_MASK = 1 << 162;

    constructor(
        uint256 _escrowDuration,
        address _verification,
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
    function solverLockData() public view returns (address currentSolver, bool calledBack, bool fulfilled) {
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
