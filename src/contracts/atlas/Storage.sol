//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import "../types/EscrowTypes.sol";
import "../types/LockTypes.sol";

contract Storage {
    // Atlas constants
    uint256 internal constant _MAX_GAS = 1_500_000;
    uint256 internal constant LEDGER_LENGTH = 6; // type(Party).max = 6
    address internal constant UNLOCKED = address(1);

    uint256 public immutable ESCROW_DURATION;
    address public immutable FACTORY;
    address public immutable VERIFICATION;
    address public immutable GAS_ACC_LIB;
    address public immutable SAFETY_LOCKS_LIB;
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
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => EscrowNonce) public nonces;

    // Atlas GasAccounting storage
    // NOTE: these storage vars / maps should only be accessible by *signed* solver transactions
    // and only once per solver per block (to avoid user-solver collaborative exploits)
    // uint256 public immutable escrowDuration;
    mapping(address => uint256) public balanceOf;
    // mapping(address => uint256) internal _escrowAccountData;

    address public constant INACTIVE = address(1);
    address public constant SOLVER_PROXY = address(2);

    // Atlas SafetyLocks storage
    Lock public lock; // transient storage
    mapping(address => Ledger) public ledgers; // transient storage
    address[LEDGER_LENGTH] public parties; // transient storage

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _safetyLocksLib,
        address _simulator
    ) {
        ESCROW_DURATION = _escrowDuration;
        FACTORY = _factory;
        VERIFICATION = _verification;
        GAS_ACC_LIB = _gasAccLib;
        SAFETY_LOCKS_LIB = _safetyLocksLib;
        SIMULATOR = _simulator;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
        lock = Lock({ activeEnvironment: UNLOCKED, activeParties: uint16(0), startingBalance: uint64(0) });

        for (uint256 i; i < LEDGER_LENGTH; i++) {
            // init the storage vars
            ledgers[i] = INACTIVE;
        }
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) { }
}
