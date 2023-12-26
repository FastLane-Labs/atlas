// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { CallConfig } from "../../src/contracts/types/DAppApprovalTypes.sol";

import "forge-std/Test.sol";

contract CallConfigBuilder is Test {
    bool sequenced;
    bool requirePreOps;
    bool trackPreOpsReturnData;
    bool trackUserReturnData;
    bool delegateUser;
    bool preSolver;
    bool postSolver;
    bool requirePostOps;
    bool zeroSolvers;
    bool reuseUserOp;
    bool userAuctioneer;
    bool solverAuctioneer;
    bool unknownAuctioneer;
    bool verifyCallChainHash;
    bool forwardReturnData;
    bool requireFulfillment;

    function withSequenced(bool _sequenced) public returns (CallConfigBuilder) {
        sequenced = _sequenced;
        return this;
    }

    function withRequirePreOps(bool _requirePreOps) public returns (CallConfigBuilder) {
        requirePreOps = _requirePreOps;
        return this;
    }

    function withTrackPreOpsReturnData(bool _trackPreOpsReturnData) public returns (CallConfigBuilder) {
        trackPreOpsReturnData = _trackPreOpsReturnData;
        return this;
    }

    function withTrackUserReturnData(bool _trackUserReturnData) public returns (CallConfigBuilder) {
        trackUserReturnData = _trackUserReturnData;
        return this;
    }

    function withDelegateUser(bool _delegateUser) public returns (CallConfigBuilder) {
        delegateUser = _delegateUser;
        return this;
    }

    function withPreSolver(bool _preSolver) public returns (CallConfigBuilder) {
        preSolver = _preSolver;
        return this;
    }

    function withPostSolver(bool _postSolver) public returns (CallConfigBuilder) {
        postSolver = _postSolver;
        return this;
    }

    function withRequirePostOps(bool _requirePostOps) public returns (CallConfigBuilder) {
        requirePostOps = _requirePostOps;
        return this;
    }

    function withZeroSolvers(bool _zeroSolvers) public returns (CallConfigBuilder) {
        zeroSolvers = _zeroSolvers;
        return this;
    }

    function withReuseUserOp(bool _reuseUserOp) public returns (CallConfigBuilder) {
        reuseUserOp = _reuseUserOp;
        return this;
    }

    function withUserAuctioneer(bool _userAuctioneer) public returns (CallConfigBuilder) {
        userAuctioneer = _userAuctioneer;
        return this;
    }

    function withSolverAuctioneer(bool _solverAuctioneer) public returns (CallConfigBuilder) {
        solverAuctioneer = _solverAuctioneer;
        return this;
    }

    function withUnknownAuctioneer(bool _unknownAuctioneer) public returns (CallConfigBuilder) {
        unknownAuctioneer = _unknownAuctioneer;
        return this;
    }

    function withVerifyCallChainHash(bool _verifyCallChainHash) public returns (CallConfigBuilder) {
        verifyCallChainHash = _verifyCallChainHash;
        return this;
    }

    function withForwardReturnData(bool _forwardReturnData) public returns (CallConfigBuilder) {
        forwardReturnData = _forwardReturnData;
        return this;
    }

    function withRequireFulfillment(bool _requireFulfillment) public returns (CallConfigBuilder) {
        requireFulfillment = _requireFulfillment;
        return this;
    }

    function build() public view returns (CallConfig memory) {
        return CallConfig(
            sequenced,
            requirePreOps,
            trackPreOpsReturnData,
            trackUserReturnData,
            delegateUser,
            preSolver,
            postSolver,
            requirePostOps,
            zeroSolvers,
            reuseUserOp,
            userAuctioneer,
            solverAuctioneer,
            unknownAuctioneer,
            verifyCallChainHash,
            forwardReturnData,
            requireFulfillment
        );
    }
}
