//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import { ISafetyLocks } from "../interfaces/ISafetyLocks.sol";
import { IUserDirect } from "../interfaces/IUserDirect.sol";

import { SafetyBits } from "../libraries/SafetyBits.sol"; 

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

// Atlas Protocol-Control Imports
import { ProtocolControl } from "../protocol/ProtocolControl.sol";
import { MEVAllocator } from "../protocol/MEVAllocator.sol";

// Uni V2 Imports
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";

// Misc
import { SwapMath } from "./SwapMath.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}
contract V2ProtocolControl is MEVAllocator, ProtocolControl {

    address constant public WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public GOVERNANCE_TOKEN = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    address constant public WETH_X_GOVERNANCE_POOL = address(0xd3d2E2692501A5c9Ca623199D38826e513033a17);

    bytes4 constant public SWAP = bytes4(IUniswapV2Pair.swap.selector);

    address immutable public control;

    bool immutable public govIsTok0;

    event BurnedGovernanceToken(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(
        address _escrow
    ) 
    MEVAllocator() 
    ProtocolControl(
        _escrow,
        msg.sender,
        false,
        true,
        true,
        false,
        false,
        true, 
        false,
        false, 
        true 
    ) {
        control = address(this);
        govIsTok0 = (IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token0() == GOVERNANCE_TOKEN);
    }

    /*
    constructor(
        address escrowAddress,
        address governanceAddress,
        bool shouldRequireSequencedNonces,
        bool shouldRequireStaging,
        bool shouldDelegateStaging,
        bool shouldExecuteUserLocally,
        bool shouldDelegateUser,
        bool shouldDelegateAllocating,
        bool shouldRequireVerification,
        bool shouldDelegateVerification,
        bool allowRecycledStorage
    )
    */

    function _stageDelegateCall(
        bytes calldata data
    ) internal override returns (bytes memory) {
        require(bytes4(data[:4]) == SWAP, "ERR-H10 InvalidFunction"); 

        // NOTE: This is a very direct example to facilitate the creation of a testing environment.  
        // Using this example in production is ill-advised. 

        UserCall memory userCall = abi.decode(data[4:], (UserCall));

        (
            uint256 amount0Out, 
            uint256 amount1Out, 
            , // address recipient // Unused
            // bytes memory swapData // Unused
        ) = abi.decode(userCall.data, (uint256, uint256, address, bytes));

        address tokenUserIsSelling = amount0Out > amount1Out ?
            IUniswapV2Pair(userCall.to).token1() :
            IUniswapV2Pair(userCall.to).token0() ;

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(userCall.to).getReserves();

        uint256 amountUserIsSelling = amount0Out > amount1Out ?
            SwapMath.getAmountIn(amount0Out, uint256(token1Balance), uint256(token0Balance)) :
            SwapMath.getAmountIn(amount1Out, uint256(token0Balance), uint256(token1Balance)) ;

        // This is a V2 swap, so optimistically transfer the tokens
        // NOTE: The user should have approved the ExecutionEnvironment for token transfers
        ERC20(tokenUserIsSelling).transferFrom(userCall.from, userCall.to, amountUserIsSelling); 

        bytes memory emptyData;
        return emptyData;
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingDelegateCall(
        bytes calldata
    ) internal override {
        // This function is delegatecalled 
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // NOTE: ProtocolVerifier has verified the PayeeData[] and BidData[] format
        // BidData[0] = address(0) <== Ether
     
        // MEV Rewards were collected in Ether
        uint256 balance = address(this).balance;

        require(balance > 0, "ERR-AC01 NoBalance");

        IWETH(WETH).deposit{value: balance}();

        // Decrement the balance by 1 so that the contract keeps the storage slot
        // initialized. 
        unchecked { --balance; } 
    
        ERC20(WETH).transfer(WETH_X_GOVERNANCE_POOL, balance); 

        bytes memory nullBytes;

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).getReserves();

        uint256 amount0Out;
        uint256 amount1Out;

        if (govIsTok0) {
            amount0Out = (
                (997_000 * balance) * uint256(token0Balance)
            ) / (
                (uint256(token1Balance) * 1_000_000) + (997_000 * balance)
            );

        } else {
            amount1Out = (
                (997_000 * balance) * uint256(token1Balance)
            ) / (
                ((uint256(token0Balance) * 1_000_000) + (997_000 * balance))
            );
        }

        IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).swap(
            amount0Out, 
            amount1Out, 
            address(0), // This sends the tokens to the null address, which burns the governance token.
            nullBytes
        );

        emit BurnedGovernanceToken(
            IUserDirect(address(this)).getUser(),
            GOVERNANCE_TOKEN,
            govIsTok0 ? amount0Out : amount1Out
        );

    }

    ///////////////// GETTERS & HELPERS // //////////////////
    function getPayeeData(
        bytes calldata 
    ) external view override returns (
        PayeeData[] memory
    ) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a 
        // hash to verify the backend. 

        bytes memory data; // empty bytes

        PaymentData[] memory payments = new PaymentData[](1);

        payments[0] = PaymentData({
            payee: control,
            payeePercent: 100
        });

        PayeeData[] memory payeeData = new PayeeData[](1);

        payeeData[0] = PayeeData({
            token: address(0),
            payments: payments,
            data: data
        });
        return payeeData;
    }

    function getBidFormat(
        bytes calldata
    ) external pure override returns (
        BidData[] memory
    ) {
        // This is a helper function called by searchers
        // so that they can get the proper format for 
        // submitting their bids to the hook. 
        
        BidData[] memory bidData = new BidData[](1);

        bidData[0] = BidData({
            token: address(0),
            bidAmount: 0 // <- searcher must update
        });

        return bidData;
    }
}