//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";

import "forge-std/Test.sol";

contract ChainlinkDAppControl is DAppControl {
    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequenced: false,
                dappNoncesSequenced: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: true,
                preSolver: false,
                postSolver: false,
                requirePostOps: true, // update base oracle in postOps
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: true
            })
        )
    { }

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    // TODO update this to a Chainlink Price Update function
    // swap() selector = 0x98434997
    function swap() external payable returns (uint256) { }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

    function _preSolverCall(bytes calldata data) internal override returns (bool) {
        (address solverTo,, bytes memory returnData) = abi.decode(data, (address, uint256, bytes));
        if (solverTo == address(this) || solverTo == _control() || solverTo == escrow) {
            return false;
        }

        // TODO add logic here if pre solver phase needed

        return true;
    }

    // Update the base Chainlink Price Oracle after solvers have had an opportunity
    function _postOpsCall(bool solved, bytes calldata data) internal override returns (bool) {
        // TODO extract from data:
        // - aggregator contract (address)
        // - rs (bytes32[] calldata) [array of oracle sig r peices]
        // - ss (bytes32[] calldata) [array of oracle sig s peices]
        // - rawVs (bytes32) [array of oracle sig v peices]
        // - report (bytes calldata)

        // call transmit() on the target aggregator contract
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        // TODO add logic here if custom logic needed at value allocation time
    }

    /////////////////////////////////////////////////////////
    ///////////////// GETTERS & HELPERS // //////////////////
    /////////////////////////////////////////////////////////
    // NOTE: These are not delegatecalled

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        // TODO add bid format - LINK token?

        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}

interface ChainlinkAggregator {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}
