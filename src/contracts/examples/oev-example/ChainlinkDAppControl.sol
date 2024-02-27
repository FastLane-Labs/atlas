//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { CallConfig } from "src/contracts/types/DAppApprovalTypes.sol";
import "src/contracts/types/UserCallTypes.sol";
import "src/contracts/types/SolverCallTypes.sol";
import "src/contracts/types/LockTypes.sol";

// Atlas DApp-Control Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { ChainlinkAtlasWrapper } from "src/contracts/examples/oev-example/ChainlinkAtlasWrapper.sol";

import "forge-std/Test.sol";

// NOTE: This contract acts as the Chainlink DAppControl for Atlas,
// and as a factory for ChainlinkAtlasWrapper contracts
contract ChainlinkDAppControl is DAppControl {
    error InvalidBaseFeed();

    event NewChainlinkWrapperCreated(address indexed wrapper, address indexed baseFeed, address indexed owner);

    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequenced: false,
                dappNoncesSequenced: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: false, //TODO return address here
                delegateUser: false,
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
    { }

    //////////////////////////////////
    // CONTRACT-SPECIFIC FUNCTIONS  //
    //////////////////////////////////

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal virtual override {
        // TODO need to get userOp.dapp address to here to allocate OEV to wrapper
    }

    /////////////////////////////////////////////////////////
    ///////////////// GETTERS & HELPERS // //////////////////
    /////////////////////////////////////////////////////////
    // NOTE: These are not delegatecalled

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        return address(0); // ETH is bid token
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }

    // ---------------------------------------------------- //
    //          ChainlinkWrapper Factory Functions          //
    // ---------------------------------------------------- //

    // Creates a new wrapper contract for a specific Chainlink feed, to attribute OEV captured by Atlas to the
    // OEV-generating protocol.
    function createNewChainlinkAtlasWrapper(address baseChainlinkFeed) external returns (address) {
        if (IChainlinkFeed(baseChainlinkFeed).latestAnswer() == 0) revert InvalidBaseFeed();

        address newWrapper = address(new ChainlinkAtlasWrapper(atlas, baseChainlinkFeed, msg.sender));
        emit NewChainlinkWrapperCreated(newWrapper, baseChainlinkFeed, msg.sender);
        return newWrapper;
    }
}

interface IChainlinkAtlasWrapper {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}

interface IChainlinkFeed {
    function latestAnswer() external view returns (int256);
}
