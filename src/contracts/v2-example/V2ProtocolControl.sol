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
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

// Misc
import {SwapMath} from "./SwapMath.sol";

// import "forge-std/Test.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract V2ProtocolControl is ProtocolControl {

    uint256 public constant CONTROL_GAS_USAGE = 250_000;

    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant GOVERNANCE_TOKEN = address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    address public constant WETH_X_GOVERNANCE_POOL = address(0xd3d2E2692501A5c9Ca623199D38826e513033a17);

    address public constant BURN_ADDRESS =
        address(uint160(uint256(keccak256(abi.encodePacked("GOVERNANCE TOKEN BURN ADDRESS")))));

    bytes4 public constant SWAP = bytes4(IUniswapV2Pair.swap.selector);

    bool public immutable govIsTok0;

    event GiftedGovernanceToken(address indexed user, address indexed token, uint256 amount);

    constructor(address _escrow)
        ProtocolControl(
            _escrow, 
            msg.sender, 
            false, 
            true, 
            false, 
            false, 
            false,
            false, 
            false, 
            true, 
            false, 
            true,
            true,
            true
        )
    {
        govIsTok0 = (IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token0() == GOVERNANCE_TOKEN);
        if (govIsTok0) {
            require(IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token1() == WETH, "INVALID TOKEN PAIR");
        } else {
            require(IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).token0() == WETH, "INVALID TOKEN PAIR");
        }
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

    function _stagingCall(UserMetaTx calldata userMetaTx)
        internal
        override
        returns (bytes memory)
    {
        require(bytes4(userMetaTx.data) == SWAP, "ERR-H10 InvalidFunction");

        (
            uint256 amount0Out,
            uint256 amount1Out,
            , // address recipient // Unused
                // bytes memory swapData // Unused
        ) = abi.decode(userMetaTx.data[4:], (uint256, uint256, address, bytes));

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(userMetaTx.to).getReserves();

        uint256 amount0In =
            amount1Out == 0 ? 0 : SwapMath.getAmountIn(amount1Out, uint256(token0Balance), uint256(token1Balance));
        uint256 amount1In =
            amount0Out == 0 ? 0 : SwapMath.getAmountIn(amount0Out, uint256(token1Balance), uint256(token0Balance));


        // This is a V2 swap, so optimistically transfer the tokens
        // NOTE: The user should have approved the ExecutionEnvironment for token transfers
        _transferUserERC20(
            amount0Out > amount1Out ? IUniswapV2Pair(userMetaTx.to).token1() : IUniswapV2Pair(userMetaTx.to).token0(),
            userMetaTx.to, 
            amount0In > amount1In ? amount0In : amount1In
        );

        bytes memory emptyData;
        return emptyData;
    }

    // This occurs after a Searcher has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingCall(bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // NOTE: ProtocolVerifier has verified the BidData[] format
        // BidData[0] = address(WETH) <== WETH

        address user = _user();

        // MEV Rewards were collected in WETH
        uint256 balance = ERC20(WETH).balanceOf(address(this));

        // TODO: remove this to allow graceful return?
        require(balance > 0, "ERR-AC01 NoBalance");

        // Refund the user any extra gas costs
        uint256 userGasOverage = tx.gasprice * CONTROL_GAS_USAGE;
        
        // CASE: gas costs exceed MEV
        if (balance <= userGasOverage) {
            IWETH(WETH).withdraw(balance); // should null out the balance
            SafeTransferLib.safeTransferETH(user, balance);
            return;
        
        // CASE: MEV exceeds gas costs
        } else {
            IWETH(WETH).withdraw(userGasOverage); // should null out the balance
            SafeTransferLib.safeTransferETH(user, userGasOverage);
            balance -= userGasOverage;
        }

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).getReserves();

        ERC20(WETH).transfer(WETH_X_GOVERNANCE_POOL, balance);

        uint256 amount0Out;
        uint256 amount1Out;

        if (govIsTok0) {
            amount0Out = ((997_000 * balance) * uint256(token0Balance))
                / ((uint256(token1Balance) * 1_000_000) + (997_000 * balance));
        } else {
            amount1Out = ((997_000 * balance) * uint256(token1Balance))
                / (((uint256(token0Balance) * 1_000_000) + (997_000 * balance)));
        }

        bytes memory nullBytes;
        IUniswapV2Pair(WETH_X_GOVERNANCE_POOL).swap(amount0Out, amount1Out, user, nullBytes);

        emit GiftedGovernanceToken(user, GOVERNANCE_TOKEN, govIsTok0 ? amount0Out : amount1Out);

        /*
        // ENABLE FOR FOUNDRY TESTING
        console.log("----====++++====----");
        console.log("Protocol Control");
        console.log("Governance Tokens Burned:", govIsTok0 ? amount0Out : amount1Out);
        console.log("----====++++====----");
        */
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

    function getBidFormat(UserMetaTx calldata) external pure override returns (BidData[] memory) {
        // This is a helper function called by searchers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        BidData[] memory bidData = new BidData[](1);

        bidData[0] = BidData({
            token: WETH,
            bidAmount: 0 // <- searcher must update
        });

        return bidData;
    }

    function getBidValue(SearcherCall calldata searcherCall)
        external
        pure
        override
        returns (uint256) 
    {
        return searcherCall.bids[0].bidAmount;
    }


}
