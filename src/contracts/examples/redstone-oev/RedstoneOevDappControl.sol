//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "./RedstoneAdapterAtlasWrapper.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";


contract RedstoneOevDappControl is DAppControl {
    error FailedToAllocateOEV();
    error OnlyGovernance();
    error OnlyWhitelistedBundlerAllowed();
    error OracleUpdateFailed();

    uint256 public bundlerOEVPercent;
    uint256 public atlasOEVPercent;
    address public atlasVault;
    address public oracleVault;

    mapping(address bundler => bool isWhitelisted) public bundlerWhitelist;
    uint32 public NUM_WHITELISTED_BUNDLERS = 0;

    constructor(
        address _atlas,
        address _atlasVault,
        address _oracleVault,
        uint256 _bundlerOEVPercent,
        uint256 _atlasOEVPercent
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
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
    {
        bundlerOEVPercent = _bundlerOEVPercent;
        atlasOEVPercent = _atlasOEVPercent;
        atlasVault = _atlasVault;
        oracleVault = _oracleVault;
    }

    function setBundlerOEVPercent(uint256 _bundlerOEVPercent) external onlyGov {
        require(_bundlerOEVPercent + atlasOEVPercent <= 100, "Invalid OEV percent");
        bundlerOEVPercent = _bundlerOEVPercent;
    }

    function setAtlasOEVPercent(uint256 _atlasOEVPercent) external onlyGov {
        require(_atlasOEVPercent + bundlerOEVPercent <= 100, "Invalid OEV percent");
        atlasOEVPercent = _atlasOEVPercent;
    }

    function setAtlasVault(address _atlasVault) external onlyGov {
        atlasVault = _atlasVault;
    }

    function setOracleVault(address _oracleVault) external onlyGov {
        oracleVault = _oracleVault;
    }

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

    function verifyBundlerWhitelist() external view {
        if (NUM_WHITELISTED_BUNDLERS > 0 && !bundlerWhitelist[_bundler()]) revert OnlyWhitelistedBundlerAllowed();
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata) internal virtual override {
        if (bidAmount == 0) return;

        uint256 oevPercentBundler = RedstoneOevDappControl(_control()).bundlerOEVPercent();
        uint256 oevPercentAtlas = RedstoneOevDappControl(_control()).atlasOEVPercent();
        address vaultAtlas = RedstoneOevDappControl(_control()).atlasVault();
        address vaultOracle = RedstoneOevDappControl(_control()).oracleVault();

        uint256 bundlerOev = (bidAmount * oevPercentBundler) / 100;
        uint256 atlasOev = (bidAmount * oevPercentAtlas) / 100;
        uint256 oracleOev = bidAmount - bundlerOev - atlasOev;

        (bool success,) = vaultOracle.call{ value: oracleOev }("");
        if (!success) revert FailedToAllocateOEV();

        (success,) = vaultAtlas.call{ value: atlasOev }("");
        if (!success) revert FailedToAllocateOEV();

        if (bundlerOev > 0) SafeTransferLib.safeTransferETH(_bundler(), bundlerOev);
    }

    // ---------------------------------------------------- //
    //                    UserOp function                   //
    // ---------------------------------------------------- //

    function update(address oracle, bytes calldata callData) external  {
        RedstoneOevDappControl(_control()).verifyBundlerWhitelist();
        (bool success,) = oracle.call(callData);
        if (!success) revert OracleUpdateFailed();
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
}
