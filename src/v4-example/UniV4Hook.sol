//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// V4 Imports
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {BaseHook} from "@uniswap/periphery-next/contracts/BaseHook.sol";

// Atlas Base Imports
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { SafetyBits } from "../libraries/SafetyBits.sol"; 
import { 
    EscrowKey,
    BidData,
    PayeeData,
    PaymentData,
    UserCall
} from "../libraries/DataTypes.sol";

// Atlas Protocol-Control Imports
import { ProtocolControl } from "../protocol-managed/ProtocolControl.sol";


contract AtlasV4Hook {

    bytes4 public constant SWAP = IPoolManager.swap.selector;

    address public immutable atlas;
    address public immutable hook;
    address public immutable v4Singleton;
    PoolKey public immutable poolKey;
    address public immutable token0;
    address public immutable token1;
    address public immutable executionEnvironment; 
    // NOTE: ExecutionEnvironment is created with CREATE2, allowing us to know
    // its address in advance. A new contract is created and selfdestructed for each
    // MEV auction to ensure that storage is clean. 

    constructor(
        address _atlas,
        address _executionEnvironment,
        address _v4Singleton,
        PoolKey calldata _poolKey
    ) {
        atlas = atlasEscrow;
        hook = address(this);
        executionEnvironment = _executionEnvironment;
        v4Singleton = _v4Singleton;
        poolKey = _poolKey;
        token0 = address(_poolKey.currency0);
        token1 = address(_poolKey.currency1);
    }

      /////////////////////////////////////////////////////////
     //                   ATLAS CALLS                       //
    /////////////////////////////////////////////////////////

    // This occurs prior to the User's call being executed
    function _stageDelegateCall(
        bytes calldata data
    ) internal returns (bytes memory stagingData) {

        UserCall memory userCall = abi.decode(data, (UserCall));

        require(bytes4(userCall.data[:4]) == SWAP, "ERR-H10 InvalidFunction");

        (
            PoolKey memory key, 
            SwapParams memory params
        ) = abi.decode(userCall.data[4:], (PoolKey, SwapParams));
        
        // Handle forwarding of token approvals
        // NOTE: The user will have approved the ExecutionEnvironment
        // in a prior call
        // TODO: Finish
    
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingDelegateCall(
        bytes calldata data
    ) internal {
        // This function is delegatecalled 
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // Pull the calldata into memory
        (
            uint256 totalEtherReward,
            BidData[] memory bids,
            PayeeData[] memory payeeData
        ) = abi.decode(data, (uint256, BidData[], PayeeData[]));

        // TODO: Verify donate function's handling of unwrapped Ether
        uint256 token0DonateAmount;
        uint256 token1DonateAmount;

        // Memory variables for loops
        uint256 i;
        uint256 k;
        PaymentData memory pmtData;

        // TODO: Build V4-specific structs to avoid loops here
        for (; i < bids.length;) {
            tokenAddress = bids[i].token;
            bidAmount = bids[i].bidAmount;

            if (bids[i].token == token0) {
                for (; k < payeeData[i].payments.length;) {
                    if (payeeData[i].payments[k].payee == hook){ 
                        token0DonateAmount = bids[i].bidAmount * pmtData.payeePercent / 100;
                        k = 0;  // reset k for other token loop
                        break;
                    }
                    unchecked{ ++k;}
                }

            } else if (bids[i].token == token1) {
                for (; k < payeeData[i].payments.length;) {
                    if (payeeData[i].payments[k].payee == hook){ 
                        token1DonateAmount = bids[i].bidAmount * pmtData.payeePercent / 100;
                        k = 0;  // reset k for other token loop
                        break;
                    }
                    unchecked{ ++k;}
                }
            }

            if (token0DonateAmount != 0 && token1DonateAmount != 0) {
                break;
            }
            unchecked{ ++i;}
        }

        IPoolManager(v4Singleton).donate(poolKey, token0DonateAmount, token1DonateAmount);
    }

    function _verificationDelegateCall(
        bytes calldata data
    ) internal returns (bool) {
        // TODO: Remove the token approvals granted during staging
    }


      /////////////////////////////////////////////////////////
     //                      V4 HOOKS                       //
    /////////////////////////////////////////////////////////
    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function beforeSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        returns (bytes4)
    {
        // Not delegatecall
        // address(this) = hook
        // msg.sender = ExecutionEnvironment

        EscrowKey memory escrowKey = ISafetyLocks(atlas).getLockState();

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that ProtocolControl supplied a valid signature
        require(msg.sender == executionEnvironment, "ERR-H00 InvalidCaller");
        require(address(this) == escrowKey.approvedCaller, "ERR-H01 InvalidCallee");
        require(escrowKey.lockState == SafetyBits._LOCKED_X_STAGING_X_UNSET, "ERR-H02 InvalidLockStage");

        return AtlasV4Hook.beforeSwap.selector;
    }


}