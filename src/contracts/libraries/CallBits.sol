//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";

library CallBits {
    uint16 internal constant _ONE = uint16(1);

    function buildCallConfig(address protocolControl) internal view returns (uint16 callConfig) {
        CallConfig memory callconfig = IProtocolControl(protocolControl).getCallConfig();
        callConfig = encodeCallConfig(callconfig);
    }

    function encodeCallConfig(CallConfig memory callconfig) internal pure returns (uint16 callConfig) {
        if (callconfig.sequenced) {
            callConfig ^= _ONE << uint16(CallConfigIndex.Sequenced);
        }
        if (callconfig.requireStaging) {
            callConfig ^= _ONE << uint16(CallConfigIndex.RequireStaging);
        }
        if (callconfig.trackStagingReturnData) {
            callConfig ^= _ONE << uint16(CallConfigIndex.TrackStagingReturnData);
        }
        if (callconfig.trackUserReturnData) {
            callConfig ^= _ONE << uint16(CallConfigIndex.TrackUserReturnData);
        }
        if (callconfig.delegateUser) {
            callConfig ^= _ONE << uint16(CallConfigIndex.DelegateUser);
        }
        if (callconfig.localUser) {
            callConfig ^= _ONE << uint16(CallConfigIndex.LocalUser);
        }
        if (callconfig.searcherStaging) {
            callConfig ^= _ONE << uint16(CallConfigIndex.SearcherStaging);
        }
        if (callconfig.searcherFulfillment) {
            callConfig ^= _ONE << uint16(CallConfigIndex.SearcherFulfillment);
        }
        if (callconfig.requireVerification) {
            callConfig ^= _ONE << uint16(CallConfigIndex.RequireVerification);
        }
        if (callconfig.zeroSearchers) {
            callConfig ^= _ONE << uint16(CallConfigIndex.ZeroSearchers);
        }
        if (callconfig.reuseUserOp) {
            callConfig ^= _ONE << uint16(CallConfigIndex.ReuseUserOp);
        }
        if (callconfig.userBundler) {
            callConfig ^= _ONE << uint16(CallConfigIndex.UserBundler);
        }
        if (callconfig.protocolBundler) {
            callConfig ^= _ONE << uint16(CallConfigIndex.ProtocolBundler);
        }
        if (callconfig.unknownBundler) {
            callConfig ^= _ONE << uint16(CallConfigIndex.UnknownBundler);
        }
    }

    function needsSequencedNonces(uint16 callConfig) internal pure returns (bool sequenced) {
        sequenced = (callConfig & 1 << uint16(CallConfigIndex.Sequenced) != 0);
    }

    function needsStagingCall(uint16 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint16(CallConfigIndex.RequireStaging) != 0);
    }

    function needsStagingReturnData(uint16 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint16(CallConfigIndex.TrackStagingReturnData) != 0);
    }

    function needsUserReturnData(uint16 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint16(CallConfigIndex.TrackUserReturnData) != 0);
    }

    function needsDelegateUser(uint16 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint16(CallConfigIndex.DelegateUser) != 0);
    }

    function needsLocalUser(uint16 callConfig) internal pure returns (bool localUser) {
        localUser = (callConfig & 1 << uint16(CallConfigIndex.LocalUser) != 0);
    }

    function needsSearcherStaging(uint16 callConfig) internal pure returns (bool searcherStaging) {
        searcherStaging = (callConfig & 1 << uint16(CallConfigIndex.SearcherStaging) != 0);
    }

    function needsSearcherPostCall(uint16 callConfig) internal pure returns (bool searcherFulfillment) {
        searcherFulfillment = (callConfig & 1 << uint16(CallConfigIndex.SearcherFulfillment) != 0);
    }

    function needsVerificationCall(uint16 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint16(CallConfigIndex.RequireVerification) != 0);
    }

    function allowsZeroSearchers(uint16 callConfig) internal pure returns (bool zeroSearchers) {
        zeroSearchers = (callConfig & 1 << uint16(CallConfigIndex.ZeroSearchers) != 0);
    }

    function allowsReuseUserOps(uint16 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = (callConfig & 1 << uint16(CallConfigIndex.ReuseUserOp) != 0);
    }

    function allowsUserBundler(uint16 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint16(CallConfigIndex.UserBundler) != 0);
    }

    function allowsProtocolBundler(uint16 callConfig) internal pure returns (bool protocolBundler) {
        protocolBundler = (callConfig & 1 << uint16(CallConfigIndex.ProtocolBundler) != 0);
    }

    function allowsUnknownBundler(uint16 callConfig) internal pure returns (bool unknownBundler) {
        unknownBundler = (callConfig & 1 << uint16(CallConfigIndex.UnknownBundler) != 0);
    }
}
