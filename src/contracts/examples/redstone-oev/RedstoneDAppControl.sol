//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "./RedstoneAdapterAtlasWrapper.sol";

contract RedstoneDAppControl is DAppControl {

    error InvalidBaseFeed();
    error InvalidRedstoneAdapter();
    error FailedToAllocateOEV();

    event NewRedstoneAtlasAdapterCreated(address indexed wrapper, address indexed owner, address baseAdapter, address baseFeed);

    mapping(address redstoneAtlasAdapter => bool isAdapter) public isRedstoneAdapter;

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
                trustedOpHash: false,
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
        address adapter = abi.decode(data, (address));
        if (!RedstoneDAppControl(_control()).isRedstoneAdapter(adapter)) {
            revert InvalidRedstoneAdapter();
        }
        (bool success,) = adapter.call{ value: bidAmount }("");
        if (!success) revert FailedToAllocateOEV();        
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

    function createNewAtlasAdapter(address baseAdapter, address baseFeed) external returns (address) {
        if (IChainlinkFeed(baseFeed).latestAnswer() == 0) revert InvalidBaseFeed();
        address adapter = address(new RedstoneAdapterAtlasWrapper(ATLAS, msg.sender, baseAdapter, baseFeed));
        isRedstoneAdapter[adapter] = true;
        emit NewRedstoneAtlasAdapterCreated(adapter, msg.sender, baseAdapter, baseFeed);
        return adapter;  
    }
}

interface IChainlinkFeed {
    function latestAnswer() external view returns (int256);
}