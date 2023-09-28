// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IDAppControl} from "../interfaces/IDAppControl.sol";
import {IDAppIntegration} from "../interfaces/IDAppIntegration.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {IAtlas} from "../interfaces/IAtlas.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract TxBuilder {
    using CallVerification for UserCall;
    using CallVerification for BidData[];

    address public immutable control;
    address public immutable escrow;
    address public immutable atlas;

    uint256 public immutable deadline;
    uint256 public immutable gas;

    constructor(address controller, address escrowAddress, address atlasAddress) {
        control = controller;
        escrow = escrowAddress;
        atlas = atlasAddress;
        deadline = block.number + 2;
        gas = 1_000_000;
    }

    function getPayeeData(bytes memory data) public returns (PayeeData[] memory) {
        return IDAppControl(control).getPayeeData(data);
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
        bytes memory data
    ) public view returns (UserOperation memory userOp) {
        userOp.to = atlas;
        userOp.call = UserCall({
            from: from,
            to: to,
            deadline: block.number + 2,
            gas: gas,
            nonce: userNextNonce(from),
            maxFeePerGas: maxFeePerGas,
            value: value,
            control: control,
            data: data
        });
    }

    function buildSolverOperation(
        UserOperation calldata userOp,
        DAppConfig calldata dConfig,
        bytes calldata solverOpData,
        address solverEOA,
        address solverContract,
        uint256 bidAmount
    ) public view returns (SolverOperation memory solverOp) {
        solverOp.to = atlas;
        solverOp.bids = getBidData(userOp.call, bidAmount);
        solverOp.call = SolverCall({
            from: solverEOA,
            to: solverContract,
            gas: gas,
            value: 0,
            nonce: solverNextNonce(solverEOA),
            maxFeePerGas: userOp.call.maxFeePerGas,
            userOpHash: userOp.call.getUserOperationHash(),
            controlCodeHash: dConfig.to.codehash,
            bidsHash: solverOp.bids.getBidsHash(),
            data: solverOpData
        });
    }

    function buildVerification(
        address governanceEOA,
        DAppConfig calldata dConfig,
        UserOperation calldata userOp,
        SolverOperation[] calldata solverOps
    ) public view returns (Verification memory verification) {
        verification.to = atlas;
        bytes32 userOpHash = userOp.call.getUserOperationHash();
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, userOp.call, solverOps);

        verification.proof = DAppProof({
            from: governanceEOA,
            to: control,
            nonce: governanceNextNonce(governanceEOA),
            deadline: block.number + 2,
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            controlCodeHash: dConfig.to.codehash
        });
    }
}
