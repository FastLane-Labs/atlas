//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import { IProtocolControl } from "../interfaces/IProtocolControl.sol";

import {
    CallConfig
} from "../libraries/DataTypes.sol";

library CallBits {

    uint16 constant internal _ONE = uint16(1);

    function buildCallConfig(address protocolControl) internal view returns (uint16 callConfig) {
        (
            bool requireStaging,
            bool delegateStaging,
            bool localUser,
            bool delegateUser,
            bool delegateAllocating,
            bool requireVerification,
            bool delegateVerification,
            bool recycledStorage
        ) = IProtocolControl(protocolControl).getCallConfig();

        if (requireStaging) {
            callConfig ^= _ONE << uint16(CallConfig.CallStaging);
            if (delegateStaging) {
                callConfig ^= _ONE << uint16(CallConfig.DelegateStaging);
            }
        }
        if (localUser) {
            callConfig ^= _ONE << uint16(CallConfig.LocalUser);
        }
        if (delegateUser) {
            callConfig ^= _ONE << uint16(CallConfig.DelegateUser);
        }
        if (delegateAllocating) {
            callConfig ^= _ONE << uint16(CallConfig.DelegateAllocating);
        }
        if (requireVerification) {
            callConfig ^= _ONE << uint16(CallConfig.CallVerification);
            if (delegateVerification) {
                callConfig ^= _ONE << uint16(CallConfig.DelegateVerification);
            }
        }
        if (recycledStorage) {
            callConfig ^= _ONE << uint16(CallConfig.RecycledStorage);
        }
    }

    function _needsStaging(uint16 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    function _delegateStaging(uint16 callConfig) internal pure returns (bool delegateStaging) {
        delegateStaging = (callConfig & 1 << uint16(CallConfig.DelegateStaging) != 0);
    }

    function _localUser(uint16 callConfig) internal pure returns (bool localUser) {
        localUser = (callConfig & 1 << uint16(CallConfig.LocalUser) != 0);
    }

    function _delegateUser(uint16 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint16(CallConfig.DelegateUser) != 0);
    }

    function _delegateAllocating(uint16 callConfig) internal pure returns (bool delegateAllocating) {
        delegateAllocating = (callConfig & 1 << uint16(CallConfig.DelegateAllocating) != 0);
    }

    function _delegateVerification(uint16 callConfig) internal pure returns (bool delegateVerification) {
        delegateVerification = (callConfig & 1 << uint16(CallConfig.DelegateVerification) != 0);
    }

    function _needsVerification(uint16 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint16(CallConfig.CallVerification) != 0);
    }

    function _recycledStorage(uint16 callConfig) internal pure returns (bool recycledStorage) {
        recycledStorage = (callConfig & 1 << uint16(CallConfig.RecycledStorage) != 0);
    }

}