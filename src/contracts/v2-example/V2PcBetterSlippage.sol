//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {IEscrow} from "../interfaces/IEscrow.sol";
import "../types/CallTypes.sol";

// Atlas Protocol-Control Imports
import {ProtocolControl} from "../protocol/ProtocolControl.sol";

// Uni V2 Imports
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router01.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

// import "forge-std/Test.sol";

/*
 * @notice Example of Uniswap V2 integration, with the following features:
    * - The user intent is to perform a swap on Uniswap V2 router only (no liquidity adding/removal operations)
    * - The bundler is the user, they front the overall gas cost
    * - All MEV is collected as the token the user is buying, improving slippage on the swap
*/
contract V2PcBetterSlippage is ProtocolControl {
    address public immutable bundler;
    address public immutable uniswapV2Router02;
    mapping(bytes4 => bool) public allowedSelectors;

    constructor(address _escrow, address _bundler, address _uniswapV2Router02)
        ProtocolControl(_escrow, msg.sender, false, true, false, false, false, false, false, true, false, true, true, true)
    {
        bundler = _bundler;
        uniswapV2Router02 = _uniswapV2Router02;

        allowedSelectors[bytes4(IUniswapV2Router01.swapExactTokensForTokens.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router01.swapTokensForExactTokens.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router01.swapExactETHForTokens.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router01.swapTokensForExactETH.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router01.swapExactTokensForETH.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router01.swapETHForExactTokens.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector)] =
            true;
        allowedSelectors[bytes4(IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector)] = true;
        allowedSelectors[bytes4(IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector)] = true;
    }

    /*
    constructor(
        address _escrow,
        address _governance,
        bool _sequenced,
        bool _requireStaging,
        bool _localUser,
        bool _delegateUser,
        bool _searcherStaging,
        bool _searcherFulfillment,
        bool _requireVerification,
        bool _zeroSearchers,
        bool _reuseUserOp,
        bool _userBundler,
        bool _protocolBundler,
        bool _unknownBundler
    )
    */

    function _stagingCall(address, address to, bytes4 funcSelector, bytes calldata)
        internal
        view
        override
        returns (bytes memory)
    {
        // User is only allowed to call UniswapV2Router02
        require(to == uniswapV2Router02, "ERR-H10 InvalidDestination");

        // User is only allowed to call swap functions
        require(allowedSelectors[funcSelector], "ERR-H11 InvalidFunction");

        // User must have approved UniswapV2Router02 to transferFrom the tokens they are selling

        bytes memory emptyData;
        return emptyData;
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingCall(bytes calldata data) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // Get bids
        (, BidData[] memory bids,) = abi.decode(data, (uint256, BidData[], bytes));

        // Token the MEV was captured in
        address token = bids[0].token;

        uint256 balance = ERC20(token).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        SafeTransferLib.safeTransfer(ERC20(token), _user(), balance);
    }

    ///////////////// GETTERS & HELPERS // //////////////////
    function getPayeeData(bytes calldata userCallData) external view override returns (PayeeData[] memory) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a
        // hash to verify the backend.
        bytes memory data;
        PaymentData[] memory payments = new PaymentData[](1);
        payments[0] = PaymentData({payee: control, payeePercent: 100});
        PayeeData[] memory payeeData = new PayeeData[](1);
        payeeData[0] = PayeeData({token: getBidToken(userCallData), payments: payments, data: data});
        return payeeData;
    }

    function getBidFormat(bytes calldata userCallData) external pure override returns (BidData[] memory) {
        BidData[] memory bidData = new BidData[](1);
        bidData[0] = BidData({
            token: getBidToken(userCallData),
            bidAmount: 0 // <- searcher must update
        });
        return bidData;
    }

    function getBidToken(bytes calldata userCallData) internal pure returns (address bidToken) {
        bytes4 funcSelector = bytes4(userCallData);
        bytes memory data = userCallData[4:];
        address[] memory path;

        if (
            funcSelector == bytes4(IUniswapV2Router01.swapExactTokensForTokens.selector)
                || funcSelector == bytes4(IUniswapV2Router01.swapTokensForExactTokens.selector)
                || funcSelector == bytes4(IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector)
        ) {
            (,, path,,) = abi.decode(data, (uint256, uint256, address[], address, uint256));
        } else if (
            funcSelector == bytes4(IUniswapV2Router01.swapExactETHForTokens.selector)
                || funcSelector == bytes4(IUniswapV2Router01.swapETHForExactTokens.selector)
                || funcSelector == bytes4(IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector)
        ) {
            (, path,,) = abi.decode(data, (uint256, address[], address, uint256));
        } else if (
            funcSelector == bytes4(IUniswapV2Router01.swapTokensForExactETH.selector)
                || funcSelector == bytes4(IUniswapV2Router01.swapExactTokensForETH.selector)
                || funcSelector == bytes4(IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector)
        ) {
            return address(0);
        }

        bidToken = path[path.length - 1];
    }
}
