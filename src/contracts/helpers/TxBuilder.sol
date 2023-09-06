// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";
import {IProtocolIntegration} from "../interfaces/IProtocolIntegration.sol";
import {IEscrow} from "../interfaces/IEscrow.sol";
import {IAtlas} from "../interfaces/IAtlas.sol";

import "../types/CallTypes.sol";
import "../types/VerificationTypes.sol";

import {CallVerification} from "../libraries/CallVerification.sol";

import "forge-std/Test.sol";

contract TxBuilder {
    using CallVerification for UserMetaTx;
    using CallVerification for BidData[];

    address public immutable control;
    address public immutable escrow;
    address public immutable atlas;

    uint256 public immutable deadline;
    uint256 public immutable gas;

    constructor(address protocolControl, address escrowAddress, address atlasAddress) {
        control = protocolControl;
        escrow = escrowAddress;
        atlas = atlasAddress;
        deadline = block.number + 2;
        gas = 1_000_000;
    }

    function getPayeeData(bytes memory data) public returns (PayeeData[] memory) {
        return IProtocolControl(control).getPayeeData(data);
    }

    function getProtocolCall() public view returns (ProtocolCall memory) {
        return IProtocolControl(control).getProtocolCall();
    }

    function getBidData(UserMetaTx calldata userMetaTx, uint256 amount) public view returns (BidData[] memory bids) {
        bids = IProtocolControl(control).getBidFormat(userMetaTx);
        bids[0].bidAmount = amount;
    }

    function searcherNextNonce(address searcherMetaTxSigner) public view returns (uint256) {
        return IEscrow(escrow).nextSearcherNonce(searcherMetaTxSigner);
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        return IProtocolIntegration(atlas).nextGovernanceNonce(signatory);
    }

    function userNextNonce(address user) public view returns (uint256) {
        return IAtlas(atlas).nextUserNonce(user);
    }

    function buildUserCall(
        address from,
        address to,
        uint256 maxFeePerGas,
        uint256 value, // TODO check this is actually intended to be the value param. Was unnamed before.
        bytes memory data
    ) public view returns (UserCall memory userCall) {
        userCall.to = atlas;
        userCall.metaTx = UserMetaTx({
            from: from,
            to: to,
            deadline: deadline,
            gas: gas,
            nonce: userNextNonce(from),
            maxFeePerGas: maxFeePerGas,
            value: value,
            control: control,
            data: data
        });
    }

    function buildSearcherCall(
        UserCall calldata userCall,
        ProtocolCall calldata protocolCall,
        bytes calldata searcherCallData,
        address searcherEOA,
        address searcherContract,
        uint256 bidAmount
    ) public view returns (SearcherCall memory searcherCall) {
        searcherCall.to = atlas;
        searcherCall.bids = getBidData(userCall.metaTx, bidAmount);
        searcherCall.metaTx = SearcherMetaTx({
            from: searcherEOA,
            to: searcherContract,
            gas: gas,
            value: 0,
            nonce: searcherNextNonce(searcherEOA),
            maxFeePerGas: userCall.metaTx.maxFeePerGas,
            userCallHash: userCall.metaTx.getUserCallHash(),
            controlCodeHash: protocolCall.to.codehash,
            bidsHash: searcherCall.bids.getBidsHash(),
            data: searcherCallData
        });
    }

    function buildVerification(
        address governanceEOA,
        ProtocolCall calldata protocolCall,
        UserCall calldata userCall,
        SearcherCall[] calldata searcherCalls
    ) public view returns (Verification memory verification) {
        verification.to = atlas;
        bytes32 userCallHash = userCall.metaTx.getUserCallHash();
        bytes32 callChainHash = CallVerification.getCallChainHash(protocolCall, userCall.metaTx, searcherCalls);

        verification.proof = ProtocolProof({
            from: governanceEOA,
            to: control,
            nonce: governanceNextNonce(governanceEOA),
            deadline: deadline,
            userCallHash: userCallHash,
            callChainHash: callChainHash,
            controlCodeHash: protocolCall.to.codehash
        });
    }
}
