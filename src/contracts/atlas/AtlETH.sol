// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.22;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { Permit69 } from "src/contracts/common/Permit69.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";
import "src/contracts/types/EscrowTypes.sol";

/// @notice Modified Solmate ERC20 with some Atlas-specific modifications.
/// @author FastLane Labs
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
abstract contract AtlETH is Permit69 {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor(
        uint256 _escrowDuration,
        AtlasVerification _verification,
        address _simulator,
        address _surchargeRecipient
    )
        Permit69(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    /*//////////////////////////////////////////////////////////////
                                ATLETH
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the unbonded AtlETH balance of the specified account.
    /// @param account The address for which to query the unbonded AtlETH balance.
    /// @return The unbonded AtlETH balance of the specified account.
    function balanceOf(address account) external view returns (uint256) {
        return uint256(_balanceOf[account].balance);
    }

    /// @notice Returns the bonded AtlETH balance of the specified account.
    /// @param account The address for which to query the bonded AtlETH balance.
    /// @return The bonded AtlETH balance of the specified account.
    function balanceOfBonded(address account) external view returns (uint256) {
        return uint256(accessData[account].bonded);
    }

    /// @notice Returns the unbonding AtlETH balance of the specified account.
    /// @param account The address for which to query the unbonding AtlETH balance.
    /// @return The unbonding AtlETH balance of the specified account.
    function balanceOfUnbonding(address account) external view returns (uint256) {
        return uint256(_balanceOf[account].unbonding);
    }

    /// @notice Returns the last active block of the specified account in the escrow contract.
    /// @param account The address for which to query the last active block.
    /// @return The last active block of the specified account in the escrow contract.
    function accountLastActiveBlock(address account) external view returns (uint256) {
        return uint256(accessData[account].lastAccessedBlock);
    }

    /// @notice Returns the block number at which the unbonding process of the specified account will be completed.
    /// @param account The address for which to query the completion block of unbonding.
    /// @return The block number at which the unbonding process of the specified account will be completed.
    function unbondingCompleteBlock(address account) external view returns (uint256) {
        uint256 lastAccessedBlock = uint256(accessData[account].lastAccessedBlock);
        if (lastAccessedBlock == 0) return 0;
        return lastAccessedBlock + ESCROW_DURATION;
    }

    /// @notice Deposits ETH to receive atlETH tokens in return.
    /// @dev Mints atlETH tokens to the caller in exchange for the deposited ETH.
    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    /// @notice Redeems atlETH tokens for ETH.
    /// @dev Burns the specified amount of atlETH tokens from the caller's balance and transfers the equivalent amount
    /// of ETH to the caller.
    /// @param amount The amount of atlETH tokens to redeem for ETH.
    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves the spender to spend a specified amount of tokens on behalf of the caller.
    /// @param spender The address of the account allowed to spend the tokens.
    /// @param amount The amount of tokens the spender is allowed to spend.
    /// @return A boolean indicating whether the approval was successful.
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens from the caller's account to the specified recipient.
    /// @param to The address of the recipient to whom tokens are being transferred.
    /// @param amount The amount of tokens to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transfer(address to, uint256 amount) public returns (bool) {
        _deduct(msg.sender, amount);
        _balanceOf[to].balance += uint112(amount);

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Transfers tokens from one account to another using an allowance mechanism.
    /// @param from The address of the account from which tokens are being transferred.
    /// @param to The address of the recipient to whom tokens are being transferred.
    /// @param amount The amount of tokens to transfer.
    /// @return A boolean indicating whether the transfer was successful.
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        _deduct(from, amount);
        _balanceOf[to].balance += uint112(amount);
        emit Transfer(from, to, amount);
        return true;
    }

    /// @notice Allows a token owner to approve spending a specific amount of tokens by a spender.
    /// @dev This function is part of the EIP-2612 permit extension.
    /// @param owner The address of the token owner granting the approval.
    /// @param spender The address of the spender to whom approval is granted.
    /// @param value The amount of tokens approved for spending.
    /// @param deadline The deadline timestamp after which the permit is considered expired.
    /// @param v The recovery identifier of the permit signature.
    /// @param r The first half of the ECDSA signature of the permit.
    /// @param s The second half of the ECDSA signature of the permit.
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
                        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
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

    /// @notice Computes or reads the stored EIP-712 domain separator for permit signatures.
    /// @return The domain separator bytes32 value.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _INITIAL_CHAIN_ID ? _INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    /// @notice Computes the EIP-712 domain separator for permit signatures.
    /// @return The domain separator bytes32 value.
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

    /// @notice Mints new atlETH tokens and assigns them to the specified account.
    /// @param to The address to which the newly minted atlETH tokens will be assigned.
    /// @param amount The amount of atlETH tokens to mint and assign to the specified account.
    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        _balanceOf[to].balance += SafeCast.toUint112(amount);
        emit Transfer(address(0), to, amount);
    }

    /// @notice Burns atlETH tokens from the specified account.
    /// @param from The address from which the atlETH tokens will be burned.
    /// @param amount The amount of atlETH tokens to burn from the specified account.
    function _burn(address from, uint256 amount) internal {
        _deduct(from, amount);
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    /// @notice Deducts atlETH tokens from the specified account.
    /// @dev This function deducts the specified amount of atlETH tokens from the balance of the specified account.
    /// If the deduction results in a negative balance, it handles the shortfall differently depending on whether the
    /// account has passed the unbonding lock period. If the account has passed the lock period, the shortfall is
    /// considered as unbonding, and the total supply is adjusted accordingly. Otherwise, if the account is still within
    /// the lock period, the function reverts due to insufficient balance for deduction.
    /// @param account The address from which to deduct atlETH tokens.
    /// @param amount The amount of atlETH tokens to deduct from the specified account.
    function _deduct(address account, uint256 amount) internal {
        uint112 amt = SafeCast.toUint112(amount);

        EscrowAccountBalance storage aData = _balanceOf[account];

        uint112 balance = aData.balance;

        if (amt <= balance) {
            _balanceOf[account].balance = balance - amt;
        } else if (block.number > accessData[account].lastAccessedBlock + ESCROW_DURATION) {
            uint112 _shortfall = amt - balance;
            aData.balance = 0;
            aData.unbonding -= _shortfall; // underflow here to revert if insufficient balance

            uint256 shortfall256 = uint256(_shortfall);
            totalSupply += shortfall256; // add the released supply back to atleth.
            bondedTotalSupply -= shortfall256; // subtract the unbonded, freed amount
        } else {
            // Reverts because amount > account's balance
            revert InsufficientBalanceForDeduction(uint256(balance), amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    EXTERNAL BOND/UNBOND LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Puts a "hold" on a solver's AtlETH, enabling it to be used in Atlas transactions.
    /// @dev This function locks the specified amount of AtlETH tokens for the sender, making them bonded.
    /// Bonded AtlETH tokens must first be unbonded before they can be transferred or withdrawn.
    /// @param amount The amount of AtlETH tokens to bond.
    function bond(uint256 amount) external {
        _bond(msg.sender, amount);
    }

    /// @notice Deposits the caller's ETH and mints AtlETH, then bonds a specified amount of that AtlETH.
    /// @param amountToBond The amount of AtlETH tokens to bond after the deposit.
    function depositAndBond(uint256 amountToBond) external payable {
        _mint(msg.sender, msg.value);
        _bond(msg.sender, amountToBond);
    }

    /// @notice Starts the unbonding wait time for the specified amount of AtlETH tokens.
    /// @dev This function initiates the unbonding process for the specified amount of AtlETH tokens
    /// held by the sender. Unbonding AtlETH tokens can still be used by solvers while the unbonding
    /// process is ongoing, but adjustments may be made at withdrawal to ensure solvency.
    /// @param amount The amount of AtlETH tokens to unbond.
    function unbond(uint256 amount) external {
        _unbond(msg.sender, amount);
    }

    /// @notice Redeems the specified amount of AtlETH tokens for withdrawal.
    /// @param amount The amount of AtlETH tokens to redeem for withdrawal.
    function redeem(uint256 amount) external {
        _redeem(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL BOND/UNBOND LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Puts a hold on a solver's AtlETH tokens, enabling them to be used in Atlas transactions.
    /// @dev This internal function puts a hold on a solver's AtlETH tokens, enabling them to be used
    /// in Atlas transactions. The specified amount of AtlETH tokens is deducted from the owner's balance
    /// and added to the bonded balance. The total supply and bonded total supply are updated accordingly.
    /// @param owner The address of the account to put a hold on AtlETH tokens for.
    /// @param amount The amount of AtlETH tokens to put a hold on.
    function _bond(address owner, uint256 amount) internal {
        uint112 amt = SafeCast.toUint112(amount);

        _balanceOf[owner].balance -= amt;
        totalSupply -= amount;

        accessData[owner].bonded += amt;
        bondedTotalSupply += amount;

        emit Bond(owner, amount);
    }

    /// @notice Starts the unbonding wait time for a specified amount of AtlETH tokens.
    /// @dev This internal function starts the unbonding wait time for a specified amount of AtlETH tokens.
    /// The specified amount of AtlETH tokens is deducted from the owner's bonded balance and added to the
    /// unbonding balance. The last accessed block for the owner is updated to the current block number.
    /// @param owner The address of the account to start the unbonding wait time for.
    /// @param amount The amount of AtlETH tokens to start the unbonding wait time for.
    function _unbond(address owner, uint256 amount) internal {
        uint112 amt = SafeCast.toUint112(amount);

        // totalSupply and totalBondedSupply are unaffected; continue to count the
        // unbonding amount as bonded total supply since it is still inaccessible
        // for atomic xfer.

        EscrowAccountAccessData storage aData = accessData[owner];

        aData.bonded -= amt;
        aData.lastAccessedBlock = uint32(block.number);

        _balanceOf[owner].unbonding += amt;

        emit Unbond(owner, amount, block.number + ESCROW_DURATION + 1);
    }

    /// @notice Redeems the specified amount of AtlETH tokens for withdrawal.
    /// @dev This function allows the owner to redeem a specified amount of AtlETH tokens
    /// for withdrawal. If the unbonding process is active for the specified account, the
    /// function will revert. Otherwise, the specified amount of AtlETH tokens will be added
    /// back to the account's balance, and the total supply will be updated accordingly.
    /// @param owner The address of the account redeeming AtlETH tokens for withdrawal.
    /// @param amount The amount of AtlETH tokens to redeem for withdrawal.
    function _redeem(address owner, uint256 amount) internal {
        if (block.number <= uint256(accessData[owner].lastAccessedBlock) + ESCROW_DURATION) {
            revert EscrowLockActive();
        }

        uint112 amt = SafeCast.toUint112(amount);

        EscrowAccountBalance storage bData = _balanceOf[owner];

        bData.unbonding -= amt;
        bondedTotalSupply -= amount;

        bData.balance += amt;
        totalSupply += amount;

        emit Redeem(owner, amount);
    }

    /// @notice Allows the current surcharge recipient to withdraw the accumulated surcharge. NOTE: If the only ETH in
    /// Atlas is the surcharge, be mindful that withdrawing this ETH may limit solvers' liquidity to flashloan ETH from
    /// Atlas in their solverOps.
    /// @dev This function can only be called by the current surcharge recipient.
    /// It transfers the accumulated surcharge amount to the surcharge recipient's address.
    function withdrawSurcharge() external {
        if (msg.sender != surchargeRecipient) {
            revert InvalidAccess();
        }

        uint256 paymentAmount = cumulativeSurcharge;
        cumulativeSurcharge = 0; // Clear before transfer to prevent reentrancy
        SafeTransferLib.safeTransferETH(msg.sender, paymentAmount);
        emit SurchargeWithdrawn(msg.sender, paymentAmount);
    }

    /// @notice Starts the transfer of the surcharge recipient designation to a new address.
    /// @dev This function can only be called by the current surcharge recipient.
    /// It sets the `pendingSurchargeRecipient` to the specified `newRecipient` address,
    /// allowing the new recipient to claim the surcharge recipient designation by calling `becomeSurchargeRecipient`.
    /// If the caller is not the current surcharge recipient, it reverts with an `InvalidAccess` error.
    /// @param newRecipient The address of the new surcharge recipient.
    function transferSurchargeRecipient(address newRecipient) external {
        if (msg.sender != surchargeRecipient) {
            revert InvalidAccess();
        }

        pendingSurchargeRecipient = newRecipient;
        emit SurchargeRecipientTransferStarted(surchargeRecipient, newRecipient);
    }

    /// @notice Finalizes the transfer of the surcharge recipient designation to a new address.
    /// @dev This function can only be called by the pending surcharge recipient,
    /// and it completes the transfer of the surcharge recipient designation to the address
    /// stored in `pendingSurchargeRecipient`.
    /// If the caller is not the pending surcharge recipient, it reverts with an `InvalidAccess` error.
    function becomeSurchargeRecipient() external {
        if (msg.sender != pendingSurchargeRecipient) {
            revert InvalidAccess();
        }

        surchargeRecipient = msg.sender;
        pendingSurchargeRecipient = address(0);
        emit SurchargeRecipientTransferred(msg.sender);
    }
}
