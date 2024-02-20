//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

import { AtlasEvents } from "src/contracts/types/AtlasEvents.sol";
import { AtlasErrors } from "src/contracts/types/AtlasErrors.sol";

contract Storage is AtlasEvents, AtlasErrors {
    // Atlas constants
    uint256 internal constant _MAX_GAS = 1_500_000;
    uint256 internal constant GAS_USED_DECIMALS_TO_DROP = 1000;
    address internal constant UNLOCKED = address(1);
    uint256 internal constant _UNLOCKED_UINT = 1;

    uint256 public immutable ESCROW_DURATION;
    address public immutable VERIFICATION;
    address public immutable SIMULATOR;

    // AtlETH ERC-20 constants
    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    // AtlETH EIP-2612 constants
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    // AtlETH ERC-20 storage
    uint256 public totalSupply;
    uint256 public bondedTotalSupply;

    mapping(address => uint256) public nonces;
    mapping(address => EscrowAccountBalance) internal _balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => EscrowAccountAccessData) public accessData;

    // Gas Accounting constants
    uint256 public constant SURCHARGE_BASE = 100;
    uint256 public constant SURCHARGE = 10;

    // atlETH GasAccounting storage

    uint256 public surcharge; // Atlas gas surcharges
    address public surchargeRecipient; // Fastlane surcharge recipient
    address public pendingSurchargeRecipient; // For 2-step transfer process

    // Atlas SafetyLocks (transient storage)
    address public lock; // transient storage
    uint256 internal _solverLock; // transient storage
    uint256 public claims; // transient storage
    uint256 public withdrawals; // transient storage
    uint256 public deposits; // transient storage

    uint256 internal _solverCalledBack = 1 << 161;
    uint256 internal _solverFulfilled = 1 << 162;

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
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Gas Accounting
        // Initialized with msg.value to seed flash loan liquidity
        surcharge = msg.value;
        surchargeRecipient = _surchargeRecipient;

        // Gas Accounting - transient storage (delete this from constructor post dencun)
        lock = UNLOCKED;
        _solverLock = _UNLOCKED_UINT;
        claims = type(uint256).max;
        withdrawals = type(uint256).max;
        deposits = type(uint256).max;

        emit SurchargeRecipientTransferred(_surchargeRecipient);
    }

    function solverLockData() public view returns (address currentSolver, bool verified, bool fulfilled) {
        uint256 solverLock = _solverLock;
        currentSolver = address(uint160(solverLock));
        verified = solverLock & _solverCalledBack != 0;
        fulfilled = solverLock & _solverFulfilled != 0;
    }

    function solver() public view returns (address) {
        return address(uint160(_solverLock));
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) { }
}
