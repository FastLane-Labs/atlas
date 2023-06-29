//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface IEscrow {

    function deposit(address searcherMetaTxSigner) external payable returns (uint256 newBalance);

    function getNextNonce(address searcherMetaTxSigner) external view returns (uint256 nextNonce);

    function executeStagingCall(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external returns (bytes memory stagingReturnData);

    function executeUserCall(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function executeSearcherCall(
        CallChainProof memory proof,
        uint256 gasWaterMark,
        bool auctionAlreadyComplete,
        SearcherCall calldata searcherCall
    ) external payable returns (bool);

    function executePayments(
        ProtocolCall calldata protocolCall,
        BidData[] calldata winningBids,
        PayeeData[] calldata payeeData
    ) external;

    function executeVerificationCall(
        CallChainProof memory proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) external;

    function executeUserRefund(
        UserCall calldata userCall,
        bool callSuccess
    ) external;
}
