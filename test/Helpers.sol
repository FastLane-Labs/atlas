// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IProtocolControl} from "../src/contracts/interfaces/IProtocolControl.sol";
import {IProtocolIntegration} from "../src/contracts/interfaces/IProtocolIntegration.sol";
import {IEscrow} from "../src/contracts/interfaces/IEscrow.sol";

import "../src/contracts/types/CallTypes.sol";
import "../src/contracts/types/EscrowTypes.sol";
import "../src/contracts/types/LockTypes.sol";
import "../src/contracts/types/VerificationTypes.sol";

contract Helper {

    address immutable public control;
    address immutable public escrow;
    address immutable public atlas;

    constructor(address protocolControl, address escrowAddress, address atlasAddress) {
        control = protocolControl;
        escrow = escrowAddress;
        atlas = atlasAddress;
    }

    function getPayeeData() public returns (PayeeData[] memory) {
        bytes memory nullData;
        return IProtocolControl(control).getPayeeData(nullData);
    }

    function getProtocolCall() public view returns (ProtocolCall memory) {
        return IProtocolControl(control).getProtocolCall();
    }

    function getBidData(uint256 amount) 
        public returns (BidData[] memory bids) 
    {
        bytes memory nullData;
        bids = IProtocolControl(control).getBidFormat(nullData);
        bids[0].bidAmount = amount;
    }

    function searcherNextNonce(address searcherMetaTxSigner) public view returns (uint256) {
        return IEscrow(escrow).getNextNonce(searcherMetaTxSigner);
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        return IProtocolIntegration(atlas).getNextNonce(signatory);
    }
}