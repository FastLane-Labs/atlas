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
import { ISimulator } from "src/contracts/interfaces/ISimulator.sol";

import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { OuterHelpers } from "src/contracts/examples/fastlane-online/OuterHelpers.sol";

import { SwapIntent, BaselineCall, Reputation } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

contract SolverGateway is OuterHelpers {
    uint256 public constant USER_GAS_BUFFER = 500_000;
    uint256 public constant METACALL_GAS_BUFFER = 200_000;
    uint256 public constant MAX_SOLVER_GAS = 500_000;

    uint256 internal constant _SLIPPAGE_BASE = 100;
    uint256 internal constant _GLOBAL_MAX_SLIPPAGE = 125; // A lower slippage set by user will override this.

    constructor(address _atlas, address _simulator) OuterHelpers(_atlas, _simulator) {}

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
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        external
        payable
        onlyAsControl
        withUserLock(solverOp.from)
    {
        require(msg.sender == solverOp.from, "ERR - SOLVER MUST BE SENDER");

        // Simulate the SolverOp and make sure it's valid
        require(_simulateSolverOp(userOp, solverOp), "ERR - SIMULATION FAIL");

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        (bool _pushAsNew, bool _replaceExisting, uint256 _replacedIndex) =
            _evaluateForInclusion(userOp, solverOp);

        if (_pushAsNew) {
            _pushSolverOp(solverOp.userOpHash, _solverOpHash);
        } else if (_replaceExisting) {
            _replaceSolverOp(solverOp.userOpHash, _solverOpHash, _replacedIndex);
        } else {
            revert("ERR - VALUE TOO LOW");
        }

        // Store the op
        S_solverOpCache[_solverOpHash] = solverOp;
    }

    function refundCongestionBuyIns(SolverOperation calldata solverOp) external withUserLock(solverOp.from) onlyAsControl {
        // NOTE: Anyone can call this on behalf of the solver
        // NOTE: the solverOp deadline cannot be before the userOp deadline, therefore if the
        // solverOp deadline is passed then we know the userOp deadline is passed.
        require(solverOp.deadline < block.number, "ERR - DEADLINE NOT PASSED");

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
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        internal
        view
        returns (bool pushAsNew, bool replaceExisting, uint256)
    {
        (SolverOperation[] memory _solverOps, uint256 _cumulativeGasReserved) = _getSolverOps(solverOp.userOpHash);

        if (_solverOps.length == 0) {
            return (true, false, 0);
        }

        (SwapIntent memory swapIntent,) = abi.decode(userOp.data[4:], (SwapIntent, BaselineCall));

        (uint256 _cumulativeScore, uint256 _replacedIndex) =
            _getCumulativeScores(swapIntent, _solverOps, userOp.gas, userOp.maxFeePerGas);

        uint256 _score =
            _getWeightedScoreNewSolver(userOp.gas, userOp.maxFeePerGas, swapIntent.minAmountUserBuys, _solverOps.length, solverOp);

        // Check can be grokked more easily in the following format:
        //      solverOpScore    _cumulativeScore (unweighted)
        // if  -------------- >  ------------------------------  * 2
        //      solverOpGas             totalGas
        if (_score * userOp.gas > _cumulativeScore * solverOp.gas * 2) {
            if (_cumulativeGasReserved + USER_GAS_BUFFER + (solverOp.gas * 2) < userOp.gas) {
                return (true, false, 0);
            } else {
                return (false, true, _replacedIndex);
            }
        }
        return (false, false, 0);
    }

    function _getCumulativeScores(
        SwapIntent memory swapIntent,
        SolverOperation[] memory solverOps,
        uint256 gas,
        uint256 maxFeePerGas
    )
        internal
        view
        returns (uint256 cumulativeScore, uint256 replacedIndex)
    {
        uint256 _lowestScore;
        uint256 _length = solverOps.length;
        for (uint256 _i; _i < _length; _i++) {
            SolverOperation memory _solverOp = solverOps[_i];

            uint256 _score =
                _getWeightedScore(gas, maxFeePerGas, swapIntent.minAmountUserBuys, _length, _solverOp);

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
        // Get the app-specific reputation
        Reputation memory _rep = S_solverReputations[solverOp.from];

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));
        uint256 _congestionBuyIn = S_congestionBuyIn[_solverOpHash];

        uint256 _bidFactor = (solverOp.bidAmount ** 2) * _SLIPPAGE_BASE / (minAmountUserBuys + 1) ** 2;
        if (_bidFactor > _GLOBAL_MAX_SLIPPAGE) _bidFactor = _GLOBAL_MAX_SLIPPAGE;

        score = (
            (_congestionBuyIn + (maxFeePerGas * totalGas)) // A solver typically has to pay maxFeePerGas * gas as a
                // requirement for winning.
                * totalGas / (totalGas + solverOp.gas) // double count gas by doing this even in unweighted score (there's
                // value in packing more solutions)
                * (uint256(_rep.successCost) + (maxFeePerGas * totalGas))
                / (uint256(_rep.failureCost) + (maxFeePerGas * totalGas * (solverCount + 1))) // as solverCount increases,
                // the dilution of thin auction history increases.
                * _bidFactor / solverOp.gas
        );
    }

    function _getWeightedScoreNewSolver(
        uint256 totalGas,
        uint256 maxFeePerGas,
        uint256 minAmountUserBuys,
        uint256 solverCount,
        SolverOperation calldata solverOp
    )
        internal
        view
        returns (uint256 score)
    {
        // Get the app-specific reputation
        Reputation memory _rep = S_solverReputations[solverOp.from];

        // Congestion buyin is the msg.value
        uint256 _congestionBuyIn = msg.value;

        uint256 _bidFactor = (solverOp.bidAmount ** 2) * _SLIPPAGE_BASE / (minAmountUserBuys + 1) ** 2;
        if (_bidFactor > _GLOBAL_MAX_SLIPPAGE) _bidFactor = _GLOBAL_MAX_SLIPPAGE;

        score = (
            (_congestionBuyIn + (maxFeePerGas * totalGas)) // A solver typically has to pay maxFeePerGas * gas as a
                // requirement for winning.
                * totalGas / (totalGas + solverOp.gas) // double count gas by doing this even in unweighted score (there's
                // value in packing more solutions)
                * (uint256(_rep.successCost) + (maxFeePerGas * totalGas))
                / (uint256(_rep.failureCost) + (maxFeePerGas * totalGas * (solverCount + 1))) // as solverCount increases,
                // the dilution of thin auction history increases.
                * _bidFactor / solverOp.gas
        );
    }
}
