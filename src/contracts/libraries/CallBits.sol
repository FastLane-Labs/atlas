//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IDAppControl } from "../interfaces/IDAppControl.sol";

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
        if (callConfig.userAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UserAuctioneer);
        }
        if (callConfig.solverAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.SolverAuctioneer);
        }
        if (callConfig.unknownAuctioneer) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.UnknownAuctioneer);
        }
        if (callConfig.verifyCallChainHash) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.VerifyCallChainHash);
        }
        if (callConfig.forwardReturnData) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.ForwardReturnData);
        }
        if (callConfig.requireFulfillment) {
            encodedCallConfig ^= _ONE << uint32(CallConfigIndex.RequireFulfillment);
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
            userAuctioneer: allowsUserAuctioneer(encodedCallConfig),
            solverAuctioneer: allowsSolverAuctioneer(encodedCallConfig),
            unknownAuctioneer: allowsUnknownAuctioneer(encodedCallConfig),
            verifyCallChainHash: verifyCallChainHash(encodedCallConfig),
            forwardReturnData: forwardReturnData(encodedCallConfig),
            requireFulfillment: needsFulfillment(encodedCallConfig)
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

    function allowsUserAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = (callConfig & 1 << uint32(CallConfigIndex.UserAuctioneer) != 0);
    }

    function allowsSolverAuctioneer(uint32 callConfig) internal pure returns (bool userAuctioneer) {
        userAuctioneer = (callConfig & 1 << uint32(CallConfigIndex.SolverAuctioneer) != 0);
    }

    function allowsUnknownAuctioneer(uint32 callConfig) internal pure returns (bool unknownAuctioneer) {
        unknownAuctioneer = (callConfig & 1 << uint32(CallConfigIndex.UnknownAuctioneer) != 0);
    }

    function verifyCallChainHash(uint32 callConfig) internal pure returns (bool verify) {
        verify = (callConfig & 1 << uint32(CallConfigIndex.VerifyCallChainHash) != 0);
    }

    function forwardReturnData(uint32 callConfig) internal pure returns (bool) {
        return (callConfig & 1 << uint32(CallConfigIndex.ForwardReturnData) != 0);
    }

    function needsFulfillment(uint32 callConfig) internal pure returns (bool) {
        return (callConfig & 1 << uint32(CallConfigIndex.RequireFulfillment) != 0);
    }
}
