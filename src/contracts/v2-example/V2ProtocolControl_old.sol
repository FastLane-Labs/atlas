//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {ISafetyLocks} from "../interfaces/ISafetyLocks.sol";
import {IExecutionEnvironment} from "../interfaces/IExecutionEnvironment.sol";

import {SafetyBits} from "../libraries/SafetyBits.sol";

import "../types/CallTypes.sol";
import "../types/LockTypes.sol";

// Atlas Protocol-Control Imports
import {ProtocolControl} from "../protocol/ProtocolControl.sol";

// Uni V2 Imports
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router01.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

// Misc
import {IWETH} from "./interfaces/IWETH.sol";

// import "forge-std/Test.sol";

contract V2ProtocolControl is ProtocolControl {
    address public immutable uniswapV2Router02;
    address public immutable governanceToken;
    address public immutable WETH;

    mapping(bytes4 => bool) public allowedSelectors;

    uint256 public constant CONTROL_GAS_USAGE = 250_000;

    event GasRefunded(address indexed to, uint256 amount);
    event BurnedGovernanceToken(address indexed user, address indexed token, uint256 amount);

    constructor(address _escrow, address _uniswapV2Router02, address _governanceToken)
        ProtocolControl(_escrow, msg.sender, false, true, false, false, false, false, false, true, false, true, true, true)
    {
        uniswapV2Router02 = _uniswapV2Router02;
        governanceToken = _governanceToken;
        WETH = IUniswapV2Router02(uniswapV2Router02).WETH();

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

    function _stagingCall(address, address, bytes4 userSelector, bytes calldata)
        internal
        view
        override
        returns (bytes memory)
    {
        // Only checks that the called function is allowed
        require(allowedSelectors[userSelector], "ERR-H10 InvalidFunction");

        // User must have approved UniswapV2Router02 to transferFrom the tokens they are selling

        bytes memory emptyData;
        return emptyData;
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingCall(bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        address user = _user();

        // MEV Rewards were collected in WETH
        uint256 balance = ERC20(WETH).balanceOf(address(this));

        if (balance == 0) {
            // oops?
            return;
        }

        // Refund the user any extra gas costs
        uint256 userGasOverage = tx.gasprice * CONTROL_GAS_USAGE;
        uint256 refundAmount = userGasOverage > balance ? balance : userGasOverage;

        IWETH(WETH).withdraw(refundAmount);
        SafeTransferLib.safeTransferETH(user, refundAmount);
        emit GasRefunded(user, refundAmount);

        balance -= refundAmount;

        if (balance == 0) {
            // No balance left
            return;
        }

        // Swap the WETH balance to governance token
        IWETH(WETH).approve(uniswapV2Router02, balance);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = governanceToken;

        uint256 burnedAmount = IUniswapV2Router02(uniswapV2Router02).swapExactTokensForTokens(
            balance, 0, path, address(0), block.timestamp
        )[1];

        emit BurnedGovernanceToken(user, governanceToken, burnedAmount);
    }

    ///////////////// GETTERS & HELPERS // //////////////////
    function getPayeeData(bytes calldata) external view override returns (PayeeData[] memory) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a
        // hash to verify the backend.

        bytes memory data; // empty bytes

        PaymentData[] memory payments = new PaymentData[](1);

        payments[0] = PaymentData({payee: control, payeePercent: 100});

        PayeeData[] memory payeeData = new PayeeData[](1);

        payeeData[0] = PayeeData({token: WETH, payments: payments, data: data});
        return payeeData;
    }

    function getBidFormat(bytes calldata) external view override returns (BidData[] memory) {
        BidData[] memory bidData = new BidData[](1);

        bidData[0] = BidData({
            token: WETH,
            bidAmount: 0 // <- searcher must update
        });

        return bidData;
    }
}
