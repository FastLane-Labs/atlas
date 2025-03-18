//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

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

contract Simulator is AtlasErrors, AtlasConstants {
    using CallBits for uint32;
    using AccountingMath for uint256;

    uint256 internal constant _SIM_GAS_SUGGESTED_BUFFER = 30_000; // TODO calc properly
    uint256 internal constant _SIM_GAS_BEFORE_METACALL = 10_000; // TODO calc properly

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
        uint256 metacallCalldataLength = msg.data.length + DAPP_OP_LENGTH + 28;
        // Additional 28 length accounts for the missing address param

        uint256 metacallCalldataGas =
            GasAccLib.metacallCalldataGas(metacallCalldataLength, IAtlas(atlas).L2_GAS_CALCULATOR());

        uint256 metacallExecutionGas = _BASE_TX_GAS_USED + AccountingMath._FIXED_GAS_OFFSET + userOp.gas
            + dConfig.dappGasLimit + solverOps.length * dConfig.solverGasLimit;

        if (dConfig.callConfig.exPostBids()) {
            metacallExecutionGas += solverOps.length * (_BID_FIND_OVERHEAD + dConfig.solverGasLimit);
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
        uint256 bundlerSurchargeRate = IAtlas(atlas).bundlerSurchargeRate();
        uint256 atlasSurchargeRate = IAtlas(atlas).atlasSurchargeRate();

        // In exPostBid mode, solvers do not pay for calldata gas, and these calldata gas vars will be excluded.
        // In normal bid mode, solvers each pay for their own solverOp calldata gas, and the winning solver pays for the
        // other non-solver calldata gas as well. In this calculation, there's only 1 solverOp so no need to subtract
        // calldata of other solverOps as they aren't any.
        uint256 metacallCalldataLength = msg.data.length + DAPP_OP_LENGTH + 28;
        uint256 metacallCalldataGas =
            GasAccLib.metacallCalldataGas(metacallCalldataLength, IAtlas(atlas).L2_GAS_CALCULATOR());

        uint256 metacallExecutionGas =
            _BASE_TX_GAS_USED + AccountingMath._FIXED_GAS_OFFSET + userOp.gas + userOp.dappGasLimit + solverOp.gas;

        uint256 totalGas = metacallExecutionGas;

        // Only add calldata costs if NOT in exPostBids mode
        if (!dConfig.callConfig.exPostBids()) {
            totalGas += metacallCalldataGas;
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
        if (!IAtlas(atlas).metacall{ value: msg.value, gas: estGasLimit }(userOp, solverOps, dAppOp, address(0))) {
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
