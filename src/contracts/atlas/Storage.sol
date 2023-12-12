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
    address public immutable BOATLETH;
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
    mapping(address => EscrowAccountAccessData) public accessData;

    // Gas Accounting constants
    uint256 public constant SURCHARGE_BASE = 100;
    uint256 public constant SURCHARGE = 10;
    address public constant SOLVER_FULFILLED = address(2);

    // Atlas GasAccounting storage
    // NOTE: these storage vars / maps should only be accessible by *signed* solver transactions
    // and only once per solver per block (to avoid user-solver collaborative exploits)
    // uint256 public immutable escrowDuration;
    mapping(address => EscrowAccountBalance) internal _balanceOf;

    uint256 public surcharge; // Atlas gas surcharges

    // Atlas SafetyLocks (transient storage)
    address public lock; // transient storage
    address public solver; // transient storage
    uint256 public claims; // transient storage
    //uint256 public reimbursements; // transient storage
    uint256 public withdrawals; // transient storage
    uint256 public deposits; // transient storage

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _boAtlETH,
        address _simulator
    )
        payable
    {
        ESCROW_DURATION = _escrowDuration;
        FACTORY = _factory;
        VERIFICATION = _verification;
        BOATLETH = _boAtlETH;
        SIMULATOR = _simulator;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();

        // Gas Accounting
        surcharge = msg.value;

        // Gas Accounting - transient storage (delete this from constructor post dencun)
        lock = UNLOCKED;
        solver = UNLOCKED;
        claims = type(uint256).max;
        withdrawals = type(uint256).max;
        deposits = type(uint256).max;
    }

    function _computeDomainSeparator() internal view virtual returns (bytes32) { }
}
