//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// V4 Imports
// import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
// import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
// import {BaseHook} from "@uniswap/periphery-next/contracts/BaseHook.sol";

// Atlas Base Imports
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol"; 

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

// Atlas Protocol-Control Imports
import { ProtocolControl } from "../protocol/ProtocolControl.sol";
import { MEVAllocator } from "../protocol/MEVAllocator.sol";


interface IPoolManager {
    type Currency is address;
    type BalanceDelta is int256;

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
    struct PoolKey {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        IHooks hooks;
    }
    
    function swap(PoolKey memory key, SwapParams memory params) external returns (BalanceDelta);
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1) external returns (BalanceDelta);
}

interface IHooks {
    function beforeSwap(
        address sender, 
        IPoolManager.PoolKey calldata key, 
        IPoolManager.SwapParams calldata params
    ) external returns (bytes4);

    struct Calls {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
    }
}

// NOTE: Uniswap V4 is unique in that it would not require a frontend integration.
// Instead, hooks can be used to enforce that the proceeds of the MEV auctions are 
// sent wherever the hook creators wish.  In this example, the MEV auction proceeds 
// are donated back to the pool. 

contract AtlasV4Hook is MEVAllocator, ProtocolControl {

    struct StagingReturn {
        address approvedToken;
        IPoolManager.PoolKey poolKey;
    }

    bytes4 public constant SWAP = IPoolManager.swap.selector;
    address public immutable hook;
    address public immutable v4Singleton;

    // Storage lock
    bytes32 public hashLock; // keccak256(poolKey, executionEnvironment)

    // Map to track when "Non Adversarial" flow is allowed.
    // NOTE: This hook is meant to be used for multiple pairs
    // key: keccak(token0, token1, block.number)
    mapping(bytes32 => bool) public sequenceLock;

    constructor(
        address _escrow,
        address _v4Singleton
    ) 
    MEVAllocator() 
    ProtocolControl(
        _escrow,
        msg.sender,
        true,
        true,
        true,
        false,
        false,
        true, 
        true,
        true, 
        false 
    ) {
        /*
        ProtocolControl(
            _escrow, // escrowAddress
            true, // shouldRequireSequencedNonces
            true, // shouldRequireStaging
            true, // shouldDelegateStaging
            false, // shouldExecuteUserLocally
            false, // shouldDelegateUser
            true, // shouldDelegateAllocating
            true, // shouldRequireVerification
            true, // shouldDelegateVerification
            false // allowRecycledStorage
        )
        */ 

        hook = address(this);
        v4Singleton = _v4Singleton;
    }

      /////////////////////////////////////////////////////////
     //                   ATLAS CALLS                       //
    /////////////////////////////////////////////////////////

    /////////////// DELEGATED CALLS //////////////////
    function _stageDelegateCall(
        bytes calldata data
    ) internal override returns (bytes memory stagingData) {
        // This function is delegatecalled 
        // address(this) = ExecutionEnvironment
        // msg.sender = Atlas Escrow

        // TODO: Finalize UserCall struct and hardcode the location
        // of the func selector.
        require(bytes4(data[4:8]) == SWAP, "ERR-H10 InvalidFunction"); 
       
        UserCall memory userCall = abi.decode(data[4:], (UserCall));

        require(userCall.to == v4Singleton, "ERR-H11 InvalidTo");

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that ProtocolControl supplied a valid signature
        require(msg.sender == escrow, "ERR-H00 InvalidCaller");

        (
            IPoolManager.PoolKey memory key, 
            IPoolManager.SwapParams memory params
        ) = abi.decode(userCall.data, (IPoolManager.PoolKey, IPoolManager.SwapParams));

        // Perform more checks and activate the lock
        AtlasV4Hook(hook).setLock(key);

        // Handle forwarding of token approvals, or token transfers. 
        // NOTE: The user will have approved the ExecutionEnvironment in a prior call
        StagingReturn memory stagingReturn = StagingReturn({
            approvedToken: (
                params.zeroForOne ? 
                IPoolManager.Currency.unwrap(key.currency0) : 
                IPoolManager.Currency.unwrap(key.currency1) 
            ),
            poolKey: key
        });

        // TODO: Determine if optimistic transfers are possible
        // (An example)
        if (params.zeroForOne) {
            if (params.amountSpecified > 0) {
                // Buying Pool's token1 with amountSpecified of User's token0
                // ERC20(token0).approve(v4Singleton, amountSpecified);
                SafeTransferLib.safeTransferFrom(
                    ERC20(IPoolManager.Currency.unwrap(key.currency0)), 
                    userCall.from, 
                    v4Singleton, // <- TODO: confirm
                    uint256(params.amountSpecified)
                );
            
            } else {
                // Buying amountSpecified of Pool's token1 with User's token0

            }
        
        } else {
            if (params.amountSpecified > 0) {
                // Buying Pool's token0 with amountSpecified of User's token1
            
            } else {
                // Buying amountSpecified of Pool's token0 with User's token1

            }
        }

        // Return value
        stagingData = abi.encode(stagingReturn);
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingDelegateCall(
        bytes calldata data
    ) internal override {
        // This function is delegatecalled 
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // Pull the calldata into memory
        (
            ,
            BidData[] memory bids,
            PayeeData[] memory payeeData
        ) = abi.decode(data, (uint256, BidData[], PayeeData[]));

        // NOTE: ProtocolVerifier has verified the PayeeData[] and BidData[] format
        // BidData[0] = token0
        // BidData[1] = token1

        uint256 token0DonateAmount = bids[0].bidAmount * payeeData[0].payments[0].payeePercent / 100;
        uint256 token1DonateAmount = bids[1].bidAmount * payeeData[1].payments[0].payeePercent / 100;

        IPoolManager.PoolKey memory key = abi.decode(payeeData[0].data, (IPoolManager.PoolKey));

        IPoolManager(v4Singleton).donate(key, token0DonateAmount, token1DonateAmount);

        // Flag the pool to be open for trading for the remainder of the block
        bytes32 sequenceKey = keccak256(
            abi.encodePacked(
                IPoolManager.Currency.unwrap(key.currency0), 
                IPoolManager.Currency.unwrap(key.currency1),
                block.number
            )
        );

        sequenceLock[sequenceKey] = true;
    }

    function _verificationDelegateCall(
        bytes calldata data
    ) internal override returns (bool) {
        // This function is delegatecalled 
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow
       
        (
            bytes memory stagingReturnData,
            //bytes memory userReturnData
        ) = abi.decode( 
            data, 
            (bytes, bytes)
        );

        StagingReturn memory stagingReturn = abi.decode(
            stagingReturnData,
            (StagingReturn)
        );

        AtlasV4Hook(hook).releaseLock(stagingReturn.poolKey);

        return true;
    }

    /////////////// EXTERNAL CALLS //////////////////
    function setLock(IPoolManager.PoolKey memory key) external {
        // This function is a standard call 
        // address(this) = hook
        // msg.sender = ExecutionEnvironment

        EscrowKey memory escrowKey = ISafetyLocks(escrow).getLockState();

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that ProtocolControl supplied a valid signature
        require(address(this) == hook, "ERR-H00 InvalidCallee");
        require(hook == escrowKey.approvedCaller, "ERR-H01 InvalidCaller");
        require(escrowKey.lockState == SafetyBits._LOCKED_X_STAGING_X_UNSET, "ERR-H02 InvalidLockStage");
        require(hashLock == bytes32(0), "ERR-H03 AlreadyActive");

        // Set the storage lock to block reentry / concurrent trading
        hashLock = keccak256(abi.encode(key, msg.sender));
    }

    function releaseLock(IPoolManager.PoolKey memory key) external {
        // This function is a standard call 
        // address(this) = hook
        // msg.sender = ExecutionEnvironment

        EscrowKey memory escrowKey = ISafetyLocks(escrow).getLockState();

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that ProtocolControl supplied a valid signature
        require(address(this) == hook, "ERR-H20 InvalidCallee");
        require(hook == escrowKey.approvedCaller, "ERR-H21 InvalidCaller");
        require(escrowKey.lockState == SafetyBits._LOCKED_X_VERIFICATION_X_UNSET, "ERR-H22 InvalidLockStage");
        require(hashLock == keccak256(abi.encode(key, msg.sender)), "ERR-H23 InvalidKey");

        // Release the storage lock 
        delete hashLock;
    }

    ///////////////// GETTERS & HELPERS // //////////////////
    function getPayeeData(
        bytes calldata data
    ) external pure override returns (
        PayeeData[] memory
    ) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a 
        // hash to verify the backend. 

        IPoolManager.PoolKey memory key = abi.decode(
            data, 
            (IPoolManager.PoolKey)
        ); 

        PaymentData[] memory payments = new PaymentData[](1);

        payments[0] = PaymentData({
            payee: address(key.hooks),
            payeePercent: 100
        });

        PayeeData[] memory payeeData = new PayeeData[](2);

        payeeData[0] = PayeeData({
            token: IPoolManager.Currency.unwrap(key.currency0),
            payments: payments,
            data: data
        });

        payeeData[1] = PayeeData({
            token: IPoolManager.Currency.unwrap(key.currency1),
            payments: payments,
            data: data
        });

        return payeeData;
    }

    function getBidFormat(
        bytes calldata data
    ) external pure override returns (
        BidData[] memory
    ) {
        // This is a helper function called by searchers
        // so that they can get the proper format for 
        // submitting their bids to the hook. 
        
        IPoolManager.PoolKey memory key = abi.decode(
            data, 
            (IPoolManager.PoolKey)
        ); 

        BidData[] memory bidData = new BidData[](2);

        bidData[0] = BidData({
            token: IPoolManager.Currency.unwrap(key.currency0),
            bidAmount: 0 // <- searcher must update
        });

        bidData[1] = BidData({
            token: IPoolManager.Currency.unwrap(key.currency1),
            bidAmount: 0 // <- searcher must update
        });

        return bidData;
    }

      /////////////////////////////////////////////////////////
     //                      V4 HOOKS                       //
    /////////////////////////////////////////////////////////

    function getHooksCalls() public pure returns (IHooks.Calls memory) { // override
        return IHooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: true, // <-- 
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function beforeSwap(
        address sender, 
        IPoolManager.PoolKey calldata key, 
        IPoolManager.SwapParams calldata
    ) external view returns (bytes4)
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
            require(
                hashLock == keccak256(abi.encode(key, escrowKey.approvedCaller)), 
                "ERR-H04 InvalidPoolKey"
            );

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

        return AtlasV4Hook.beforeSwap.selector;
    }
}