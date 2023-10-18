// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.19;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import "../types/EscrowTypes.sol";
import {Permit69} from "../common/Permit69.sol";

// TODO split out events and errors to share with AtlasEscrow
// TODO all modifiers should be internal fns for contract size savings

/// @notice Modified Solmate ERC20 with some Atlas-specific modifications.
/// @author FastLane Labs
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract AtlETH is Permit69 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public constant name = "Atlas ETH";
    string public constant symbol = "atlETH";
    uint8 public constant decimals = 18;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf; 
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    /*//////////////////////////////////////////////////////////////
                            ATLAS STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public immutable escrowDuration;
    mapping(address => SolverEscrow) internal _escrowData;

    // NOTE: these storage vars / maps should only be accessible by *signed* solver transactions
    // and only once per solver per block (to avoid user-solver collaborative exploits)
    // EOA Address => solver escrow data

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _escrowDuration, address _simulator) Permit69(_simulator)  {
        escrowDuration = _escrowDuration;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                                ATLETH
    //////////////////////////////////////////////////////////////*/

    // Restricts ERC20 actions to after escrow period has passed
    modifier checkEscrowDuration(address owner) {
        require(block.number >= uint256(_escrowData[owner].lastAccessed) + uint256(escrowDuration), "ERR-E080 TooEarly");
        _;
    }

    // TODO adapt these fns to new contract structure

    // Deposit ETH and get atlETH in return.
    function deposit() external payable onlyWhenUnlocked{
        _mint(msg.sender, msg.value);
    }

    // Redeem atlETH for ETH.
    function withdraw(uint256 amount)
        external
        onlyWhenUnlocked
        checkEscrowDuration(msg.sender)
        returns (uint256 newBalance)
    {
        require(balanceOf[msg.sender] >= amount, "ERR-E078 InsufficientBalance");
        _burn(msg.sender, amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
        newBalance = balanceOf[msg.sender];
    }

    function nextSolverNonce(address solverSigner) external view returns (uint256 nextNonce) {
        nextNonce = uint256(_escrowData[solverSigner].nonce) + 1;
    }

    function solverLastActiveBlock(address solverSigner) external view returns (uint256 lastBlock) {
        lastBlock = uint256(_escrowData[solverSigner].lastAccessed);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public checkEscrowDuration(msg.sender) returns (bool) {
        balanceOf[msg.sender] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public checkEscrowDuration(from) returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public  {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
            allowance[recoveredAddress][spender] = value;
        }
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view  returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view  returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal  {
        totalSupply += amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal  {
        balanceOf[from] -= amount;
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
