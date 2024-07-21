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

import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { OuterHelpers } from "src/contracts/examples/fastlane-online/OuterHelpers.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

contract SolverGateway is OuterHelpers {

    uint256 public constant USER_GAS_BUFFER = 500_000;
    uint256 public constant MAX_SOLVER_GAS = 350_000;
    uint256 private constant _CONGESTION_BASE = 1_000_000_000;

    constructor(address _atlas) OuterHelpers(_atlas) { }

    /////////////////////////////////////////////////////////
    //              CONTROL-LOCAL FUNCTIONS                //
    //                 (not delegated)                     //
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
        onlyWhenUnlocked 
    {   
        EscrowAccountAccessData memory _aData = _preValidateSolverOp(swapIntent, baselineCall, deadline, gas, maxFeePerGas, userOpHash, swapper, solverOp);

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));
        
        (bool _pushAsNew, bool _replaceExisting, uint256 _replacedIndex) = _evaluateForInclusion(
            swapIntent, gas, maxFeePerGas, solverOp, _aData);

        if (_pushAsNew) {
            S_solverOpHashes[userOpHash].push(_solverOpHash);
        } else if (_replaceExisting) {
            S_solverOpHashes[userOpHash][_replacedIndex] = _solverOpHash;
            // TODO: handle replaced solver's congestionBuyIn
        } else {
            revert("ERR - VALUE TOO LOW");
        }

        S_solverOpCache[_solverOpHash] = solverOp;
        S_congestionBuyIn[_solverOpHash] = msg.value;
    }

    function _evaluateForInclusion(
        SwapIntent calldata swapIntent,
        uint256 gas,
        uint256 maxFeePerGas,
        SolverOperation calldata solverOp,
        EscrowAccountAccessData memory aData
    ) internal view returns (bool pushAsNew, bool replaceExisting, uint256) {
        SolverOperation[] memory _solverOps = _getSolverOps(solverOp.userOpHash);

        if (_solverOps.length == 0) {
            return (true, false, 0);
        }

        (uint256 _cumulativeGasReserved, uint256 _cumulativeScore, uint256 _replacedIndex) = _getCumulativeScores(swapIntent, _solverOps, gas, maxFeePerGas);

        uint256 _score = _getWeightedScore(swapIntent, solverOp, gas, msg.value, maxFeePerGas, aData);

        if (_score * gas > _cumulativeScore * solverOp.gas * 2) {
            if (_cumulativeGasReserved + USER_GAS_BUFFER + (solverOp.gas*2) < gas) {
                return (true, false, 0);
            } else {
                return (false, true, _replacedIndex);
            }
        }
        return (false, false, 0);
    }

    function _getSolverOps(bytes32 userOpHash) internal view returns (SolverOperation[] memory solverOps) {
    
        uint256 _totalSolvers = S_solverOpHashes[userOpHash].length;

        solverOps = new SolverOperation[](_totalSolvers);

        for (uint256 _j; _j < _totalSolvers; _j++) {
            bytes32 _solverOpHash = S_solverOpHashes[userOpHash][_j];
            SolverOperation memory _solverOp = S_solverOpCache[_solverOpHash];
            solverOps[_j] = _solverOp;
        }
    }

    function _getCumulativeScores(SwapIntent calldata swapIntent, SolverOperation[] memory solverOps, uint256 gas, uint256 maxFeePerGas) 
        internal 
        view 
        returns (uint256 cumulativeGasReserved, uint256 cumulativeScore, uint256 replacedIndex) 
    {
        
        uint256 _lowestScore;
        for (uint256 _i; _i < solverOps.length; _i++) {
            
            SolverOperation memory _solverOp = solverOps[_i];
        
            uint256 _score = _getWeightedScore(gas, maxFeePerGas, swapIntent.minAmountUserBuys, _solverOp);

            if (_i == 0 || _score < _lowestScore) {
                replacedIndex = _i;
                _lowestScore = _score;
            }
            
            cumulativeScore += _score;
            cumulativeGasReserved += _solverOp.gas;
        }
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
        internal view returns (EscrowAccountAccessData memory aData) 
    {
        require(msg.sender == solverOp.from, "ERR - SOLVER MUST BE SENDER");

        UserOperation memory _userOp = _getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas);
        bytes32 _userOpHash = _getUserOperationHash(_userOp);

        // Make sure the calculated UserOpHash matches the actual UserOpHash. Because the User's nonce is a part of the hash,
        // this ensures that Solvers can't add their solution to an intent that's already been executed (with its nonce incremented).
        require(userOpHash == _userOpHash, "ERR - USER HASH MISMATCH (NONCE)");
        require(userOpHash == solverOp.userOpHash, "ERR - USER HASH MISMATCH (SOLVER)");

        // Check deadlines
        require(deadline >= block.number, "ERR - DEADLINE PASSED");
        require(solverOp.deadline >= deadline, "ERR - DEADLINE INVALID");

        require(solverOp.maxFeePerGas >= tx.gasprice, "ERR - LOW SOLVER GASPRICE");
        require(solverOp.maxFeePerGas >= maxFeePerGas, "ERR - INVALID SOLVER GASPRICE");

        // Make sure the token is correct
        require(solverOp.bidToken == swapIntent.tokenUserBuys, "ERR - BuyTokenMismatch");
        require(solverOp.bidToken != swapIntent.tokenUserSells, "ERR - SellTokenMismatch");
        require(solverOp.bidAmount >= swapIntent.minAmountUserBuys, "ERR - BID TOO LOW");

        // Validate control address
        require(solverOp.control == CONTROL, "ERR - INVALID CONTROL");
        
        // Get the access data
        aData = _getAccessData(msg.sender);

        // Check gas limits
        require(gas > USER_GAS_BUFFER + MAX_SOLVER_GAS * 2, "ERR - USER GAS TOO LOW");
        require(solverOp.gas < MAX_SOLVER_GAS, "ERR - SOLVER GAS TOO HIGH");
        require(uint256(aData.bonded) > gas, "ERR - BONDED TOO LOW");

        // Check solver eligibility
        require(uint256(aData.lastAccessedBlock) < block.number, "ERR - DOUBLE SOLVE");
    }

    function _getWeightedScore(
        uint256 gas, 
        uint256 maxFeePerGas,
        uint256 minAmountUserBuys, 
        SolverOperation memory solverOp
    ) 
        internal 
        view 
        returns (uint256 score) 
    {
        EscrowAccountAccessData memory _aData = _getAccessData(solverOp.from);
        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));
        uint256 _congestionBuyIn = S_congestionBuyIn[_solverOpHash];

        score = ( 
            (_congestionBuyIn + (maxFeePerGas * gas)) // A solver typically has to pay maxFeePerGas * gas as a requirement for winning.
                * gas 
                / (gas + solverOp.gas) // double count gas by doing this even in unweighted score (there's value in packing more solutions)
                * (uint256(_aData.auctionWins +1)**2)
                / (uint256(_aData.auctionWins + _aData.auctionFails +3)**2) // TODO: change the 3 into solverOps.length?
                * (solverOp.bidAmount > (minAmountUserBuys +1) * 2 ? (minAmountUserBuys +1) * 2 : solverOp.bidAmount)
                / (minAmountUserBuys +1)
                / solverOp.gas
        );
    }

    function _getWeightedScore(
        SwapIntent calldata swapIntent,
        SolverOperation calldata solverOp,
        uint256 gas, 
        uint256 congestionBuyIn, 
        uint256 maxFeePerGas,
        EscrowAccountAccessData memory aData
    ) 
        internal 
        pure 
        returns (uint256 score) 
    {
        score = ( 
            (congestionBuyIn + (maxFeePerGas * gas)) // A solver typically has to pay maxFeePerGas * gas as a requirement for winning.
                * gas 
                / (gas + solverOp.gas) // double count gas by doing this even in unweighted score (there's value in packing more solutions)
                * (uint256(aData.auctionWins +1)**2)
                / (uint256(aData.auctionWins + aData.auctionFails +3)**2) // TODO: change the 3 into solverOps.length?
                * (solverOp.bidAmount > (swapIntent.minAmountUserBuys +1) * 2 ? (swapIntent.minAmountUserBuys +1) * 2 : solverOp.bidAmount)
                / (swapIntent.minAmountUserBuys +1)
                / solverOp.gas
        );
    }
}