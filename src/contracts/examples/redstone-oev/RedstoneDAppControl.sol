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
    error OnlyWhitelistedBundlerAllowed();

    uint256 public immutable bundlerOEVPercent = 5;

    event NewRedstoneAtlasAdapterCreated(address indexed wrapper, address indexed owner, address indexed baseFeed);

    mapping(address redstoneAtlasAdapter => bool isAdapter) public isRedstoneAdapter;

    mapping(address bundler => bool isWhitelisted) public bundlerWhitelist;
    uint32 public NUM_WHITELISTED_BUNDLERS = 0;

    constructor(
        address _atlas
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: true,
                trackUserReturnData: false,
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

    function addBundlerToWhitelist(address bundler) external onlyGov {
        if (!bundlerWhitelist[bundler]) {
            bundlerWhitelist[bundler] = true;
            NUM_WHITELISTED_BUNDLERS++;
        }
    }

    function removeBundlerFromWhitelist(address bundler) external onlyGov {
        if (bundlerWhitelist[bundler]) {
            bundlerWhitelist[bundler] = false;
            NUM_WHITELISTED_BUNDLERS--;
        }
    }

    function _onlyGov() internal view {
        if (msg.sender != governance) revert OnlyGovernance();
    }

    modifier onlyGov() {
        _onlyGov();
        _;
    }

    function verifyWhitelist() external view {
        if (NUM_WHITELISTED_BUNDLERS > 0 && !bundlerWhitelist[_bundler()]) revert OnlyWhitelistedBundlerAllowed();
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    function _preOpsCall(UserOperation calldata userOp) internal view override returns (bytes memory) {
        RedstoneDAppControl(userOp.control).verifyWhitelist();
        return abi.encode(userOp.dapp);
    }

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata data) internal virtual override {
        if (bidAmount == 0) return;

        uint256 oevForBundler = (bidAmount * bundlerOEVPercent) / 100;
        uint256 oevForAdapter = bidAmount - oevForBundler;

        address adapter = abi.decode(data, (address)); // returned from _preOpsCall
        if (!RedstoneDAppControl(_control()).isRedstoneAdapter(adapter)) {
            revert InvalidRedstoneAdapter();
        }
        (bool success,) = adapter.call{ value: oevForAdapter }("");
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
