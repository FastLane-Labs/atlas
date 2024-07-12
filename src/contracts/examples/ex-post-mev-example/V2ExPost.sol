//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Base Imports
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";

import { SafetyBits } from "src/contracts/libraries/SafetyBits.sol";

import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

// Uni V2 Imports
import { IUniswapV2Pair } from "./interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

// Misc
import { SwapMath } from "./SwapMath.sol";

// import "forge-std/Test.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
}

contract V2ExPost is DAppControl {
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    event GiftedGovernanceToken(address indexed user, address indexed token, uint256 amount);

    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: false,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: true,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: true,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: true,
                allowAllocateValueFailure: false
            })
        )
    { }

    function _checkUserOperation(UserOperation memory userOp) internal view {
        require(bytes4(userOp.data) == IUniswapV2Pair.swap.selector, "ERR-H10 InvalidFunction");
        require(
            IUniswapV2Factory(IUniswapV2Pair(userOp.dapp).factory()).getPair(
                IUniswapV2Pair(userOp.dapp).token0(), IUniswapV2Pair(userOp.dapp).token1()
            ) == userOp.dapp,
            "ERR-H11 Invalid pair"
        );
    }

    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory returnData) {
        // check if dapps using this DApontrol can handle the userOp
        _checkUserOperation(userOp);

        (
            uint256 amount0Out,
            uint256 amount1Out,
            , // address recipient // Unused
                // bytes memory swapData // Unused
        ) = abi.decode(userOp.data[4:], (uint256, uint256, address, bytes));

        require(amount0Out == 0 || amount1Out == 0, "ERR-H12 InvalidAmountOuts");
        require(amount0Out > 0 || amount1Out > 0, "ERR-H13 InvalidAmountOuts");

        (uint112 token0Balance, uint112 token1Balance,) = IUniswapV2Pair(userOp.dapp).getReserves();

        uint256 amount0In =
            amount1Out == 0 ? 0 : SwapMath.getAmountIn(amount1Out, uint256(token0Balance), uint256(token1Balance));
        uint256 amount1In =
            amount0Out == 0 ? 0 : SwapMath.getAmountIn(amount0Out, uint256(token1Balance), uint256(token0Balance));

        // This is a V2 swap, so optimistically transfer the tokens
        // NOTE: The user should have approved Atlas for token transfers
        _transferUserERC20(
            amount0Out > amount1Out ? IUniswapV2Pair(userOp.dapp).token1() : IUniswapV2Pair(userOp.dapp).token0(),
            userOp.dapp,
            amount0In > amount1In ? amount0In : amount1In
        );

        return new bytes(0);
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        if (bidAmount == 0) {
            return;
        }

        address user = _user();
        if (bidToken == address(0)) {
            SafeTransferLib.safeTransferETH(user, address(this).balance);
        } else {
            SafeTransferLib.safeTransfer(bidToken, user, bidAmount);
        }

        /*
        // ENABLE FOR FOUNDRY TESTING
        console.log("----====++++====----");
        console.log("DApp Control");
        console.log("Governance Tokens Burned:", govIsTok0 ? amount0Out : amount1Out);
        console.log("----====++++====----");
        */
    }

    ///////////////// GETTERS & HELPERS // //////////////////

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.
        return WETH;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
