//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;

import {IDAppControl} from "../interfaces/IDAppControl.sol";

import "../types/DAppApprovalTypes.sol";

library CallBits {
    uint32 internal constant _ONE = uint32(1);

    function buildCallConfig(address controller) internal view returns (uint32 callConfig) {
        CallConfig memory callconfig = IDAppControl(controller).getCallConfig();
        callConfig = encodeCallConfig(callconfig);
    }

    function encodeCallConfig(CallConfig memory callConfig) internal pure returns (uint32 encodedCallConfig) {
        if (callConfig.sequenced) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.Sequenced);
        }
        if (callConfig.requirePreOps) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePreOps);
        }
        if (callConfig.trackPreOpsReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.TrackPreOpsReturnData);
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
        if (callConfig.preSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.PreSolver);
        }
        if (callConfig.postSolver) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.PostSolver);
        }
        if (callConfig.requirePostOps) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequirePostOpsCall);
        }
        if (callConfig.zeroSolvers) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ZeroSolvers);
        }
        if (callConfig.reuseUserOp) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ReuseUserOp);
        }
        if(callConfig.userBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserBundler);
        }
        if (callConfig.solverBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SolverBundler);
        }
        if (callConfig.unknownBundler) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UnknownBundler);
        }
        if (callConfig.forwardReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ForwardReturnData);
        }
    }

    function decodeCallConfig(uint32 encodedCallConfig) internal pure returns (CallConfig memory callConfig) {
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
            solverBundler: allowsSolverBundler(encodedCallConfig),
            unknownBundler: allowsUnknownBundler(encodedCallConfig),
            forwardReturnData: forwardReturnData(encodedCallConfig)
        });
    }

    function needsSequencedNonces(uint32 callConfig) internal pure returns (bool sequenced) {
        sequenced = (callConfig & 1 << uint32(CallConfigIndex.Sequenced) != 0);
    }

    function needsPreOpsCall(uint32 callConfig) internal pure returns (bool needsPreOps) {
        needsPreOps = (callConfig & 1 << uint32(CallConfigIndex.RequirePreOps) != 0);
    }

    function needsPreOpsReturnData(uint32 callConfig) internal pure returns (bool needsReturnData) {
        needsReturnData = (callConfig & 1 << uint32(CallConfigIndex.TrackPreOpsReturnData) != 0);
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

    function needsPreSolver(uint32 callConfig) internal pure returns (bool preSolver) {
        preSolver = (callConfig & 1 << uint32(CallConfigIndex.PreSolver) != 0);
    }

    function needsSolverPostCall(uint32 callConfig) internal pure returns (bool postSolver) {
        postSolver = (callConfig & 1 << uint32(CallConfigIndex.PostSolver) != 0);
    }

    function needsPostOpsCall(uint32 callConfig) internal pure returns (bool needsPostOps) {
        needsPostOps = (callConfig & 1 << uint32(CallConfigIndex.RequirePostOpsCall) != 0);
    }

    function allowsZeroSolvers(uint32 callConfig) internal pure returns (bool zeroSolvers) {
        zeroSolvers = (callConfig & 1 << uint32(CallConfigIndex.ZeroSolvers) != 0);
    }

    function allowsReuseUserOps(uint32 callConfig) internal pure returns (bool reuseUserOp) {
        reuseUserOp = (callConfig & 1 << uint32(CallConfigIndex.ReuseUserOp) != 0);
    }

    function allowsUserBundler(uint32 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint32(CallConfigIndex.UserBundler) != 0);
    }

    function allowsSolverBundler(uint32 callConfig) internal pure returns (bool userBundler) {
        userBundler = (callConfig & 1 << uint32(CallConfigIndex.SolverBundler) != 0);
    }

    function allowsUnknownBundler(uint32 callConfig) internal pure returns (bool unknownBundler) {
        unknownBundler = (callConfig & 1 << uint32(CallConfigIndex.UnknownBundler) != 0);
    }

    function forwardReturnData(uint32 callConfig) internal pure returns (bool) {
        return (callConfig & 1 << uint32(CallConfigIndex.ForwardReturnData) != 0);
    }
}
