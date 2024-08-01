//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { DAppOperation } from "src/contracts/types/DAppOperation.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/EscrowTypes.sol";

// Interface Import
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";

import { BaselineSwapper } from "src/contracts/examples/fastlane-online/BaselineSwapper.sol";
import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { OuterHelpers } from "src/contracts/examples/fastlane-online/OuterHelpers.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

contract SolverGateway is OuterHelpers {
    uint256 public constant USER_GAS_BUFFER = 500_000;
    uint256 public constant METACALL_GAS_BUFFER = 200_000;
    uint256 public constant MAX_SOLVER_GAS = 350_000;

    uint256 internal constant _GAS_USED_DECIMALS_TO_DROP = 1000; // Must match Atlas contract's value
    uint256 internal constant _SLIPPAGE_BASE = 100;
    uint256 internal constant _GLOBAL_MAX_SLIPPAGE = 125; // A lower slippage set by user will override this.

    address public immutable BASELINE_SWAPPER;

    constructor(address _atlas) OuterHelpers(_atlas) {
        BaselineSwapper _baselineSwapper = new BaselineSwapper();
        BASELINE_SWAPPER = address(_baselineSwapper);
    }

    /////////////////////////////////////////////////////////
    //              CONTROL-LOCAL FUNCTIONS                //
    //                 (not delegated)                     //
    /////////////////////////////////////////////////////////

    /////////////////////////////////////////////////////////
    //              EXTERNAL INTERFACE FUNCS               //
    /////////////////////////////////////////////////////////
    //                  FOR SOLVERS                        //
    /////////////////////////////////////////////////////////
    function addSolverOp(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas,
        bytes32 userOpHash,
        address swapper,
        SolverOperation calldata solverOp
    )
        external
        payable
        onlyAsControl
        withUserLock
    {
        EscrowAccountAccessData memory _aData =
            _preValidateSolverOp(swapIntent, baselineCall, deadline, gas, maxFeePerGas, userOpHash, swapper, solverOp);

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        (bool _pushAsNew, bool _replaceExisting, uint256 _replacedIndex) =
            _evaluateForInclusion(swapIntent, gas, maxFeePerGas, solverOp, _aData);

        if (_pushAsNew) {
            _pushSolverOp(userOpHash, _solverOpHash);
        } else if (_replaceExisting) {
            _replaceSolverOp(userOpHash, _solverOpHash, _replacedIndex);
        } else {
            revert SolverGateway_AddSolverOp_ValueTooLow();
        }

        // Store the op
        S_solverOpCache[_solverOpHash] = solverOp;
    }

    function refundCongestionBuyIns(SolverOperation calldata solverOp) external withUserLock onlyAsControl {
        // NOTE: Anyone can call this on behalf of the solver
        // NOTE: the solverOp deadline cannot be before the userOp deadline, therefore if the
        // solverOp deadline is passed then we know the userOp deadline is passed.
        if (solverOp.deadline >= block.number) {
            revert SolverGateway_RefundCongestionBuyIns_DeadlineNotPassed();
        }

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        uint256 _congestionBuyIn = S_congestionBuyIn[_solverOpHash];
        uint256 _aggCongestionBuyIn = S_aggCongestionBuyIn[solverOp.userOpHash];

        // NOTE: On successful execution, the _aggCongestionBuyIn is set to zero
        // but the individual _congestionBuyIns are not, so verify both.
        if (_congestionBuyIn > 0 && _aggCongestionBuyIn >= _congestionBuyIn) {
            delete S_congestionBuyIn[_solverOpHash];
            S_aggCongestionBuyIn[solverOp.userOpHash] -= _congestionBuyIn;

            SafeTransferLib.safeTransferETH(solverOp.from, _congestionBuyIn);
        }
    }

    /////////////////////////////////////////////////////////
    //              EXTERNAL INTERFACE FUNCS               //
    //                  FOR DAPP CONTROL                   //
    /////////////////////////////////////////////////////////
    function getBidAmount(bytes32 solverOpHash) external view returns (uint256 bidAmount) {
        return S_solverOpCache[solverOpHash].bidAmount;
    }

    /////////////////////////////////////////////////////////
    //                   INTERNAL FUNCS                    //
    /////////////////////////////////////////////////////////
    function _pushSolverOp(bytes32 userOpHash, bytes32 solverOpHash) internal {
        // Push to array
        S_solverOpHashes[userOpHash].push(solverOpHash);

        // Accounting
        if (msg.value > 0) {
            S_aggCongestionBuyIn[userOpHash] += msg.value;
            S_congestionBuyIn[solverOpHash] = msg.value;
        }
    }

    function _replaceSolverOp(bytes32 userOpHash, bytes32 solverOpHash, uint256 replacedIndex) internal {
        // Handle the removed solverOp
        bytes32 _replacedHash = S_solverOpHashes[userOpHash][replacedIndex];
        uint256 _replacedCongestionBuyIn = S_congestionBuyIn[_replacedHash];

        // Handle xfer back
        if (_replacedCongestionBuyIn > 0) {
            // Accounting (remove balance before xfer)
            delete S_congestionBuyIn[_replacedHash];

            SolverOperation memory _replacedSolverOp = S_solverOpCache[solverOpHash];

            if (_replacedSolverOp.from.code.length == 0) {
                // Transfer their congestion buyin back
                SafeTransferLib.safeTransferETH(_replacedSolverOp.from, _replacedCongestionBuyIn);
            }
        }

        // Accounting
        if (_replacedCongestionBuyIn > msg.value) {
            S_aggCongestionBuyIn[userOpHash] -= (_replacedCongestionBuyIn - msg.value);
        } else if (_replacedCongestionBuyIn < msg.value) {
            S_aggCongestionBuyIn[userOpHash] += (msg.value - _replacedCongestionBuyIn);
        } // if they're equal, do nothing.

        if (msg.value > 0) {
            S_congestionBuyIn[solverOpHash] = msg.value;
        }

        S_solverOpHashes[userOpHash][replacedIndex] = solverOpHash;
    }

    function _getSolverOps(bytes32 userOpHash)
        internal
        view
        returns (SolverOperation[] memory solverOps, uint256 cumulativeGasReserved)
    {
        uint256 _totalSolvers = S_solverOpHashes[userOpHash].length;

        solverOps = new SolverOperation[](_totalSolvers);

        for (uint256 _j; _j < _totalSolvers; _j++) {
            bytes32 _solverOpHash = S_solverOpHashes[userOpHash][_j];
            SolverOperation memory _solverOp = S_solverOpCache[_solverOpHash];
            solverOps[_j] = _solverOp;
            cumulativeGasReserved += _solverOp.gas;
        }
    }

    function _evaluateForInclusion(
        SwapIntent calldata swapIntent,
        uint256 totalGas,
        uint256 maxFeePerGas,
        SolverOperation calldata solverOp,
        EscrowAccountAccessData memory aData
    )
        internal
        view
        returns (bool pushAsNew, bool replaceExisting, uint256)
    {
        (SolverOperation[] memory _solverOps, uint256 _cumulativeGasReserved) = _getSolverOps(solverOp.userOpHash);

        if (_solverOps.length == 0) {
            return (true, false, 0);
        }

        (uint256 _cumulativeScore, uint256 _replacedIndex) =
            _getCumulativeScores(swapIntent, _solverOps, totalGas, maxFeePerGas);

        uint256 _score =
            _getWeightedScore(swapIntent, solverOp, totalGas, msg.value, maxFeePerGas, _solverOps.length, aData);

        // Check can be grokked more easily in the following format:
        //      solverOpScore    _cumulativeScore (unweighted)
        // if  -------------- >  ------------------------------  * 2
        //      solverOpGas             totalGas
        if (_score * totalGas > _cumulativeScore * solverOp.gas * 2) {
            if (_cumulativeGasReserved + USER_GAS_BUFFER + (solverOp.gas * 2) < totalGas) {
                return (true, false, 0);
            } else {
                return (false, true, _replacedIndex);
            }
        }
        return (false, false, 0);
    }

    function _getCumulativeScores(
        SwapIntent calldata swapIntent,
        SolverOperation[] memory solverOps,
        uint256 gas,
        uint256 maxFeePerGas
    )
        internal
        view
        returns (uint256 cumulativeScore, uint256 replacedIndex)
    {
        uint256 _lowestScore;
        for (uint256 _i; _i < solverOps.length; _i++) {
            SolverOperation memory _solverOp = solverOps[_i];

            uint256 _score =
                _getWeightedScore(gas, maxFeePerGas, swapIntent.minAmountUserBuys, solverOps.length, _solverOp);

            if (_i == 0 || _score < _lowestScore) {
                replacedIndex = _i;
                _lowestScore = _score;
            }

            cumulativeScore += _score;
        }
    }

    function _getWeightedScore(
        uint256 totalGas,
        uint256 maxFeePerGas,
        uint256 minAmountUserBuys,
        uint256 solverCount,
        SolverOperation memory solverOp
    )
        internal
        view
        returns (uint256 score)
    {
        EscrowAccountAccessData memory _aData = _getAccessData(solverOp.from);
        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));
        uint256 _congestionBuyIn = S_congestionBuyIn[_solverOpHash];

        uint256 _bidFactor = (solverOp.bidAmount ** 2) * _SLIPPAGE_BASE / (minAmountUserBuys + 1) ** 2;
        if (_bidFactor > _GLOBAL_MAX_SLIPPAGE) _bidFactor = _GLOBAL_MAX_SLIPPAGE;

        score = (
            (_congestionBuyIn + (maxFeePerGas * totalGas)) // A solver typically has to pay maxFeePerGas * gas as a
                // requirement for winning.
                * totalGas / (totalGas + solverOp.gas) // double count gas by doing this even in unweighted score (there's
                // value in packing more solutions)
                * (uint256(_aData.auctionWins) + 1)
                / (uint256(_aData.auctionWins + _aData.auctionFails) + solverCount ** 2 + 1) // as solverCount increases,
                // the dilution of thin auction history increases.
                * _bidFactor / solverOp.gas
        );
    }

    function _getWeightedScore(
        SwapIntent calldata swapIntent,
        SolverOperation calldata solverOp,
        uint256 totalGas,
        uint256 congestionBuyIn,
        uint256 maxFeePerGas,
        uint256 solverCount,
        EscrowAccountAccessData memory aData
    )
        internal
        pure
        returns (uint256 score)
    {
        uint256 _bidFactor = (solverOp.bidAmount ** 2) * _SLIPPAGE_BASE / (swapIntent.minAmountUserBuys + 1) ** 2;
        if (_bidFactor > _GLOBAL_MAX_SLIPPAGE) _bidFactor = _GLOBAL_MAX_SLIPPAGE;

        score = (
            (congestionBuyIn + (maxFeePerGas * totalGas)) // A solver typically has to pay maxFeePerGas * gas as a
                // requirement for winning.
                * totalGas / (totalGas + solverOp.gas) // double count gas by doing this even in unweighted score (there's
                // value in packing more solutions)
                * (uint256(aData.auctionWins) + 1)
                / (uint256(aData.auctionWins + aData.auctionFails) + solverCount ** 2 + 1) * _bidFactor / solverOp.gas
        );
    }

    function _preValidateSolverOp(
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas,
        bytes32 userOpHash,
        address swapper,
        SolverOperation calldata solverOp
    )
        internal
        view
        returns (EscrowAccountAccessData memory aData)
    {
        if (msg.sender != solverOp.from) {
            revert SolverGateway_PreValidateSolverOp_MsgSenderIsNotSolver();
        }

        UserOperation memory _userOp = _getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas);
        bytes32 _userOpHash = _getUserOperationHash(_userOp);

        // Verify the signature
        uint256 _verificationResult = IAtlasVerification(ATLAS_VERIFICATION).verifySolverOp(
            solverOp, _userOpHash, maxFeePerGas, address(this), false
        );
        if (_verificationResult != 0 && _verificationResult != (1 << uint256(SolverOutcome.GasPriceOverCap))) {
            revert SolverGateway_PreValidateSolverOp_Unverified();
        }
        // Make sure the calculated UserOpHash matches the actual UserOpHash. Because the User's nonce is a part of the
        // hash,
        // this ensures that Solvers can't add their solution to an intent that's already been executed (with its nonce
        // incremented).
        if (userOpHash != _userOpHash) {
            revert SolverGateway_PreValidateSolverOp_UserOpHashMismatch_Nonce();
        }
        if (userOpHash != solverOp.userOpHash) {
            revert SolverGateway_PreValidateSolverOp_UserOpHashMismatch_Solver();
        }

        // Check deadlines
        if (deadline < block.number) {
            revert SolverGateway_PreValidateSolverOp_DeadlinePassed();
        }
        if (solverOp.deadline < deadline) {
            revert SolverGateway_PreValidateSolverOp_DeadlineInvalid();
        }

        // Gas
        if (solverOp.maxFeePerGas < maxFeePerGas) {
            revert SolverGateway_PreValidateSolverOp_InvalidSolverGasPrice();
        }

        // Make sure the token is correct
        if (solverOp.bidToken != swapIntent.tokenUserBuys) {
            revert SolverGateway_PreValidateSolverOp_BuyTokenMismatch();
        }
        if (solverOp.bidToken == swapIntent.tokenUserSells) {
            revert SolverGateway_PreValidateSolverOp_SellTokenMismatch();
        }
        if (solverOp.bidAmount < swapIntent.minAmountUserBuys) {
            revert SolverGateway_PreValidateSolverOp_BidTooLow();
        }
        if (swapIntent.tokenUserSells == address(0)) {
            revert SolverGateway_PreValidateSolverOp_SellTokenZeroAddress();
        }
        if (swapIntent.tokenUserBuys == address(0)) {
            revert SolverGateway_PreValidateSolverOp_BuyTokenZeroAddress();
        }

        // Validate control address
        if (solverOp.control != CONTROL) {
            revert SolverGateway_PreValidateSolverOp_InvalidControl();
        }

        // Make sure no tomfoolery
        if (solverOp.to == address(this)) revert SolverGateway_PreValidateSolverOp_SneakySneaky();
        if (solverOp.to == BASELINE_SWAPPER) revert SolverGateway_PreValidateSolverOp_AWiseGuyEh();

        // Get the access data
        aData = _getAccessData(msg.sender);

        // Check gas limits
        if (gas <= USER_GAS_BUFFER + MAX_SOLVER_GAS * 2) {
            revert SolverGateway_PreValidateSolverOp_UserGasTooLow();
        }
        if (solverOp.gas >= MAX_SOLVER_GAS) {
            revert SolverGateway_PreValidateSolverOp_SolverGasTooHigh();
        }
        if (uint256(aData.bonded) <= gas) {
            revert SolverGateway_PreValidateSolverOp_BondedTooLow();
        }

        // Check solver eligibility
        if (uint256(aData.lastAccessedBlock) >= block.number) {
            revert SolverGateway_PreValidateSolverOp_DoubleSolve();
        }
    }
}
