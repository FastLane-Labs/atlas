//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

library CallVerification {
    function getUserCallHash(UserMetaTx calldata userMetaTx) internal pure returns (bytes32 userCallHash) {
        userCallHash = keccak256(abi.encode(userMetaTx));
    }

    function getBidsHash(BidData[] memory bidData) internal pure returns (bytes32 bidsHash) {
        return keccak256(abi.encode(bidData));
    }

    function getCallChainHash(
        ProtocolCall calldata protocolCall,
        UserMetaTx calldata userMetaTx,
        SearcherCall[] calldata searcherCalls
    ) internal pure returns (bytes32 callSequenceHash) {
        
        uint256 i;
        if (protocolCall.callConfig & 1 << uint16(CallConfig.CallStaging) != 0) {
            // Start with staging call if staging is needed
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // initial hash = null
                    protocolCall.to,
                    abi.encodeWithSelector(
                        IProtocolControl.stagingCall.selector,
                        userMetaTx
                    ),
                    i++
                )
            );
        }

        // then user call
        callSequenceHash = keccak256(
            abi.encodePacked(
                callSequenceHash, // always reference previous hash
                abi.encode(userMetaTx),
                i++
            )
        );

        // then searcher calls
        uint256 count = searcherCalls.length;
        uint256 n;
        for (; n<count;) {
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // reference previous hash
                    abi.encode(searcherCalls[n].metaTx), // searcher call
                    i++
                )
            );
            unchecked {++n;}
        }
    }
}
