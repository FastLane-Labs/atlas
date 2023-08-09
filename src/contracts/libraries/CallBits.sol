//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IProtocolControl} from "../interfaces/IProtocolControl.sol";

import "../types/CallTypes.sol";

library CallBits {
    uint16 internal constant _ONE = uint16(1);

    function buildCallConfig(address protocolControl) internal view returns (uint16 callConfig) {
        (
            bool sequenced,
            bool requireStaging,
            bool localUser,
            bool delegateUser,
            bool searcherStaging,
            bool searcherFulfillment,
            bool requireVerification,
            bool zeroSearchers,
            bool reuseUserOp,
            bool userBundler,
            bool protocolBundler,
            bool unknownBundler
        ) = IProtocolControl(protocolControl).getCallConfig();

        // WTB tuple unpacking :*(
        callConfig = encodeCallConfig(
             sequenced,
             requireStaging,
             localUser,
             delegateUser,
             searcherStaging,
             searcherFulfillment,
             requireVerification,
             zeroSearchers,
             reuseUserOp,
             userBundler,
             protocolBundler,
             unknownBundler
        );
    }

    function encodeCallConfig(
        bool sequenced,
        bool requireStaging,
        bool localUser,
        bool delegateUser,
        bool searcherStaging,
        bool searcherFulfillment,
        bool requireVerification,
        bool zeroSearchers,
        bool reuseUserOp,
        bool userBundler,
        bool protocolBundler,
        bool unknownBundler
    ) internal pure returns (uint16 callConfig) {
        if (sequenced) {
            callConfig ^= _ONE << uint16(CallConfig.Sequenced);
        }
        if (requireStaging) {
            callConfig ^= _ONE << uint16(CallConfig.CallStaging);
        }
        if (localUser) {
            callConfig ^= _ONE << uint16(CallConfig.LocalUser);
        }
        if (delegateUser) {
            callConfig ^= _ONE << uint16(CallConfig.DelegateUser);
        }
        if (searcherStaging) {
            callConfig ^= _ONE << uint16(CallConfig.SearcherStaging);
        }
        if (searcherFulfillment) {
            callConfig ^= _ONE << uint16(CallConfig.SearcherFulfillment);
        }
        if (requireVerification) {
            callConfig ^= _ONE << uint16(CallConfig.CallVerification);
        }
        if (zeroSearchers) {
            callConfig ^= _ONE << uint16(CallConfig.ZeroSearchers);
        }
        if (reuseUserOp) {
            callConfig ^= _ONE << uint16(CallConfig.ReuseUserOp);
        }
        if (userBundler) {
            callConfig ^= _ONE << uint16(CallConfig.UserBundler);
        }
        if (protocolBundler) {
            callConfig ^= _ONE << uint16(CallConfig.ProtocolBundler);
        }
        if (unknownBundler) {
            callConfig ^= _ONE << uint16(CallConfig.UnknownBundler);
        }
    }

    function needsSequencedNonces(uint16 callConfig) internal pure returns (bool sequenced) {
        sequenced = (callConfig & 1 << uint16(CallConfig.Sequenced) != 0);
    }

    function needsStagingCall(uint16 callConfig) internal pure returns (bool needsStaging) {
        needsStaging = (callConfig & 1 << uint16(CallConfig.CallStaging) != 0);
    }

    function needsLocalUser(uint16 callConfig) internal pure returns (bool localUser) {
        localUser = (callConfig & 1 << uint16(CallConfig.LocalUser) != 0);
    }

    function needsDelegateUser(uint16 callConfig) internal pure returns (bool delegateUser) {
        delegateUser = (callConfig & 1 << uint16(CallConfig.DelegateUser) != 0);
    }

    function needsSearcherStaging(uint16 callConfig) internal pure returns (bool searcherStaging) {
        searcherStaging = (callConfig & 1 << uint16(CallConfig.SearcherStaging) != 0);
    }

    function needsSearcherFullfillment(uint16 callConfig) internal pure returns (bool searcherFulfillment) {
        searcherFulfillment = (callConfig & 1 << uint16(CallConfig.SearcherFulfillment) != 0);
    }

    function needsVerificationCall(uint16 callConfig) internal pure returns (bool needsVerification) {
        needsVerification = (callConfig & 1 << uint16(CallConfig.CallVerification) != 0);
    }

    function allowsZeroSearchers(uint16 callConfig) internal pure returns (bool zeroSearchers) {
        zeroSearchers = (callConfig & 1 << uint16(CallConfig.ZeroSearchers) != 0);
    }

    function allowsReuseUserOps(uint16 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = (callConfig & 1 << uint16(CallConfig.ReuseUserOp) != 0);
    }

    function allowsUserBundler(uint16 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint16(CallConfig.UserBundler) != 0);
    }

    function allowsProtocolBundler(uint16 callConfig) internal pure returns (bool protocolBundler) {
        protocolBundler = (callConfig & 1 << uint16(CallConfig.ProtocolBundler) != 0);
    }

    function allowsUnknownBundler(uint16 callConfig) internal pure returns (bool unknownBundler) {
        unknownBundler = (callConfig & 1 << uint16(CallConfig.UnknownBundler) != 0);
    }
}
