//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";

library CallBits {
    uint32 internal constant _ONE = uint32(1);

    function buildCallConfig(address protocolControl) internal view returns (uint32 callConfig) {
        CallConfig memory callconfig = IProtocolControl(protocolControl).getCallConfig();
        callConfig = encodeCallConfig(callconfig);
    }

    function encodeCallConfig(CallConfig memory callConfig) internal pure returns (uint32 encodedCallConfig) {
        if (callConfig.sequenced) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.Sequenced);
        }
        if (callConfig.requireStaging) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequireStaging);
        }
        if (callConfig.trackStagingReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackStagingReturnData);
        }
        if (callConfig.trackUserReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackUserReturnData);
        }
        if (callConfig.delegateUser) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.DelegateUser);
        }
        if (callConfig.localUser) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.LocalUser);
        }
        if (callConfig.searcherStaging) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SearcherStaging);
        }
        if (callConfig.searcherFulfillment) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SearcherFulfillment);
        }
        if (callConfig.requireVerification) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequireVerification);
        }
        if (callConfig.zeroSearchers) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ZeroSearchers);
        }
        if (callConfig.reuseUserOp) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ReuseUserOp);
        }
        if (callConfig.userBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserBundler);
        }
        if (callConfig.protocolBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ProtocolBundler);
        }
        if (callConfig.unknownBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UnknownBundler);
        }
    }

    function decodeCallConfig(uint32 encodedCallConfig) internal pure returns (CallConfig memory callConfig) {
        callConfig = CallConfig({
            sequenced: needsSequencedNonces(encodedCallConfig),
            requireStaging: needsStagingCall(encodedCallConfig),
            trackStagingReturnData: needsStagingReturnData(encodedCallConfig),
            trackUserReturnData: needsUserReturnData(encodedCallConfig),
            delegateUser: needsDelegateUser(encodedCallConfig),
            localUser: needsLocalUser(encodedCallConfig),
            searcherStaging: needsSearcherStaging(encodedCallConfig),
            searcherFulfillment: needsSearcherPostCall(encodedCallConfig),
            requireVerification: needsVerificationCall(encodedCallConfig),
            zeroSearchers: allowsZeroSearchers(encodedCallConfig),
            reuseUserOp: allowsReuseUserOps(encodedCallConfig),
            userBundler: allowsUserBundler(encodedCallConfig),
            protocolBundler: allowsProtocolBundler(encodedCallConfig),
            unknownBundler: allowsUnknownBundler(encodedCallConfig)
        });
    }

    function needsSequencedNonces(uint32 callConfig) internal pure returns (bool sequenced) {
        sequenced = (callConfig & 1 << uint32(CallConfigIndex.Sequenced) != 0);
    }

    function needsStagingCall(uint32 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint32(CallConfigIndex.RequireStaging) != 0);
    }

    function needsStagingReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint32(CallConfigIndex.TrackStagingReturnData) != 0);
    }

    function needsUserReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint32(CallConfigIndex.TrackUserReturnData) != 0);
    }

    function needsDelegateUser(uint32 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint32(CallConfigIndex.DelegateUser) != 0);
    }

    function needsLocalUser(uint32 callConfig) internal pure returns (bool localUser) {
        localUser = (callConfig & 1 << uint32(CallConfigIndex.LocalUser) != 0);
    }

    function needsSearcherStaging(uint32 callConfig) internal pure returns (bool searcherStaging) {
        searcherStaging = (callConfig & 1 << uint32(CallConfigIndex.SearcherStaging) != 0);
    }

    function needsSearcherPostCall(uint32 callConfig) internal pure returns (bool searcherFulfillment) {
        searcherFulfillment = (callConfig & 1 << uint32(CallConfigIndex.SearcherFulfillment) != 0);
    }

    function needsVerificationCall(uint32 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint32(CallConfigIndex.RequireVerification) != 0);
    }

    function allowsZeroSearchers(uint32 callConfig) internal pure returns (bool zeroSearchers) {
        zeroSearchers = (callConfig & 1 << uint32(CallConfigIndex.ZeroSearchers) != 0);
    }

    function allowsReuseUserOps(uint32 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = (callConfig & 1 << uint32(CallConfigIndex.ReuseUserOp) != 0);
    }

    function allowsUserBundler(uint32 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint32(CallConfigIndex.UserBundler) != 0);
    }

    function allowsProtocolBundler(uint32 callConfig) internal pure returns (bool protocolBundler) {
        protocolBundler = (callConfig & 1 << uint32(CallConfigIndex.ProtocolBundler) != 0);
    }

    function allowsUnknownBundler(uint32 callConfig) internal pure returns (bool unknownBundler) {
        unknownBundler = (callConfig & 1 << uint32(CallConfigIndex.UnknownBundler) != 0);
    }
}
