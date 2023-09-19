//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import "../types/CallTypes.sol";

library CallBits {
    uint16 internal constant _ONE = uint16(1);

    function buildCallConfig(address controller) internal view returns (uint16 callConfig) {
        CallConfig memory callconfig = IDAppControl(controller).getCallConfig();
        callConfig = encodeCallConfig(callconfig);
    }

    function encodeCallConfig(CallConfig memory callConfig) internal pure returns (uint16 encodedCallConfig) {
        if (callConfig.sequenced) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.Sequenced);
        }
        if (callConfig.requirePreOps) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.RequirePreOps);
        }
        if (callConfig.trackPreOpsReturnData) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.TrackPreOpsReturnData);
        }
        if (callConfig.trackUserReturnData) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.TrackUserReturnData);
        }
        if (callConfig.delegateUser) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.DelegateUser);
        }
        if (callConfig.localUser) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.LocalUser);
        }
        if (callConfig.preSolver) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.PreSolver);
        }
        if (callConfig.postSolver) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.PostSolver);
        }
        if (callConfig.requirePostOps) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.RequirePostOpsCall);
        }
        if (callConfig.zeroSolvers) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.ZeroSolvers);
        }
        if (callConfig.reuseUserOp) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.ReuseUserOp);
        }
        if (callConfig.userBundler) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.UserBundler);
        }
        if (callConfig.dAppBundler) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.DAppBundler);
        }
        if (callConfig.unknownBundler) {
            encodedCallConfig ^= _ONE << uint16(CallConfigIndex.UnknownBundler);
        }
    }

    function decodeCallConfig(uint16 encodedCallConfig) internal pure returns (CallConfig memory callConfig) {
        callConfig = CallConfig({
            sequenced: needsSequencedNonces(encodedCallConfig),
            requirePreOps: needsPreOpsCall(encodedCallConfig),
            trackPreOpsReturnData: needsPreOpsReturnData(encodedCallConfig),
            trackUserReturnData: needsUserReturnData(encodedCallConfig),
            delegateUser: needsDelegateUser(encodedCallConfig),
            localUser: needsLocalUser(encodedCallConfig),
            preSolver: needsPreSolver(encodedCallConfig),
            postSolver: needsSolverPostCall(encodedCallConfig),
            requirePostOps: needsPostOpsCall(encodedCallConfig),
            zeroSolvers: allowsZeroSolvers(encodedCallConfig),
            reuseUserOp: allowsReuseUserOps(encodedCallConfig),
            userBundler: allowsUserBundler(encodedCallConfig),
            dAppBundler: allowsDAppBundler(encodedCallConfig),
            unknownBundler: allowsUnknownBundler(encodedCallConfig)
        });
    }

    function needsSequencedNonces(uint16 callConfig) internal pure returns (bool sequenced) {
        sequenced = (callConfig & 1 << uint16(CallConfigIndex.Sequenced) != 0);
    }

    function needsPreOpsCall(uint16 callConfig) internal pure returns (bool needsPreOps) {
        needsPreOps = (callConfig & 1 << uint16(CallConfigIndex.RequirePreOps) != 0);
    }

    function needsPreOpsReturnData(uint16 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint16(CallConfigIndex.TrackPreOpsReturnData) != 0);
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

    function needsPreSolver(uint16 callConfig) internal pure returns (bool preSolver) {
        preSolver = (callConfig & 1 << uint16(CallConfigIndex.PreSolver) != 0);
    }

    function needsSolverPostCall(uint16 callConfig) internal pure returns (bool postSolver) {
        postSolver = (callConfig & 1 << uint16(CallConfigIndex.PostSolver) != 0);
    }

    function needsPostOpsCall(uint16 callConfig) internal pure returns (bool needsPostOps) {
        needsPostOps = (callConfig & 1 << uint16(CallConfigIndex.RequirePostOpsCall) != 0);
    }

    function allowsZeroSolvers(uint16 callConfig) internal pure returns (bool zeroSolvers) {
        zeroSolvers = (callConfig & 1 << uint16(CallConfigIndex.ZeroSolvers) != 0);
    }

    function allowsReuseUserOps(uint16 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = (callConfig & 1 << uint16(CallConfigIndex.ReuseUserOp) != 0);
    }

    function allowsUserBundler(uint16 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint16(CallConfigIndex.UserBundler) != 0);
    }

    function allowsDAppBundler(uint16 callConfig) internal pure returns (bool dAppBundler) {
        dAppBundler = (callConfig & 1 << uint16(CallConfigIndex.DAppBundler) != 0);
    }

    function allowsUnknownBundler(uint16 callConfig) internal pure returns (bool unknownBundler) {
        unknownBundler = (callConfig & 1 << uint16(CallConfigIndex.UnknownBundler) != 0);
    }
}
