// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { UserOperation } from "../../../src/contracts/types/UserCallTypes.sol";

import { IAtlasVerification } from "../../../src/contracts/interfaces/IAtlasVerification.sol";

import "./BaseOperationBuilder.sol";

contract UserOperationBuilder is BaseOperationBuilder, Test {
    function user_validAndUnsigned(
        address from,
        address to,
        address control,
        uint256 value,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 deadline,
        bytes memory data
    )
        public
        returns (UserOperation memory userOp)
    {
        userOp = UserOperation({
            from: from,
            to: _atlas(),
            value: value,
            gas: gasLimit,
            maxFeePerGas: maxFeePerGas,
            nonce: IAtlasVerification(_atlasVerification()).getNextNonce(from),
            deadline: deadline,
            dapp: to,
            control: control,
            sessionKey: address(0),
            data: data,
            signature: new bytes(0)
        });
    }

    function user_validAndSigned(
        address from,
        address to,
        address control,
        uint256 value,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 deadline,
        bytes memory data,
        uint256 privateKey
    )
        public
        returns (UserOperation memory userOp)
    {
        userOp = user_validAndSigned(from, to, control, value, gasLimit, maxFeePerGas, deadline, data, privateKey);
        (v, r, s) = vm.sign(privateKey, IAtlasVerification(_atlasVerification()).getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(r, s, v);
    }
}
