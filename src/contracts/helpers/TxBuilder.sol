// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IDAppControl} from "../interfaces/IDAppControl.sol";
import {IDAppIntegration} from "../interfaces/IDAppIntegration.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {IAtlas} from "../interfaces/IAtlas.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";
import {CallBits} from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

contract TxBuilder {
    using CallVerification for UserCall;
    using CallVerification for BidData[];

    address public immutable control;
    address public immutable escrow;
    address public immutable atlas;

    uint256 public immutable gas;

    constructor(address controller, address escrowAddress, address atlasAddress) {
        control = controller;
        escrow = escrowAddress;
        atlas = atlasAddress;
        gas = 1_000_000;
    }

    function getDAppConfig() public view returns (DAppConfig memory) {
        return IDAppControl(control).getDAppConfig();
    }

    function getBidData(UserCall calldata uCall, uint256 amount) public view returns (BidData[] memory bids) {
        bids = IDAppControl(control).getBidFormat(uCall);
        bids[0].bidAmount = amount;
    }

    function solverNextNonce(address solverSigner) public view returns (uint256) {
        return IEscrow(escrow).nextSolverNonce(solverSigner);
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        return IDAppIntegration(atlas).nextGovernanceNonce(signatory);
    }

    function userNextNonce(address user) public view returns (uint256) {
        return IAtlas(atlas).nextUserNonce(user);
    }

    function buildUserOperation(
        address from,
        address to,
        uint256 maxFeePerGas,
        uint256 value, // TODO check this is actually intended to be the value param. Was unnamed before.
        uint256 deadline,
        bytes memory data
    ) public view returns (UserOperation memory userOp) {
        userOp.to = atlas;
        userOp.call = UserCall({
            from: from,
            to: to,
            value: value,
            gas: gas,
            maxFeePerGas: maxFeePerGas,
            nonce: userNextNonce(from),
            deadline: block.number + 2,
            control: control,
            data: data
        });
    }

    function buildSolverOperation(
        UserOperation calldata userOp,
        DAppConfig memory dConfig,
        bytes calldata solverOpData,
        address solverEOA,
        address solverContract,
        uint256 bidAmount
    ) public view returns (SolverOperation memory solverOp) {
        if (dConfig.callConfig == 0) {
            dConfig = DAppConfig({
                to: userOp.call.control,
                callConfig: CallBits.buildCallConfig(userOp.call.control)
            });
        }

        solverOp.to = atlas;
        solverOp.bids = getBidData(userOp.call, bidAmount);
        solverOp.call = SolverCall({
            from: solverEOA,
            to: solverContract,
            value: 0,
            gas: gas,
            maxFeePerGas: userOp.call.maxFeePerGas,
            nonce: solverNextNonce(solverEOA),
            deadline: userOp.call.deadline,
            controlCodeHash: dConfig.to.codehash,
            userOpHash: userOp.call.getUserOperationHash(),
            bidsHash: solverOp.bids.getBidsHash(),
            data: solverOpData
        });
    }

    function buildDAppOperation(
        address governanceEOA,
        DAppConfig memory dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps
    ) public view returns (DAppOperation memory dAppOp) {
        dAppOp.to = atlas;
        if (dConfig.callConfig == 0) {
            dConfig = DAppConfig({
                to: userOp.call.control,
                callConfig: CallBits.buildCallConfig(userOp.call.control)
            });
        }
        bytes32 userOpHash = userOp.call.getUserOperationHash();
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, userOp.call, solverOps);

        dAppOp.approval = DAppApproval({
            from: governanceEOA,
            to: control,
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.call.maxFeePerGas,
            nonce: governanceNextNonce(governanceEOA),
            deadline: userOp.call.deadline,
            controlCodeHash: dConfig.to.codehash,
            userOpHash: userOpHash,
            callChainHash: callChainHash
        });
    }
}
