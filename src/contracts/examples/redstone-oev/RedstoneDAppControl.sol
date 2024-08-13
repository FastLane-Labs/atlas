//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "./RedstoneAdapterAtlasWrapper.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract RedstoneDAppControl is DAppControl {
    error InvalidBaseFeed();
    error InvalidRedstoneAdapter();
    error FailedToAllocateOEV();
    error OnlyGovernance();

    uint256 private bundlerOEVPercent = 5;

    event NewRedstoneAtlasAdapterCreated(address indexed wrapper, address indexed owner, address indexed baseFeed);

    mapping(address redstoneAtlasAdapter => bool isAdapter) public isRedstoneAdapter;

    constructor(
        address _atlas
    )
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
                zeroSolvers: true, // oracle updates can be made without solvers and no OEV
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: true // oracle updates should go through even if OEV allocation fails
             })
        )
    { }

    function setBundlerOEVPercent(uint256 _percent) external onlyGov {
        bundlerOEVPercent = _percent;
    }

    function _onlyGov() internal view {
        if (msg.sender != governance) revert OnlyGovernance();
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata data) internal virtual override {
        uint256 oevForBundler = bidAmount * bundlerOEVPercent / 100;
        uint256 oevForSolver = bidAmount - oevForBundler;

        address adapter = abi.decode(data, (address));
        if (!RedstoneDAppControl(_control()).isRedstoneAdapter(adapter)) {
            revert InvalidRedstoneAdapter();
        }
        (bool success,) = adapter.call{ value: oevForSolver }("");
        if (!success) revert FailedToAllocateOEV();

        SafeTransferLib.safeTransferETH(_bundler(), oevForBundler);
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

    // ---------------------------------------------------- //
    //                   AtlasAdapterFactory                //
    // ---------------------------------------------------- //
    function createNewAtlasAdapter(address baseFeed) external returns (address) {
        if (IFeed(baseFeed).latestAnswer() == 0) revert InvalidBaseFeed();
        address adapter = address(new RedstoneAdapterAtlasWrapper(ATLAS, msg.sender, baseFeed));
        isRedstoneAdapter[adapter] = true;
        emit NewRedstoneAtlasAdapterCreated(adapter, msg.sender, baseFeed);
        return adapter;
    }
}
