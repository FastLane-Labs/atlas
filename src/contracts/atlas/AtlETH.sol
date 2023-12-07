// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import "../types/EscrowTypes.sol";
import { Permit69 } from "../common/Permit69.sol";

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
        return uint256(nonces[account].lastAccessed);
    }

    function balanceOf(address account) public view returns (uint256) {
        EscrowAccountData memory accountData = _balanceOf[account];
        return uint256(accountData.balance - accountData.holds);
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
    // Then bonds the given amountToBond
    function depositAndBond(uint256 amountToBond) external payable {
        _mint(msg.sender, msg.value);
        _bond(msg.sender, amountToBond);
    }

    function _bond(address account, uint256 amount) internal {
        EscrowAccountData memory accountData = _balanceOf[account];
        if (accountData.balance - accountData.holds < amount) revert InsufficientUnbondedBalance();
        accountData.holds += uint128(amount);
        _balanceOf[account] = accountData;
    }

    function unbond() external { }

    // Redeem atlETH for ETH.
    function redeem(uint256 amount) external {
        _checkIfUnlocked();
        _checkTransfersAllowed(msg.sender);

        EscrowAccountData memory accountData = _balanceOf[msg.sender];

        uint128 _amount = uint128(amount);

        if (accountData.balance - accountData.holds < _amount) revert InsufficientUnbondedBalance();

        EscrowNonce memory nonceData = nonces[msg.sender];

        nonceData.lastAccessed = uint64(block.number);
        nonceData.withdrawalAmount += _amount;
        accountData.holds += _amount;

        nonces[msg.sender] = nonceData;
        _balanceOf[msg.sender] = accountData;
    }

    function withdraw(uint256 amount) external {
        _checkIfUnlocked();
        _checkTransfersAllowed(msg.sender);

        _withdrawAccounting(amount, msg.sender);

        emit Transfer(msg.sender, address(0), amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function withdrawSurcharge(uint256 amount) external {
        _checkIfUnlocked();

        if (surcharge < amount) revert InsufficientSurchargeBalance(surcharge, amount);

        unchecked {
            surcharge -= amount;
        }

        // NOTE: Surcharges are not deducted from totalSupply.
        _balanceOf[address(0xa7145)].balance += uint128(amount);
    }

    function _withdrawAccounting(uint256 amount, address spender) internal {
        EscrowNonce memory nonceData = nonces[spender];
        EscrowAccountData memory accountData = _balanceOf[spender];

        uint128 _amount = uint128(amount);

        if (nonceData.withdrawalAmount < _amount) {
            revert InsufficientRedeemedBalance(uint256(nonceData.withdrawalAmount), amount);
        }
        if (accountData.balance < _amount) revert InsufficientAvailableBalance(uint256(accountData.balance), amount);

        nonceData.lastAccessed = uint64(block.number);
        nonceData.withdrawalAmount -= _amount;

        accountData.balance -= _amount;
        accountData.holds = _amount > accountData.holds ? 0 : accountData.holds - _amount;

        nonces[spender] = nonceData;
        _balanceOf[spender] = accountData;

        unchecked {
            totalSupply -= amount;
        }
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
        _checkTransfersAllowed(msg.sender);

        _withdrawAccounting(amount, msg.sender);

        _balanceOf[to].balance += uint128(amount);

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _checkTransfersAllowed(from);

        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        _withdrawAccounting(amount, from);

        _balanceOf[to].balance += uint128(amount);

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
    function _checkTransfersAllowed(address account) internal view {
        if (block.number < nonces[account].lastAccessed + ESCROW_DURATION) {
            revert EscrowLockActive();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;

        _balanceOf[to].balance += uint128(amount);

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        _balanceOf[from].balance -= uint128(amount);
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }
}
