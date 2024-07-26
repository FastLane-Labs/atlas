//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

contract FastLaneOnlineErrors {
    // FastLaneControl.sol
    error FLOnlineControl_PreSolver_BuyTokenMismatch();
    error FLOnlineControl_PreSolver_SellTokenMismatch();
    error FLOnlineControl_PreSolver_BidBelowReserve();

    error FLOnlineControl_PostOps_BalanceOfFailed1();
    error FLOnlineControl_PostOps_BalanceOfFailed2();
    error FLOnlineControl_PostOps_BaselineCallFailed();
    error FLOnlineControl_PostOps_ReserveNotMet();

    // FastLaneOnlineInner.sol
    error FLOnlineInner_Swap_OnlyAtlas();
    error FLOnlineInner_Swap_MustBeDelegated();
    error FLOnlineInner_Swap_BuyAndSellTokensAreSame();
    error FLOnlineInner_Swap_ControlNotUser();
    error FLOnlineInner_Swap_ControlNotBundler();
    error FLOnlineInner_Swap_UserNotLocked();
    error FLOnlineInner_Swap_SellFundsUnavailable();

    error FLOnlineInner_BaselineSwapWrapper_NotActiveEnv();
    error FLOnlineInner_BaselineSwapWrapper_IncorrectPhase();
    error FLOnlineInner_BaselineSwapWrapper_CallerIsNotAtlas();
    error FLOnlineInner_BaselineSwapWrapper_BalanceOfFailed1();
    error FLOnlineInner_BaselineSwapWrapper_BalanceOfFailed2();
    error FLOnlineInner_BaselineSwapWrapper_BaselineCallFailed();
    error FLOnlineInner_BaselineSwapWrapper_NoBalanceIncrease();

    // SolverGateway.sol
    error SolverGateway_AddSolverOp_ValueTooLow();

    error SolverGateway_RefundCongestionBuyIns_DeadlineNotPassed();

    error SolverGateway_PreValidateSolverOp_MsgSenderIsNotSolver();
    error SolverGateway_PreValidateSolverOp_Unverified();
    error SolverGateway_PreValidateSolverOp_UserOpHashMismatch_Nonce();
    error SolverGateway_PreValidateSolverOp_UserOpHashMismatch_Solver();
    error SolverGateway_PreValidateSolverOp_DeadlinePassed();
    error SolverGateway_PreValidateSolverOp_DeadlineInvalid();
    error SolverGateway_PreValidateSolverOp_InvalidSolverGasPrice();
    error SolverGateway_PreValidateSolverOp_BuyTokenMismatch();
    error SolverGateway_PreValidateSolverOp_SellTokenMismatch();
    error SolverGateway_PreValidateSolverOp_BidTooLow();
    error SolverGateway_PreValidateSolverOp_SellTokenZeroAddress();
    error SolverGateway_PreValidateSolverOp_BuyTokenZeroAddress();
    error SolverGateway_PreValidateSolverOp_InvalidControl();
    error SolverGateway_PreValidateSolverOp_UserGasTooLow();
    error SolverGateway_PreValidateSolverOp_SolverGasTooHigh();
    error SolverGateway_PreValidateSolverOp_BondedTooLow();
    error SolverGateway_PreValidateSolverOp_DoubleSolve();

    // FLOnlineOuter.sol
    error FLOnlineOuter_FastOnlineSwap_UserOpHashMismatch();

    error FLOnlineOuter_ValidateSwap_DeadlinePassed();
    error FLOnlineOuter_ValidateSwap_InvalidGasPrice();
    error FLOnlineOuter_ValidateSwap_TxGasTooHigh();
    error FLOnlineOuter_ValidateSwap_TxGasTooLow();
    error FLOnlineOuter_ValidateSwap_GasLimitTooLow();
    error FLOnlineOuter_ValidateSwap_SellTokenZeroAddress();
    error FLOnlineOuter_ValidateSwap_BuyTokenZeroAddress();
}
