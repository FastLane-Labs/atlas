//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IThogLock } from "../interfaces/IThogLock.sol";

interface IFactory is IThogLock {
    struct ProtocolData {
        address owner; // the protocol, not fastlane
        uint32 nonce; 
        uint16 callConfig; // bitwise
        uint16 split; // FL revenue share
    }

    enum CallConfig { // for readability, will get broken down into pure funcs later
        CallStaging,
        DelegateStaging,
        FwdValueStaging,
        CallVerification,
        DelegateVerification,
        FwdValueVerification
    }
    
    function initReleaseFactoryThogLock(
        uint256 keyCode
    ) external;
}