//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";

contract RedstoneDAppControl is DAppControl {
    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: true,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: false
            })
        )
    { }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata data) internal virtual override {

    }

    // NOTE: Functions below are not delegatecalled

    // ---------------------------------------------------- //
    //                    View Functions                    //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        return address(0); // ETH is bid token
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    function createNewAdapterWrapper() external returns (address) {
        
    }
}