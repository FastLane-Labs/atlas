// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IAtlas} from "../src/contracts/interfaces/IAtlas.sol";

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {DAppVerification} from "../src/contracts/atlas/DAppVerification.sol";

import "../src/contracts/types/VerificationTypes.sol";

import {TestConstants} from "./base/TestConstants.sol";

import {CallVerification} from "../src/contracts/libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract VerificationSigner is Test, TestConstants, DAppVerification {
    function signVerification(Verification memory verification, address atlas, uint256 privateKey)
        public
        view
        returns (Verification memory)
    {
        bytes32 payload = IAtlas(atlas).getVerificationPayload(verification);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, payload);

        verification.signature = abi.encodePacked(r, s, v);

        return verification;
    }
}
