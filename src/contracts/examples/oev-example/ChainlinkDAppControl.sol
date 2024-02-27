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
    address public immutable CHAINLINK_WRAPPER; // TODO remove and use userOp.dapp addr instead to target protocol
        // wrapper

    event NewChainlinkWrapperCreated(address wrapper, address baseFeed, address owner);

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
                requirePreOps: true,
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

    // Update the ChainlinkAtlasWrapper at userOp.dapp address, with Chainlink transmit data
    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory) {
        (bytes memory report, bytes32[] memory rs, bytes32[] memory ss, bytes32 rawVs) =
            abi.decode(userOp.data, (bytes, bytes32[], bytes32[], bytes32));

        IChainlinkAtlasWrapper(userOp.dapp).transmit(report, rs, ss, rawVs);
    }

    // TODO remove this
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external {
        IChainlinkAtlasWrapper(CHAINLINK_WRAPPER).transmit(report, rs, ss, rawVs);
    }

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
        address newWrapper = address(new ChainlinkAtlasWrapper(atlas, baseChainlinkFeed, msg.sender));
        emit NewChainlinkWrapperCreated(newWrapper, baseChainlinkFeed, msg.sender);
        return newWrapper;
    }
}

interface IChainlinkAtlasWrapper {
    function transmit(bytes calldata report, bytes32[] calldata rs, bytes32[] calldata ss, bytes32 rawVs) external;
}
