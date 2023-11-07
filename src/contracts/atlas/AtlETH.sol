// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

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
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 _escrowDuration,
        address _factory,
        address _verification,
        address _gasAccLib,
        address _simulator
    ) Permit69(_escrowDuration, _factory, _verification, _gasAccLib, _simulator) {}

    /*//////////////////////////////////////////////////////////////
                                ATLETH
    //////////////////////////////////////////////////////////////*/

    // Custom checks for atlETH transfer functions.
    // Interactions (transfers, withdrawals) are allowed only after the owner last interaction
    // with Atlas was at least `escrowDuration` blocks ago.
    modifier tokenTransferChecks(address account) {
        if(block.number <= _escrowAccountData[account].lastAccessed + ESCROW_DURATION) {
            revert EscrowLockActive();
        }
        _;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _escrowAccountData[account].balance;
    }

    function nextAccountNonce(address account) external view returns (uint256 nextNonce) {
        nextNonce = uint256(_escrowAccountData[account].nonce) + 1;
    }

    function accountLastActiveBlock(address account) external view returns (uint256 lastBlock) {
        lastBlock = uint256(_escrowAccountData[account].lastAccessed);
    }

    // Deposit ETH and get atlETH in return.
    function deposit() external payable onlyWhenUnlocked {
        _mint(msg.sender, msg.value);
    }

    // Redeem atlETH for ETH.
    function withdraw(uint256 amount) external onlyWhenUnlocked tokenTransferChecks(msg.sender) {
        if (_escrowAccountData[msg.sender].balance < amount) revert InsufficientBalance();
        _burn(msg.sender, amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public tokenTransferChecks(msg.sender) returns (bool) {
        _escrowAccountData[msg.sender].balance -= uint128(amount);
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _escrowAccountData[to].balance += uint128(amount);
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public tokenTransferChecks(from) returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _escrowAccountData[from].balance -= uint128(amount);
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _escrowAccountData[to].balance += uint128(amount);
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        if(deadline < block.timestamp) revert PermitDeadlineExpired();
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
            if(recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSigner();
            allowance[recoveredAddress][spender] = value;
        }
        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view override returns (bytes32) {
        return keccak256(
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

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            _escrowAccountData[to].balance += uint128(amount);
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        _escrowAccountData[from].balance -= uint128(amount);
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
