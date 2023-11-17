//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {IDAppControl} from "../interfaces/IDAppControl.sol";
import {IAtlETH} from "../interfaces/IAtlETH.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract Sorter {

    address immutable public atlas;
    address immutable public escrow;

    constructor(address _atlas, address _escrow) {
        atlas = _atlas;
        escrow = _escrow;
    }

    struct SortingData {
        uint256 amount;
        bool valid;
    }

    function sortBids(
        UserOperation calldata userOp, 
        SolverOperation[] calldata solverOps
    ) external view returns (SolverOperation[] memory) {

        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);

        uint256 count = solverOps.length;

        (SortingData[] memory sortingData, uint256 invalid) = _getSortingData(
            dConfig, userOp, solverOps, count);

        uint256[] memory sorted = _sort(sortingData, count, invalid);

        SolverOperation[] memory solverOpsSorted = new SolverOperation[](count - invalid);

        count -= invalid;
        uint256 i = 0;

        for (;i<count;) {
            solverOpsSorted[i] = solverOps[sorted[i]];
            unchecked { ++i; }
        }

        return solverOpsSorted;
    }

    function _verifyBidFormat(
        address bidToken, 
        SolverOperation calldata solverOp
    ) internal pure returns (bool) {
        if (solverOp.bidToken != bidToken) {
            return false;
        }
            
        return true;
    }

    function _verifySolverEligibility(
        DAppConfig memory dConfig,
        UserOperation calldata userOp, 
        SolverOperation calldata solverOp
    ) internal view returns (bool) {
        // Verify that the solver submitted the correct callhash
        bytes32 userOpHash = CallVerification.getUserOperationHash(userOp);
        if (solverOp.userOpHash != userOpHash) {
            return false;
        }

        // Make sure the solver has enough funds escrowed
        // TODO: subtract any pending withdrawals
        uint256 solverBalance = IAtlETH(escrow).balanceOf(solverOp.from);
        if (solverBalance < solverOp.maxFeePerGas * solverOp.gas) {
            return false;
        }

        // Solvers can only do one tx per block - this prevents double counting escrow balances.
        // TODO: Add in "targetBlockNumber" as an arg?
        uint256 solverLastActiveBlock = IAtlETH(escrow).accountLastActiveBlock(solverOp.from);
        if (solverLastActiveBlock >= block.number) {
            return false;
        }

        // Make sure the solver nonce is accurate
        uint256 nextSolverNonce = IAtlETH(escrow).nextAccountNonce(solverOp.from);
        if (nextSolverNonce != solverOp.nonce) {
            return false;
        }

        // Make sure that the solver has the correct codehash for dApp control contract
        if (dConfig.to != solverOp.control) {
            return false;
        }

        // Make sure that the solver's maxFeePerGas matches or exceeds the user's
        if (solverOp.maxFeePerGas < userOp.maxFeePerGas) {
            return false;
        }

        return true;
    }

    function _getSortingData(
        DAppConfig memory dConfig, 
        UserOperation calldata userOp, 
        SolverOperation[] calldata solverOps,
        uint256 count
    ) internal view returns (SortingData[] memory, uint256){

        address bidToken = IDAppControl(dConfig.to).getBidFormat(userOp);

        SortingData[] memory sortingData = new SortingData[](count);

        uint256 i;
        uint256 invalid;
        for (;i<count;) {
            if (
                _verifyBidFormat(bidToken, solverOps[i]) && 
                _verifySolverEligibility(dConfig, userOp, solverOps[i])
            ) {
                sortingData[i] = SortingData({
                    amount: IDAppControl(dConfig.to).getBidValue(solverOps[i]),
                    valid: true
                });
                

            } else {
                sortingData[i] = SortingData({
                    amount: 0,
                    valid: false
                });
                unchecked{ ++invalid; }
            }
            unchecked{ ++i; }            
        }

        return (sortingData, invalid);
    }

    function _sort(
        SortingData[] memory sortingData,
        uint256 count,
        uint256 invalid
    ) internal pure returns (uint256[] memory) {

        uint256[] memory sorted = new uint256[](count - invalid);

        uint256 n; // outer loop counter
        uint256 i; // inner loop counter

        uint256 topBid;
        uint256 bottomBid;

        for (;invalid<count;) {

            // Reset the ceiling / floor
            topBid = 0;
            bottomBid = type(uint256).max;

            // Loop through and find the highest and lowest remaining valid bids
            for(;i<sortingData.length;) {
                if (sortingData[i].valid) {
                    if (sortingData[i].amount > topBid) {
                        sorted[n] = i;
                    }
                    if (sortingData[i].amount < bottomBid) {
                        sorted[count-1-n] = i;
                    }
                }
                unchecked {++i;}
            }

            // Mark the lowest & highest bids invalid (Used)
            sortingData[sorted[n]].valid = false;
            sortingData[sorted[count-1-n]].valid = false;

            unchecked { invalid +=2; }
            unchecked { ++n; }
        }

        return sorted;
    }
}