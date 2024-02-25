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
    address public immutable CHAINLINK_WRAPPER;

    constructor(
        address _atlas,
        address _wrapper
    )
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
    {
        CHAINLINK_WRAPPER = _wrapper;
    }

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    // TODO update this to a Chainlink Price Update function
    function transmit(
        bytes calldata report,
        bytes32[] calldata rs,
        bytes32[] calldata ss,
        bytes32 rawVs
    )
        external
        payable
        returns (uint256)
    {
        // TODO add checks here maybe and fix up function
        IChainlinkAtlasWrapper(CHAINLINK_WRAPPER).transmit(report, rs, ss, rawVs);
        return 0;
    }

    //////////////////////////////////
    //   ATLAS OVERRIDE FUNCTIONS   //
    //////////////////////////////////

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

interface IChainlinkAtlasWrapper {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}
