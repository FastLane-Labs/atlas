//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

interface IEscrow {

    function deposit(address searcherMetaTxSigner) external payable returns (uint256 newBalance);

    function getNextNonce(address searcherMetaTxSigner) external view returns (uint256 nextNonce);

    function executeStagingCall(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall
    ) external returns (bytes memory stagingReturnData);

    function executeUserCall(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData,
        UserCall calldata userCall
    ) external returns (bytes memory userReturnData);

    function executeSearcherCall(
        CallChainProof calldata proof,
        bool auctionAlreadyComplete,
        SearcherCall calldata searcherCall
    ) external payable returns (bool);

    function executePayments(
        ProtocolCall calldata protocolCall,
        BidData[] calldata winningBids,
        PayeeData[] calldata payeeData
    ) external;

    function executeVerificationCall(
        CallChainProof calldata proof,
        ProtocolCall calldata protocolCall,
        bytes memory stagingReturnData, 
        bytes memory userReturnData
    ) external;

    function executeUserRefund(
        address userCallFrom
    ) external;
}
