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
    using CallVerification for UserOperation;
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

    function solverNextNonce(address solverSigner) public view returns (uint256) {
        return IEscrow(escrow).nextSolverNonce(solverSigner);
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        return IAtlas(atlas).getNextNonce(signatory);
    }

    function userNextNonce(address user) public view returns (uint256) {
        return IAtlas(atlas).getNextNonce(user);
    }

    function getControlCodeHash(address dAppControl) external view returns (bytes32) {
        return dAppControl.codehash;
    }

    function getBlockchainID() external view returns (uint256 chainId) {
        chainId = block.chainid;
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
        userOp = UserOperation({
            from: from,
            to: atlas,
            value: value,
            gas: gas,
            maxFeePerGas: maxFeePerGas,
            nonce: userNextNonce(from),
            deadline: deadline,
            dapp: to,
            control: control,
            data: data
        });
    }

    function buildSolverOperation(
        UserOperation memory userOp,
        DAppConfig memory,
        bytes memory solverOpData,
        address solverEOA,
        address solverContract,
        uint256 bidAmount
    ) public view returns (SolverOperation memory solverOp) {
        
        solverOp = SolverOperation({
            from: solverEOA,
            to: atlas,
            value: 0,
            gas: gas,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: solverNextNonce(solverEOA),
            deadline: userOp.deadline,
            solver: solverContract,
            control: userOp.control,
            userOpHash: userOp.getUserOperationHash(),
            bidToken: IDAppControl(control).getBidFormat(userOp),
            bidAmount: bidAmount,
            data: solverOpData,
            signature: new bytes(0)
        });
    }

    function buildDAppOperation(
        address governanceEOA,
        DAppConfig memory dConfig,
        UserOperation memory userOp,
        SolverOperation[] memory solverOps
    ) public view returns (DAppOperation memory dAppOp) {
        dAppOp.to = atlas;
        if (dConfig.callConfig == 0) {
            dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        }
        bytes32 userOpHash = userOp.getUserOperationHash();
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, userOp, solverOps);

        dAppOp = DAppOperation({
            from: governanceEOA,
            to: atlas,
            value: 0,
            gas: 2_000_000,
            maxFeePerGas: userOp.maxFeePerGas,
            nonce: governanceNextNonce(governanceEOA),
            deadline: userOp.deadline,
            control: dConfig.to,
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });
    }
}
