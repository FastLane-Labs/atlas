//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";


interface ISolverGateway {
    function getBidAmount(bytes32 solverOpHash) external view returns (uint256 bidAmount);  
}
contract FastLaneOnlineControl is DAppControl {
    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: true,
                requirePreSolver: true,
                requirePostSolver: false,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: false,
                forwardReturnData: true,
                requireFulfillment: true,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: true,
                allowAllocateValueFailure: false
            })
        )
    { }

    // ---------------------------------------------------- //
    //                     Atlas hooks                      //
    // ---------------------------------------------------- //

    /*
    * @notice This function is called before a solver operation executes
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers the tokens that the user is selling to the solver
    * @param solverOp The SolverOperation that is about to execute
    * @return true if the transfer was successful, false otherwise
    */
    function _preSolverCall(SolverOperation calldata solverOp, bytes calldata returnData) internal override {
        (, SwapIntent memory _swapIntent,) = abi.decode(returnData, (address, SwapIntent, BaselineCall));

        // Make sure the token is correct
        require(solverOp.bidToken == _swapIntent.tokenUserBuys, "FLOnlineControl: BuyTokenMismatch");
        require(solverOp.bidToken != _swapIntent.tokenUserSells, "FLOnlineControl: SellTokenMismatch");

        // NOTE: This module is unlike the generalized swap intent module - here, the solverOp.bidAmount includes
        // the min amount that the user expects.
        require(solverOp.bidAmount >= _swapIntent.minAmountUserBuys, "FLOnlineControl: BidBelowReserve");

        // If not bidfinding, verify that the new ExPost bid is >= the actual bid
        // NOTE: This allows bid improvement but blocks bid decrementing
        // NOTE: Only do this after bidfinding so that solvers still pay for failure in both cost and reputation.
        // TODO: Solvers can see the bids of other Solvers because the SolverOp maps have public getters.
        // This needs to be fixed by customizing the getters so they don't work during the actual SolverOps.
        if (!_bidFind()) {
            bytes32 _solverOpHash = keccak256(abi.encode(solverOp));
            (bool _success, bytes memory _data) = CONTROL.staticcall(abi.encodeCall(ISolverGateway.getBidAmount, (_solverOpHash)));
            require(_success, "FLOnlineControl: BidAmountFail");

            uint256 _minBidAmount = abi.decode(_data, (uint256));
            require(solverOp.bidAmount >= _minBidAmount, "FLOnlineControl: ExPostBelowAnte");
        }

        // Optimistically transfer to the solver contract the tokens that the user is selling
        _transferUserERC20(_swapIntent.tokenUserSells, solverOp.solver, _swapIntent.amountUserSells);

        return; // success
    }

    /*
    * @notice This function is called after a solver has successfully paid their bid
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers all the available bid tokens on the contract (instead of only the bid amount,
    *      to avoid leaving any dust on the contract)
    * @param bidToken The address of the token used for the winning solver operation's bid
    * @param _
    * @param _
    */
    function _allocateValueCall(address, uint256, bytes calldata returnData) internal override {
        (address _swapper, SwapIntent memory _swapIntent,) = abi.decode(returnData, (address, SwapIntent, BaselineCall));

        uint256 _buyTokenBalance = _getERC20Balance(_swapIntent.tokenUserBuys);

        SafeTransferLib.safeTransfer(_swapIntent.tokenUserBuys, _swapper, _buyTokenBalance);
    }

    // ---------------------------------------------------- //
    //                 Getters and helpers                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        (, SwapIntent memory _swapIntent,) = abi.decode(userOp.data[4:], (address, SwapIntent, BaselineCall));
        bidToken = _swapIntent.tokenUserBuys;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    function _getERC20Balance(address token) internal view returns (uint256 balance) {
        (bool _success, bytes memory _data) = token.staticcall(abi.encodeCall(IERC20.balanceOf, address(this)));
        require(_success, "OuterHelper: BalanceCheckFail");
        balance = abi.decode(_data, (uint256));
    }
}
