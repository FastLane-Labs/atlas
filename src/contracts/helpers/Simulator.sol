//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "../types/SolverOperation.sol";
import "../types/UserOperation.sol";
import "../types/LockTypes.sol";
import "../types/DAppOperation.sol";
import "../types/ConfigTypes.sol";
import "../types/ValidCalls.sol";
import "../types/EscrowTypes.sol";
import { AtlasErrors } from "../types/AtlasErrors.sol";
import { AtlasConstants } from "../types/AtlasConstants.sol";
import { AccountingMath } from "../libraries/AccountingMath.sol";
import { GasAccLib } from "../libraries/GasAccLib.sol";
import { CallBits } from "../libraries/CallBits.sol";
import { Result } from "../interfaces/ISimulator.sol";
import { IAtlas } from "../interfaces/IAtlas.sol";
import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IL2GasCalculator } from "../interfaces/IL2GasCalculator.sol";

contract Simulator is AtlasErrors, AtlasConstants {
    using CallBits for uint32;
    using AccountingMath for uint256;
    using GasAccLib for SolverOperation[];

    uint256 internal constant _SIM_GAS_SUGGESTED_BUFFER = 30_000;
    uint256 internal constant _SIM_GAS_BEFORE_METACALL = 10_000;

    address public immutable deployer;
    address public atlas;

    event DeployerWithdrawal(address indexed to, uint256 amount);

    constructor() {
        deployer = msg.sender;
    }

    /// @notice Returns an estimation of the gas limit for a metacall, given the supplied UserOperation and array of
    /// SolverOperations. This is the gas limit that the bundler should use when executing the metacall.
    /// @param userOp The UserOperation of the metacall.
    /// @param solverOps The array of SolverOperations of the metacall.
    /// @return The estimated gas limit for the metacall.
    function estimateMetacallGasLimit(
        UserOperation calldata userOp,
        SolverOperation[] memory solverOps
    )
        public
        view
        returns (uint256)
    {
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        address l2GasCalculator = IAtlas(atlas).L2_GAS_CALCULATOR();
        uint256 nonSolverCalldataLength =
            userOp.data.length + USER_OP_STATIC_LENGTH + DAPP_OP_LENGTH + _EXTRA_CALLDATA_LENGTH;
        uint256 solverOpsLen = solverOps.length;
        uint256 solverDataLenSum; // Calculated as sum of solverOps[i].data.length below
        uint256 allSolversExecutionGas; // Calculated as sum of solverOps[i].gas below

        for (uint256 i = 0; i < solverOpsLen; ++i) {
            // Sum calldata length of all solverOp.data fields in the array
            solverDataLenSum += solverOps[i].data.length;
            // Sum all solverOp.gas values in the array, each with a ceiling of dConfig.solverGasLimit
            allSolversExecutionGas += Math.min(solverOps[i].gas, dConfig.solverGasLimit);
        }

        uint256 metacallCalldataGas = (_SOLVER_OP_BASE_CALLDATA * solverOpsLen)
            + GasAccLib.calldataGas(solverDataLenSum, l2GasCalculator)
            + GasAccLib.metacallCalldataGas(nonSolverCalldataLength, l2GasCalculator);

        uint256 metacallExecutionGas = _BASE_TX_GAS_USED + AccountingMath._FIXED_GAS_OFFSET + userOp.gas
            + dConfig.dappGasLimit + allSolversExecutionGas;

        if (dConfig.callConfig.exPostBids()) {
            metacallExecutionGas += (solverOpsLen * _BID_FIND_OVERHEAD) + allSolversExecutionGas;
        }

        return metacallCalldataGas + metacallExecutionGas;
    }

    /// @notice Returns an estimation of the max amount (in native token) a winning solver could be charged, given the
    /// supplied UserOperation and SolverOperation, assuming the Atlas and Bundler surcharge rates do not change, and
    /// assuming the supplied solverOp wins.
    /// @param userOp The UserOperation of the metacall.
    /// @param solverOp The SolverOperation of the solver whose charge is being estimated.
    /// @return The estimated max gas charge in native token units.
    function estimateMaxSolverWinGasCharge(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        external
        view
        returns (uint256)
    {
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        uint256 bundlerSurchargeRate = userOp.bundlerSurchargeRate;
        uint256 atlasSurchargeRate = IAtlas(atlas).getAtlasSurchargeRate();
        uint256 totalGas;

        if (dConfig.callConfig.multipleSuccessfulSolvers()) {
            // If multipleSuccessfulSolvers = true, each solver only pays for their own gas usage.

            // Calculate solver gas obligation as if expecting a solver fault in handleSolverFailAccounting()
            uint256 _calldataGas =
                GasAccLib.solverOpCalldataGas(solverOp.data.length, IAtlas(atlas).L2_GAS_CALCULATOR());

            // Use solver's gas limit since we can't know actual execution gas beforehand
            totalGas = _calldataGas + solverOp.gas + _SOLVER_FAULT_OFFSET;
        } else {
            // If multipleSuccessfulSolvers = false, the winning solver pays for their own gas + the non-solver gas.

            // In exPostBid mode, solvers do not pay for calldata gas, and these calldata gas vars will be excluded.
            // In normal bid mode, solvers each pay for their own solverOp calldata gas, and the winning solver pays for
            // the other non-solver calldata gas as well. In this calculation, there's only 1 solverOp so no need to
            // subtract calldata of other solverOps as they aren't any.
            uint256 metacallCalldataLength = (_SOLVER_OP_BASE_CALLDATA + solverOp.data.length)
                + (USER_OP_STATIC_LENGTH + userOp.data.length) + DAPP_OP_LENGTH + _EXTRA_CALLDATA_LENGTH;

            uint256 metacallCalldataGas =
                GasAccLib.metacallCalldataGas(metacallCalldataLength, IAtlas(atlas).L2_GAS_CALCULATOR());

            uint256 metacallExecutionGas =
                _BASE_TX_GAS_USED + AccountingMath._FIXED_GAS_OFFSET + userOp.gas + userOp.dappGasLimit + solverOp.gas;

            totalGas = metacallExecutionGas;

            // Only add calldata costs if NOT in exPostBids mode
            if (!dConfig.callConfig.exPostBids()) {
                totalGas += metacallCalldataGas;
            }
        }

        // NOTE: In exPostBids mode, the bid-finding solverOp execution gas is written off. So no need to add here.

        return (totalGas * solverOp.maxFeePerGas).withSurcharge(bundlerSurchargeRate + atlasSurchargeRate);
    }

    function simUserOperation(UserOperation calldata userOp)
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        if (userOp.value > address(this).balance) revert SimulatorBalanceTooLow();

        SolverOperation[] memory solverOps = new SolverOperation[](0);
        DAppOperation memory dAppOp;
        dAppOp.to = atlas;
        dAppOp.control = userOp.control;

        uint256 estGasLim = estimateMetacallGasLimit(userOp, solverOps);

        (Result result, uint256 validCallsResult) = _errorCatcher(userOp, solverOps, dAppOp, estGasLim);
        success = uint8(result) > uint8(Result.UserOpSimFail);
        if (success) validCallsResult = uint256(ValidCallsResult.Valid);
        if (msg.value != 0) SafeTransferLib.safeTransferETH(msg.sender, msg.value);
        return (success, result, validCallsResult);
    }

    function simSolverCall(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        if (userOp.value > address(this).balance) revert SimulatorBalanceTooLow();

        SolverOperation[] memory solverOps = new SolverOperation[](1);
        solverOps[0] = solverOp;

        uint256 estGasLim = estimateMetacallGasLimit(userOp, solverOps);

        (Result result, uint256 solverOutcomeResult) = _errorCatcher(userOp, solverOps, dAppOp, estGasLim);
        success = result == Result.SimulationPassed;
        if (success) solverOutcomeResult = 0; // discard additional error uint if solver stage was successful
        if (msg.value != 0) SafeTransferLib.safeTransferETH(msg.sender, msg.value);
        return (success, result, solverOutcomeResult);
    }

    function simSolverCalls(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp
    )
        external
        payable
        returns (bool success, Result simResult, uint256)
    {
        if (userOp.value > address(this).balance) revert SimulatorBalanceTooLow();

        if (solverOps.length == 0) {
            // Returns number out of usual range of SolverOutcome enum to indicate no solverOps
            return (false, Result.Unknown, uint256(type(SolverOutcome).max) + 1);
        }

        uint256 estGasLim = estimateMetacallGasLimit(userOp, solverOps);

        (Result result, uint256 solverOutcomeResult) = _errorCatcher(userOp, solverOps, dAppOp, estGasLim);
        success = result == Result.SimulationPassed;
        if (success) solverOutcomeResult = 0; // discard additional error uint if solver stage was successful
        if (msg.value != 0) SafeTransferLib.safeTransferETH(msg.sender, msg.value);
        return (success, result, solverOutcomeResult);
    }

    function _errorCatcher(
        UserOperation memory userOp,
        SolverOperation[] memory solverOps,
        DAppOperation memory dAppOp,
        uint256 estGasLimit
    )
        internal
        returns (Result result, uint256 additionalErrorCode)
    {
        if (gasleft() < estGasLimit + _SIM_GAS_BEFORE_METACALL) {
            revert InsufficientGasForMetacallSimulation(estGasLimit, estGasLimit + _SIM_GAS_SUGGESTED_BUFFER);
        }

        try this.metacallSimulation{ value: userOp.value }(userOp, solverOps, dAppOp, estGasLimit) {
            revert Unreachable();
        } catch (bytes memory revertData) {
            bytes4 errorSwitch = bytes4(revertData);
            if (errorSwitch == VerificationSimFail.selector) {
                // revertData in form [bytes4, uint256] but reverts on abi.decode
                // This decodes the uint256 error code portion of the revertData
                uint256 validCallsResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    validCallsResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                result = Result.VerificationSimFail;
                additionalErrorCode = validCallsResult;
            } else if (errorSwitch == PreOpsSimFail.selector) {
                result = Result.PreOpsSimFail;
            } else if (errorSwitch == UserOpSimFail.selector) {
                result = Result.UserOpSimFail;
            } else if (errorSwitch == SolverSimFail.selector) {
                // Expects revertData in form [bytes4, uint256]
                uint256 solverOutcomeResult;
                assembly {
                    let dataLocation := add(revertData, 0x20)
                    solverOutcomeResult := mload(add(dataLocation, sub(mload(revertData), 32)))
                }
                result = Result.SolverSimFail;
                additionalErrorCode = solverOutcomeResult;
            } else if (errorSwitch == AllocateValueSimFail.selector) {
                result = Result.AllocateValueSimFail;
            } else if (errorSwitch == SimulationPassed.selector) {
                result = Result.SimulationPassed;
            } else {
                result = Result.Unknown;
            }

            return (result, additionalErrorCode);
        }
    }

    function metacallSimulation(
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps,
        DAppOperation calldata dAppOp,
        uint256 estGasLimit
    )
        external
        payable
    {
        if (msg.sender != address(this)) revert InvalidEntryFunction();
        bool auctionWon =
            IAtlas(atlas).metacall{ value: msg.value, gas: estGasLimit }(userOp, solverOps, dAppOp, address(0));

        // If multipleSuccessfulSolvers = true, metacall always returns auctionWon = false, even if there were some
        // successful solvers. So we always revert with SimulationPassed here if multipleSuccessfulSolvers = true.
        if (!auctionWon && !userOp.callConfig.multipleSuccessfulSolvers()) {
            revert NoAuctionWinner(); // should be unreachable
        }
        revert SimulationPassed();
    }

    // ---------------------------------------------------- //
    //                   Deployer Functions                 //
    // ---------------------------------------------------- //

    function setAtlas(address _atlas) external {
        if (msg.sender != deployer) revert Unauthorized();
        atlas = _atlas;
    }

    function withdrawETH(address to) external {
        if (msg.sender != deployer) revert Unauthorized();
        uint256 _balance = address(this).balance;
        SafeTransferLib.safeTransferETH(to, _balance);
        emit DeployerWithdrawal(to, _balance);
    }

    receive() external payable { }
    fallback() external payable { }
}
