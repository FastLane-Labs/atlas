// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import "../types/EscrowTypes.sol";
import { Permit69 } from "../common/Permit69.sol";

import "forge-std/Test.sol";

// TODO split out events and errors to share with AtlasEscrow

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
        address _simulator
    )
        Permit69(_escrowDuration, _factory, _verification, _simulator)
    { }

    /*//////////////////////////////////////////////////////////////
                                ATLETH
    //////////////////////////////////////////////////////////////*/

    function accountLastActiveBlock(address account) external view returns (uint256) {
        return uint256(accessData[account].lastAccessedBlock);
    }

    // TODO
    // Other views needed:
    // - bonded balance
    // - unbonding balance
    // - time left until unbonded

    function balanceOf(address account) public view returns (uint256) {
        EscrowAccountBalance memory accountBalance = _balanceOf[account];
        return uint256(accountBalance.total - accountBalance.bonded);
    }

    // Deposit ETH and get atlETH in return.
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    // Puts a "hold" on a solver's AtlETH, enabling it to be used in Atlas transactions
    // Bonded AtlETH must first be unbonded to become transferrable or withdrawable
    function bond(uint256 amount) external {
        _bond(msg.sender, amount);
    }

    // Deposits the sender's full msg.value and converts to AtlETH
    // Then bonds the sender's amountToBond of AtlETH
    function depositAndBond(uint256 amountToBond) external payable {
        _mint(msg.sender, msg.value);
        _bond(msg.sender, amountToBond);
    }

    // Starts the unbonding wait time.
    // Unbonding AtlETH can still be used be solvers while unbonding,
    // but adjustments may be made at withdrawal to ensure solvency
    function unbond(uint256 amount) external returns (uint256 unbondCompleteBlock) {
        _checkIfUnlocked();

        EscrowAccountBalance memory accountBalance = _balanceOf[msg.sender];
        EscrowAccountAccessData memory _accessData = accessData[msg.sender];

        _accessData.lastAccessedBlock = uint64(block.number);
        _accessData.unbondingBalance += uint128(amount);

        // The new withdrawAmount should not exceed the solver's holds balance
        if (accountBalance.bonded < _accessData.unbondingBalance) {
            revert InsufficientBondedBalance({ balance: accountBalance.bonded, requested: amount });
        }

        accessData[msg.sender] = _accessData;

        return block.number + ESCROW_DURATION;
    }

    function withdraw(uint256 amount) external {
        _checkIfUnlocked();
        _checkEscrowPeriodHasPassed(msg.sender);

        // Amount may be adjusted down if solver does not hold enough AtlETH
        amount = _withdrawAccounting(amount, msg.sender);

        emit Transfer(msg.sender, address(0), amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function withdrawSurcharge(uint256 amount) external {
        _checkIfUnlocked();

        if (surcharge < amount) revert InsufficientSurchargeBalance({ balance: surcharge, requested: amount });

        unchecked {
            surcharge -= amount;
        }

        // NOTE: Surcharges are not deducted from totalSupply.
        _balanceOf[address(0xa7145)].total += uint128(amount);
    }

    function _bond(address account, uint256 amount) internal {
        EscrowAccountBalance memory accountBalance = _balanceOf[account];
        if (accountBalance.total - accountBalance.bonded < amount) {
            revert InsufficientUnbondedBalance({
                balance: accountBalance.total - accountBalance.bonded,
                requested: amount
            });
        }
        accountBalance.bonded += uint128(amount);
        _balanceOf[account] = accountBalance;
    }

    // Returns the allowed withdrawal amount which may be <= the requested amount param
    function _withdrawAccounting(uint256 amount, address spender) internal returns (uint256) {
        EscrowAccountAccessData memory _accessData = accessData[spender];
        EscrowAccountBalance memory accountBalance = _balanceOf[spender];

        uint128 _amount = uint128(amount);
        uint128 unlockedBalance = accountBalance.total - accountBalance.bonded;
        _accessData.lastAccessedBlock = uint64(block.number);

        if (_accessData.unbondingBalance + unlockedBalance < _amount) {
            revert InsufficientWithdrawableBalance({ balance: _accessData.unbondingBalance, requested: amount });
        }

        // SAFE: When holds >= withdrawalAmount, we can safely withdraw the full amount
        // UNSAFE: When holds < withdrawalAmount, we must make adjustments to ensure solvency
        if (_accessData.unbondingBalance > accountBalance.bonded) {
            // UNSAFE: When holds < withdrawalAmount, we must make adjustments to ensure solvency
            if (_accessData.unbondingBalance > accountBalance.total) {
                // If withdrawAmount > all of solver's AtlETH, adjust withdrawAmount down
                _accessData.unbondingBalance = accountBalance.total;
                _amount = accountBalance.total;
            }
            // In all unsafe cases, holds must be adjusted up to match withdrawalAmount
            accountBalance.bonded = _accessData.unbondingBalance;
        }

        // First withdraw from unlocked balance
        // Here, holds = max(bonded, withdrawalAmount)
        unlockedBalance = accountBalance.total - accountBalance.bonded;
        accountBalance.total -= _amount;

        // After withdrawing all unlocked balance, take the rest from holds and withdrawalAmount
        if (_amount > unlockedBalance) {
            _accessData.unbondingBalance -= _amount - unlockedBalance;
            accountBalance.bonded -= _amount - unlockedBalance;
        }

        accessData[spender] = _accessData;
        _balanceOf[spender] = accountBalance;

        totalSupply -= _amount;

        return amount;
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    // NOTE: This transfer func would be problematic if it pulled from a withdraw rather than a redeem
    // E.G.  start the withdrawal in advance. This would prevent searchers from xfering their escrowed gas in the same
    // block, but in front of their own searcher ops.
    function transfer(address to, uint256 amount) public returns (bool) {
        EscrowAccountAccessData memory _accessData = accessData[msg.sender];
        EscrowAccountBalance memory accountBalance = _balanceOf[msg.sender];

        // Only allowed to transfer AtlETH that is not bonded or unbonding
        uint128 maxUnavailable =
            accountBalance.bonded >= _accessData.unbondingBalance ? accountBalance.bonded : _accessData.unbondingBalance;
        if (amount > accountBalance.total - maxUnavailable) {
            revert InsufficientAvailableBalance({ balance: accountBalance.total - maxUnavailable, requested: amount });
        }

        _balanceOf[msg.sender].total -= uint128(amount);
        _balanceOf[to].total += uint128(amount);

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        EscrowAccountAccessData memory _accessData = accessData[from];
        EscrowAccountBalance memory accountBalance = _balanceOf[from];

        // Only allowed to transfer AtlETH that is not bonded or unbonding
        uint128 maxUnavailable =
            accountBalance.bonded >= _accessData.unbondingBalance ? accountBalance.bonded : _accessData.unbondingBalance;
        if (amount > accountBalance.total - maxUnavailable) {
            revert InsufficientAvailableBalance({ balance: accountBalance.total - maxUnavailable, requested: amount });
        }

        _balanceOf[from].total -= uint128(amount);
        _balanceOf[to].total += uint128(amount);

        emit Transfer(from, to, amount);
        return true;
    }

    /*
    // TODO: Readd permit but w/ custom safety checks. 
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
    {
        if (deadline < block.timestamp) revert PermitDeadlineExpired();
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
            if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSigner();
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
    */

    // Custom checks for atlETH transfer functions.
    // Interactions (transfers, withdrawals) are allowed only after the owner last interaction
    // with Atlas was at least `escrowDuration` blocks ago.
    function _checkEscrowPeriodHasPassed(address account) internal view {
        if (block.number < accessData[account].lastAccessedBlock + ESCROW_DURATION) {
            revert EscrowLockActive();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;

        _balanceOf[to].total += uint128(amount);

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        _balanceOf[from].total -= uint128(amount);
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
