// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IAtlas} from "../src/contracts/interfaces/IAtlas.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {DAppVerification} from "../src/contracts/atlas/DAppVerification.sol";

import "../src/contracts/types/DAppApprovalTypes.sol";

import {TestConstants} from "./base/TestConstants.sol";

import {CallVerification} from "../src/contracts/libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract DAppOperationSigner is Test, TestConstants, DAppVerification {
    function signDAppOperation(DAppOperation memory verification, address atlas, uint256 privateKey)
        public
        view
        returns (DAppOperation memory)
    {
        bytes32 payload = IAtlas(atlas).getDAppOperationPayload(verification);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, payload);

        verification.signature = abi.encodePacked(r, s, v);

        return verification;
    }
}
