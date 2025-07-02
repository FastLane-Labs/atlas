//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IAtlas } from "../interfaces/IAtlas.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";

import { CallBits } from "../libraries/CallBits.sol";
import { AccountingMath } from "../libraries/AccountingMath.sol";
import { CallVerification } from "../libraries/CallVerification.sol";
import { SafeBlockNumber } from "../libraries/SafeBlockNumber.sol";

import { AtlasConstants } from "../types/AtlasConstants.sol";
import "../types/UserOperation.sol";
import "../types/SolverOperation.sol";
import "../types/DAppOperation.sol";
import "../types/ConfigTypes.sol";

contract Sorter is AtlasConstants {
    using CallBits for uint32;
    using CallVerification for UserOperation;
    using AccountingMath for uint256;

    IAtlas public immutable ATLAS;
    IAtlasVerification public immutable VERIFICATION;

    struct SortingData {
        uint256 amount;
        bool valid;
    }

    constructor(address _atlas) {
        ATLAS = IAtlas(_atlas);
        VERIFICATION = IAtlasVerification(ATLAS.VERIFICATION());
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

    /// @dev Verifies that the solver is eligible
    /// @dev Does not check solver signature as it might be trusted (solverOp.from == bundler)
    /// @dev Checks other than signature are same as those done in `verifySolverOp()` in AtlasVerification and
    /// `_validateSolverOpGasAndValue()` and `_validateSolverOpDeadline()` in Atlas
    function _verifySolverEligibility(
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        uint256 totalSurchargeRate
    )
        internal
        view
        returns (bool)
    {
        // Make sure the solver has enough funds bonded
        uint256 solverBalance = ATLAS.balanceOfBonded(solverOp.from);

        // solverOp.gas has a ceiling of dConfig.solverGasLimit
        uint256 solverOpGasLimit = Math.min(solverOp.gas, dConfig.solverGasLimit);

        // Calldata gas a winning solver would pay for: non-solverOp calldata + their own solverOp calldata
        uint256 calldataGas = (
            USER_OP_STATIC_LENGTH + DAPP_OP_LENGTH + _SOLVER_OP_STATIC_LENGTH + _EXTRA_CALLDATA_LENGTH
                + userOp.data.length + solverOp.data.length
        ) * _GAS_PER_CALLDATA_BYTE;

        // Execution gas a winning solver would pay for
        uint256 executionGas = _BASE_TX_GAS_USED + _PRE_EXECUTE_METACALL_GAS + _POST_SETTLE_METACALL_GAS
            + solverOpGasLimit + userOp.gas + dConfig.dappGasLimit;

        uint256 maxSolverCost = (solverOp.maxFeePerGas * (executionGas + calldataGas)).withSurcharge(totalSurchargeRate);

        if (solverBalance < maxSolverCost) {
            return false;
        }

        // solverOp.to must be the atlas address
        if (solverOp.to != address(ATLAS)) {
            return false;
        }

        // Solvers can only do one tx per block - this prevents double counting bonded balances
        uint256 solverLastActiveBlock = ATLAS.accountLastActiveBlock(solverOp.from);
        if (solverLastActiveBlock >= SafeBlockNumber.get()) {
            return false;
        }

        // Ensure the solver control address matches the configured dApp control address
        if (dConfig.to != solverOp.control) {
            return false;
        }

        // Make sure that the solver's maxFeePerGas matches or exceeds the user's
        if (solverOp.maxFeePerGas < userOp.maxFeePerGas) {
            return false;
        }

        // solverOp.solver must not be the atlas or verification address
        if (solverOp.solver == address(ATLAS) || solverOp.solver == address(VERIFICATION)) {
            return false;
        }

        // solverOp.deadline must be in the future
        if (solverOp.deadline != 0 && SafeBlockNumber.get() > solverOp.deadline) {
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

        uint256 totalSurchargeRate = ATLAS.getAtlasSurchargeRate() + userOp.bundlerSurchargeRate;

        SortingData[] memory sortingData = new SortingData[](count);

        bytes32 userOpHash = VERIFICATION.getUserOperationHash(userOp);

        uint256 invalid;
        for (uint256 i; i < count; ++i) {
            if (
                solverOps[i].userOpHash == userOpHash && _verifyBidFormat(bidToken, solverOps[i])
                    && _verifySolverEligibility(dConfig, userOp, solverOps[i], totalSurchargeRate)
            ) {
                sortingData[i] = SortingData({ amount: solverOps[i].bidAmount, valid: true });
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
