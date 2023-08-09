//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

import {CallBits} from "../libraries/CallBits.sol";

import "../types/CallTypes.sol";
import "../types/GovernanceTypes.sol";

import {UserCall, UserMetaTx} from "../types/CallTypes.sol";

// This contract exists so that protocol frontends can sign and confirm the
// calldata for users.  Users already trust the frontends to build and verify
// their calldata.  This allows users to know that any CallData sourced via
// an external relay (such as FastLane) has been verified by the already-trusted
// frontend
contract UserVerifier is EIP712 {
    using ECDSA for bytes32;
    using CallBits for uint16;

    bytes32 public constant USER_TYPE_HASH = keccak256(
        "UserMetaTx(address from,address to,uint256 deadline,uint256 gas,uint256 nonce,uint256 maxFeePerGas,uint256 value,bytes32 data)"
    );

    mapping(address => uint256) public userNonces;

    constructor() EIP712("UserVerifier", "0.0.1") {}

    // Verify the user's meta transaction
    function _verifyUser(ProtocolCall calldata protocolCall, UserCall calldata userCall)
        internal
        returns (bool)
    {
        // Verify the signature before storing any data to avoid
        // spoof transactions clogging up protocol userNonces
        require(_verifySignature(userCall), "ERR-UV01 InvalidSignature");

        if (userCall.metaTx.to != protocolCall.to) {
            return (false);
        }

        uint256 userNonce = userNonces[userCall.metaTx.from];

        // If the protocol indicated that they only accept sequenced userNonces
        // (IE for FCFS execution), check and make sure the order is correct
        // NOTE: allowing only sequenced userNonces could create a scenario in
        // which builders or validators may be able to profit via censorship.
        // Protocols are encouraged to rely on the deadline parameter
        // to prevent replay attacks.
        if (protocolCall.callConfig.needsSequencedNonces()) {
            if (userCall.metaTx.nonce != userNonce + 1) {
                return (false);
            }
            unchecked {
                ++userNonces[userCall.metaTx.from];
            }

            // If not sequenced, check to see if this nonce is highest and store
            // it if so.  This ensures nonce + 1 will always be available.
        } else {
            if (userCall.metaTx.nonce > userNonce + 1) {
                unchecked {
                    userNonces[userCall.metaTx.from] = userCall.metaTx.nonce + 1;
                }
            } else if (userCall.metaTx.nonce == userNonce + 1) {
                unchecked {
                    ++userNonces[userCall.metaTx.from];
                }
            } else {
                return false;
            }
        }

        return (true);
    }

    function _getProofHash(UserMetaTx memory metaTx) internal pure returns (bytes32 proofHash) {
        proofHash = keccak256(
            abi.encode(
                USER_TYPE_HASH,
                metaTx.from,
                metaTx.to,
                metaTx.deadline,
                metaTx.gas,
                metaTx.nonce,
                metaTx.maxFeePerGas,
                metaTx.value,
                keccak256(metaTx.data)
            )
        );
    }

    function _verifySignature(UserCall calldata userCall) internal view returns (bool) {
        address signer = _hashTypedDataV4(_getProofHash(userCall.metaTx)).recover(userCall.signature);

        return signer == userCall.metaTx.from;
    }

    function getUserCallPayload(UserCall memory userCall) public view returns (bytes32 payload) {
        payload = _hashTypedDataV4(_getProofHash(userCall.metaTx));
    }

    function nextUserNonce(address user) external view returns (uint256 nextNonce) {
        nextNonce = userNonces[user] + 1;
    }
}
