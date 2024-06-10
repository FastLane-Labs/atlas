//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IAtlETH } from "../interfaces/IAtlETH.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { CallBits } from "src/contracts/libraries/CallBits.sol";
import { CallVerification } from "../libraries/CallVerification.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

contract Sorter {
    using CallBits for uint32;
    using CallVerification for UserOperation;

    address public immutable atlas;

    struct SortingData {
        uint256 amount;
        bool valid;
    }

    constructor(address _atlas) {
        atlas = _atlas;
    }

    function sortBids(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps
    )
        external
        view
        returns (SolverOperation[] memory)
    {
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);

        uint256 count = solverOps.length;

        (SortingData[] memory sortingData, uint256 invalid) = _getSortingData(dConfig, userOp, solverOps, count);

        uint256[] memory sorted = _sort(sortingData, count, invalid);

        count -= invalid;
        SolverOperation[] memory solverOpsSorted = new SolverOperation[](count);

        for (uint256 i; i < count; ++i) {
            solverOpsSorted[i] = solverOps[sorted[i]];
        }

        return solverOpsSorted;
    }

    function _verifyBidFormat(address bidToken, SolverOperation calldata solverOp) internal pure returns (bool) {
        return solverOp.bidToken == bidToken;
    }

    function _verifySolverEligibility(
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        internal
        view
        returns (bool)
    {
        // Make sure the solver has enough funds bonded
        uint256 solverBalance = IAtlETH(atlas).balanceOfBonded(solverOp.from);
        if (solverBalance < solverOp.maxFeePerGas * solverOp.gas) {
            return false;
        }

        // Solvers can only do one tx per block - this prevents double counting bonded balances
        uint256 solverLastActiveBlock = IAtlETH(atlas).accountLastActiveBlock(solverOp.from);
        if (solverLastActiveBlock >= block.number) {
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
    )
        internal
        view
        returns (SortingData[] memory, uint256)
    {
        address bidToken = IDAppControl(dConfig.to).getBidFormat(userOp);

        SortingData[] memory sortingData = new SortingData[](count);

        bytes32 userOpHash =
            dConfig.callConfig.allowsTrustedOpHash() ? userOp.getAltOperationHash() : userOp.getUserOperationHash();

        uint256 invalid;
        for (uint256 i; i < count; ++i) {
            if (
                solverOps[i].userOpHash == userOpHash && _verifyBidFormat(bidToken, solverOps[i])
                    && _verifySolverEligibility(dConfig, userOp, solverOps[i])
            ) {
                sortingData[i] =
                    SortingData({ amount: IDAppControl(dConfig.to).getBidValue(solverOps[i]), valid: true });
            } else {
                sortingData[i] = SortingData({ amount: 0, valid: false });
                unchecked {
                    ++invalid;
                }
            }
        }

        return (sortingData, invalid);
    }

    function _sort(
        SortingData[] memory sortingData,
        uint256 count,
        uint256 invalid
    )
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory sorted = new uint256[](count - invalid);
        if (sorted.length == 0) {
            return sorted;
        }

        int256 topBidAmount;
        int256 topBidIndex;

        for (uint256 i; i < sorted.length; ++i) {
            topBidAmount = -1;
            topBidIndex = -1;

            for (uint256 j; j < count; ++j) {
                if (sortingData[j].valid && int256(sortingData[j].amount) > topBidAmount) {
                    topBidAmount = int256(sortingData[j].amount);
                    topBidIndex = int256(j);
                }
            }

            if (topBidIndex == -1) {
                // all indices in sorting data are invalid
                break;
            }

            sortingData[uint256(topBidIndex)].valid = false;
            sorted[i] = uint256(topBidIndex);
        }

        return sorted;
    }
}
