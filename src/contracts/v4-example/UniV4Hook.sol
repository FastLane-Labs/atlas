//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// V4 Imports
import {IPoolManager} from "./IPoolManager.sol";
import {IHooks} from "./IHooks.sol";

// Atlas Imports
import {V4ProtocolControl} from "./V4ProtocolControl.sol";

import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {SafetyBits} from "../libraries/SafetyBits.sol";

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

// NOTE: Uniswap V4 is unique in that it would not require a frontend integration.
// Instead, hooks can be used to enforce that the proceeds of the MEV auctions are
// sent wherever the hook creators wish.  In this example, the MEV auction proceeds
// are donated back to the pool.


    /////////////////////////////////////////////////////////
    //                      V4 HOOK                        //
    /////////////////////////////////////////////////////////

contract UniV4Hook is V4ProtocolControl {

    constructor(address _escrow, address _v4Singleton) V4ProtocolControl(_escrow, _v4Singleton) {}
    
    function getHooksCalls() public pure returns (IHooks.Calls memory) {
        // override
        return IHooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true, // <--
            afterModifyPosition: false,
            beforeSwap: true, // <--
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function beforeModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        virtual
        returns (bytes4)
    {
        // TODO: Hook must own ALL liquidity.  
        // Users can withdraw liquidity through Hook rather than through the pool itself
    }

    function beforeSwap(address sender, IPoolManager.PoolKey calldata key, IPoolManager.SwapParams calldata)
        external
        view
        returns (bytes4)
    {
        // This function is a standard call
        // address(this) = hook
        // msg.sender = v4Singleton

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that ProtocolControl supplied a valid signature
        require(address(this) == hook, "ERR-H00 InvalidCallee");
        require(msg.sender == v4Singleton, "ERR-H01 InvalidCaller"); // TODO: Confirm this

        EscrowKey memory escrowKey = ISafetyLocks(escrow).getLockState();

        // Case:
        // User call
        if (escrowKey.lockState == SafetyBits._LOCKED_X_USER_X_UNSET) {
            // Sender = ExecutionEnvironment

            // Verify that the pool is valid for the user to trade in.
            require(keccak256(abi.encode(key, sender)) == hashLock, "ERR-H02 InvalidSwapper");

            // Case:
            // Searcher call
        } else if (escrowKey.lockState == SafetyBits._LOCKED_X_SEARCHERS_X_VERIFIED) {
            // Sender = Searcher contract
            // NOTE: This lockState verifies that the user's transaction has already
            // been executed.
            // NOTE: Searchers must have triggered the safetyCallback on the ExecutionEnvironment
            // *before* swapping.  The safetyCallback sets the ExecutionEnvironment as the
            // escrowKey.approvedCaller.

            // Verify that the pool is valid for a searcher to trade in.
            require(hashLock == keccak256(abi.encode(key, escrowKey.approvedCaller)), "ERR-H04 InvalidPoolKey");

            // Case:
            // Other call
        } else {
            // Determine if the sequenced order was processed earlier in the block
            bytes32 sequenceKey = keccak256(
                abi.encodePacked(
                    IPoolManager.Currency.unwrap(key.currency0),
                    IPoolManager.Currency.unwrap(key.currency1),
                    block.number
                )
            );

            if (!sequenceLock[sequenceKey]) {
                // TODO: Add in ability to "cache" the unsequenced transaction in storage.
                // Currently, Uni V4 will either fully execute the trade or throw a revert,
                // undoing any SSTORE made by the hook.
                revert("ERR-H02 InvalidLockStage");
            }
        }

        // NOTE: Searchers attempting to backrun in this pool will easily be able to precompute
        // the hashLock's value. It should not be used as a lock to keep them out - it is only
        // meant to prevent searchers from winning an auction for Pool X but trading in Pool Y.

        return UniV4Hook.beforeSwap.selector;
    }
}
