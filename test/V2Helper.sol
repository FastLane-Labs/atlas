// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TxBuilder} from "../src/contracts/helpers/TxBuilder.sol";

import {IUniswapV2Pair} from "../src/contracts/v2-example/interfaces/IUniswapV2Pair.sol";

import {BlindBackrun} from "./searcher/src/blindBackrun.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

import {TestConstants} from "./base/TestConstants.sol";

import "forge-std/Test.sol";

contract V2Helper is Test, TestConstants, TxBuilder {
   
    uint256 public immutable maxFeePerGas;

    constructor(address protocolControl, address escrowAddress, address atlasAddress) 
        TxBuilder(protocolControl, escrowAddress, atlasAddress)
    {
        maxFeePerGas = tx.gasprice * 2;
    }

    function getPayeeData() public returns (PayeeData[] memory) {
        bytes memory nullData;
        return TxBuilder.getPayeeData(nullData);
    }

    function buildUserCall(address to, address from, address tokenIn) public view returns (UserCall memory userCall) {
        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(to).getReserves();

        address token0 = IUniswapV2Pair(to).token0();

        return TxBuilder.buildUserCall(
            from,
            to,
            maxFeePerGas,
            0,
            buildV2SwapCalldata(
                tokenIn == token0 ? 0 : uint256(token0Balance) / 2, tokenIn == token0 ? uint256(token1Balance) / 2 : 0, from
                )
        );
    }

    function buildV2SwapCalldata(uint256 amount0Out, uint256 amount1Out, address recipient)
        public
        pure
        returns (bytes memory data)
    {
        data = abi.encodeWithSelector(IUniswapV2Pair.swap.selector, amount0Out, amount1Out, recipient, data);
    }

    function buildSearcherCall(
        UserCall memory userCall,
        ProtocolCall memory protocolCall,
        address searcherEOA,
        address searcherContract,
        address poolOne,
        address poolTwo,
        uint256 bidAmount
    ) public returns (SearcherCall memory searcherCall) {
        return TxBuilder.buildSearcherCall(
            userCall, 
            protocolCall, 
            abi.encodeWithSelector(BlindBackrun.executeArbitrage.selector, poolOne, poolTwo),
            searcherEOA, 
            searcherContract,  
            bidAmount
        );
    }
}
