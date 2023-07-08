// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IProtocolControl} from "../src/contracts/interfaces/IProtocolControl.sol";
import {IProtocolIntegration} from "../src/contracts/interfaces/IProtocolIntegration.sol";
import {IEscrow} from "../src/contracts/interfaces/IEscrow.sol";
import {IUniswapV2Pair} from "../src/contracts/v2-example/interfaces/IUniswapV2Pair.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

import {BlindBackrun} from "./searcher/src/blindBackrun.sol";

import {TestConstants} from "./base/TestConstants.sol";

import {CallVerification} from "../src/contracts/libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract Helper is Test, TestConstants {
    address public immutable control;
    address public immutable escrow;
    address public immutable atlas;
    uint256 public immutable maxFeePerGas;
    uint256 public immutable deadline;
    uint256 public immutable gas;

    constructor(address protocolControl, address escrowAddress, address atlasAddress) {
        control = protocolControl;
        escrow = escrowAddress;
        atlas = atlasAddress;
        maxFeePerGas = tx.gasprice * 2;
        deadline = block.number + 2;
        gas = 1_000_000;
    }

    function getPayeeData() public returns (PayeeData[] memory) {
        bytes memory nullData;
        return IProtocolControl(control).getPayeeData(nullData);
    }

    function getProtocolCall() public view returns (ProtocolCall memory) {
        return IProtocolControl(control).getProtocolCall();
    }

    function getBidData(uint256 amount) public returns (BidData[] memory bids) {
        bytes memory nullData;
        bids = IProtocolControl(control).getBidFormat(nullData);
        bids[0].bidAmount = amount;
    }

    function searcherNextNonce(address searcherMetaTxSigner) public view returns (uint256) {
        return IEscrow(escrow).nextSearcherNonce(searcherMetaTxSigner);
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        return IProtocolIntegration(atlas).nextGovernanceNonce(signatory);
    }

    function buildUserCall(address to, address from, address tokenIn) public view returns (UserCall memory userCall) {
        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(to).getReserves();

        address token0 = IUniswapV2Pair(to).token0();

        userCall = UserCall({
            to: to,
            from: from,
            deadline: deadline,
            gas: gas,
            value: 0,
            data: buildV2SwapCalldata(
                tokenIn == token0 ? 0 : uint256(token0Balance) / 2, tokenIn == token0 ? uint256(token1Balance) / 2 : 0, from
                )
        });
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
        address searcherEOA,
        address searcherContract,
        address poolOne,
        address poolTwo,
        uint256 bidAmount
    ) public returns (SearcherCall memory searcherCall) {
        searcherCall.bids = getBidData(bidAmount);
        searcherCall.metaTx = SearcherMetaTx({
            from: searcherEOA,
            to: searcherContract,
            gas: gas,
            value: 0,
            nonce: searcherNextNonce(searcherEOA),
            userCallHash: keccak256(abi.encodePacked(userCall.to, userCall.data)),
            maxFeePerGas: maxFeePerGas,
            bidsHash: keccak256(abi.encode(searcherCall.bids)),
            data: abi.encodeWithSelector(BlindBackrun.executeArbitrage.selector, poolOne, poolTwo)
        });
    }

    function buildVerification(
        address governanceEOA,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        PayeeData[] memory payeeData,
        SearcherCall[] calldata searcherCalls
    ) public view returns (Verification memory verification) {
        bytes32[] memory executionHashChain =
            CallVerification.buildExecutionHashChain(protocolCall, userCall, searcherCalls);

        verification.proof = ProtocolProof({
            from: governanceEOA,
            to: control,
            nonce: governanceNextNonce(governanceEOA),
            deadline: deadline,
            payeeHash: keccak256(abi.encode(payeeData)),
            userCallHash: keccak256(abi.encodePacked(userCall.to, userCall.data)),
            callChainHash: executionHashChain[executionHashChain.length - 1]
        });
    }
}
