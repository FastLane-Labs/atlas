//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

// Base Imports
import { SafeTransferLib, ERC20 } from "solmate/utils/SafeTransferLib.sol";

// Atlas Imports
import { DAppControl } from "../../dapp/DAppControl.sol";
import { CallConfig } from "../../types/DAppApprovalTypes.sol";
import "../../types/UserCallTypes.sol";
import "../../types/SolverCallTypes.sol";
import "../../types/LockTypes.sol";

struct Condition {
    address antecedent;
    bytes context;
}

// External representation of the swap intent
struct SwapIntent {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency;
    Condition[] conditions; // Optional
}

// Internal representation of the swap intent
struct SwapData {
    address tokenUserBuys;
    uint256 amountUserBuys;
    address tokenUserSells;
    uint256 amountUserSells;
    address auctionBaseCurrency;
}

contract SwapIntentDAppControl is DAppControl {
    using SafeTransferLib for ERC20;

    uint256 public constant USER_CONDITION_GAS_LIMIT = 20_000;
    uint256 public constant MAX_USER_CONDITIONS = 5;

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
                preSolver: true,
                postSolver: true,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: true,
                userAuctioneer: false,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: true,
                trustedOpHash: true,
                invertBidValue: false,
                exPostBids: false
            })
        )
    { }

    // ---------------------------------------------------- //
    //                       Custom                         //
    // ---------------------------------------------------- //

    /*
    * @notice This is the user operation target function
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev selector = 0x98434997
    * @dev It checks that the user has approved Atlas to spend the tokens they are selling and the conditions are met
    * @param swapIntent The SwapIntent struct
    * @return swapData The SwapData struct
    */
    function swap(SwapIntent calldata swapIntent) external payable returns (SwapData memory) {
        require(msg.sender == atlas, "SwapIntentDAppControl: InvalidSender");
        require(_addressPointer() == CONTROL, "SwapIntentDAppControl: InvalidLockState");
        require(address(this) != CONTROL, "SwapIntentDAppControl: MustBeDelegated");
        require(swapIntent.tokenUserSells != swapIntent.auctionBaseCurrency, "SwapIntentDAppControl: SellIsSurplus");

        address user = _user();

        require(
            _availableFundsERC20(swapIntent.tokenUserSells, user, swapIntent.amountUserSells, ExecutionPhase.PreSolver),
            "SwapIntentDAppControl: SellFundsUnavailable"
        );

        if (swapIntent.conditions.length > 0) {
            require(swapIntent.conditions.length <= MAX_USER_CONDITIONS, "SwapIntentDAppControl: TooManyConditions");

            bool valid;
            bytes memory conditionData;

            for (uint256 i; i < swapIntent.conditions.length; ++i) {
                (valid, conditionData) = swapIntent.conditions[i].antecedent.staticcall{ gas: USER_CONDITION_GAS_LIMIT }(
                    swapIntent.conditions[i].context
                );
                require(valid && abi.decode(conditionData, (bool)), "SwapIntentDAppControl: ConditionUnsound");
            }
        }

        return SwapData({
            tokenUserBuys: swapIntent.tokenUserBuys,
            amountUserBuys: swapIntent.amountUserBuys,
            tokenUserSells: swapIntent.tokenUserSells,
            amountUserSells: swapIntent.amountUserSells,
            auctionBaseCurrency: swapIntent.auctionBaseCurrency
        });
    }

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
    function _preSolverCall(
        SolverOperation calldata solverOp,
        bytes calldata returnData
    )
        internal
        override
        returns (bool)
    {
        address solverTo = solverOp.solver;
        if (solverTo == address(this) || solverTo == _control() || solverTo == atlas) {
            return false;
        }

        SwapData memory swapData = abi.decode(returnData, (SwapData));

        // Optimistically transfer to the solver contract the tokens that the user is selling
        _transferUserERC20(swapData.tokenUserSells, solverTo, swapData.amountUserSells);

        return true;
    }

    /*
    * @notice This function is called after a solver operation executed
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers to the user the tokens they are buying
    * @param _
    * @param returnData The return data from the user operation (swap data)
    * @return true if the transfer was successful, false otherwise
    */
    function _postSolverCall(SolverOperation calldata, bytes calldata returnData) internal override returns (bool) {
        SwapData memory swapData = abi.decode(returnData, (SwapData));
        uint256 buyTokenBalance = ERC20(swapData.tokenUserBuys).balanceOf(address(this));

        if (buyTokenBalance < swapData.amountUserBuys) {
            return false;
        }

        // Transfer exactly the amount the user is buying, the bid amount will be transferred
        // in _allocateValueCall, even if those are the same tokens
        if (swapData.tokenUserBuys != swapData.auctionBaseCurrency) {
            ERC20(swapData.tokenUserBuys).safeTransfer(_user(), buyTokenBalance);
        } else {
            ERC20(swapData.tokenUserBuys).safeTransfer(_user(), swapData.amountUserBuys);
        }

        return true;
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
    function _allocateValueCall(address bidToken, uint256, bytes calldata) internal override {
        if (bidToken != address(0)) {
            ERC20(bidToken).safeTransfer(_user(), ERC20(bidToken).balanceOf(address(this)));
        } else {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);
        }
    }

    // ---------------------------------------------------- //
    //                 Getters and helpers                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        (SwapIntent memory swapIntent) = abi.decode(userOp.data[4:], (SwapIntent));
        bidToken = swapIntent.auctionBaseCurrency;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
