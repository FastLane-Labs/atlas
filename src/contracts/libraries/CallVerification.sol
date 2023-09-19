//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import "../types/CallTypes.sol";

library CallVerification {
    function getUserOperationHash(UserCall calldata uCall) internal pure returns (bytes32 userOpHash) {
        userOpHash = keccak256(abi.encode(uCall));
    }

    function getBidsHash(BidData[] memory bidData) internal pure returns (bytes32 bidsHash) {
        return keccak256(abi.encode(bidData));
    }

    function getCallChainHash(
        DAppConfig calldata dConfig,
        UserCall calldata uCall,
        SolverOperation[] calldata solverOps
    ) internal pure returns (bytes32 callSequenceHash) {
        
        uint256 i;
        if (dConfig.callConfig & 1 << uint16(CallConfigIndex.RequirePreOps) != 0) {
            // Start with preOps call if preOps is needed
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // initial hash = null
                    dConfig.to,
                    abi.encodeWithSelector(
                        IDAppControl.preOpsCall.selector,
                        uCall
                    ),
                    i++
                )
            );
        }

        // then user call
        callSequenceHash = keccak256(
            abi.encodePacked(
                callSequenceHash, // always reference previous hash
                abi.encode(uCall),
                i++
            )
        );

        // then solver calls
        uint256 count = solverOps.length;
        uint256 n;
        for (; n<count;) {
            callSequenceHash = keccak256(
                abi.encodePacked(
                    callSequenceHash, // reference previous hash
                    abi.encode(solverOps[n].call), // solver call
                    i++
                )
            );
            unchecked {++n;}
        }
    }
}
