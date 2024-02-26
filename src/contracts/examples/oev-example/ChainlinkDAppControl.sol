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
                trackUserReturnData: false,
                delegateUser: true,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
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

    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external {
        IChainlinkAtlasWrapper(CHAINLINK_WRAPPER).transmit(report, rs, ss, rawVs);
    }

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal virtual override {
        // TODO send ETH bid to Chainlink or Protocol that created liquidation opportunity
    }

    /////////////////////////////////////////////////////////
    ///////////////// GETTERS & HELPERS // //////////////////
    /////////////////////////////////////////////////////////
    // NOTE: These are not delegatecalled

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        // Address(0) --> ETH is bid token
        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}

interface IChainlinkAtlasWrapper {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}
