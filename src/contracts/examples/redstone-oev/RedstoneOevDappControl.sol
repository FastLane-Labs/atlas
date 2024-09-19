//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "./RedstoneAdapterAtlasWrapper.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IRedstoneAdapter } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";

contract RedstoneOevDappControl is DAppControl {
    error OnlyGovernance();
    error OnlyWhitelistedBundlerAllowed();
    error OnlyWhitelistedOracleAllowed();
    error InvalidUserDestination();
    error InvalidUserEntryCall();
    error InvalidUserUpdateCall();
    error OracleUpdateFailed();

    uint256 public bundlerOEVPercent;
    uint256 public atlasOEVPercent;
    address public atlasVault;
    mapping(address oracle => address oracleVault) public oracleVaults;

    mapping(address bundler => bool isWhitelisted) public bundlerWhitelist;
    uint32 public NUM_WHITELISTED_BUNDLERS = 0;

    mapping(address oracle => bool isWhitelisted) public oracleWhitelist;
    uint32 public NUM_WHITELISTED_ORACLES = 0;

    constructor(
        address _atlas,
        address _atlasVault,
        uint256 _bundlerOEVPercent,
        uint256 _atlasOEVPercent
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: false,
                zeroSolvers: true, // Oracle updates can be made without solvers and no OEV
                reuseUserOp: true,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false, // Update oracle even if all solvers fail
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: true // Oracle updates should go through even if OEV allocation fails
             })
        )
    {
        bundlerOEVPercent = _bundlerOEVPercent;
        atlasOEVPercent = _atlasOEVPercent;
        atlasVault = _atlasVault;
    }

    // ---------------------------------------------------- //
    //                   Custom Functions                   //
    // ---------------------------------------------------- //

    modifier onlyGov() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
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

    function setOracleVault(address oracle, address _oracleVault) external onlyGov {
        oracleVaults[oracle] = _oracleVault;
    }

    // ---------------------------------------------------- //
    //              Bundler Related Functions               //
    // ---------------------------------------------------- //

    function verifyBundlerWhitelist() external view {
        // Whitelisting is enforced only if the whitelist is not empty
        if (NUM_WHITELISTED_BUNDLERS > 0 && !bundlerWhitelist[_bundler()]) revert OnlyWhitelistedBundlerAllowed();
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

    // ---------------------------------------------------- //
    //               Oracle Related Functions               //
    // ---------------------------------------------------- //

    function verifyOracleWhitelist(address oracle) external view {
        // Whitelisting is enforced only if the whitelist is not empty
        if (NUM_WHITELISTED_ORACLES > 0 && !oracleWhitelist[oracle]) revert OnlyWhitelistedOracleAllowed();
    }

    function addOracleToWhitelist(address oracle) external onlyGov {
        if (!oracleWhitelist[oracle]) {
            oracleWhitelist[oracle] = true;
            NUM_WHITELISTED_ORACLES++;
        }
    }

    function removeOracleFromWhitelist(address oracle) external onlyGov {
        if (oracleWhitelist[oracle]) {
            oracleWhitelist[oracle] = false;
            NUM_WHITELISTED_ORACLES--;
        }
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    /**
     * @notice Checks if the bundler is whitelisted and if the user is calling the update function
     * @param userOp The user operation to check
     * @return An empty bytes array
     */
    function _preOpsCall(UserOperation calldata userOp) internal view override returns (bytes memory) {
        // The bundler must be whitelisted
        RedstoneOevDappControl(_control()).verifyBundlerWhitelist();

        // The user must be calling the present contract
        if (userOp.dapp != _control()) revert InvalidUserDestination();

        // The user must be calling the update function
        if (bytes4(userOp.data) != bytes4(RedstoneOevDappControl.update.selector)) {
            revert InvalidUserEntryCall();
        }

        (address oracle, bytes memory updateCallData) = abi.decode(userOp.data[4:], (address, bytes));

        // The called oracle must be whitelisted
        RedstoneOevDappControl(_control()).verifyOracleWhitelist(oracle);

        // The update call data must be a valid updateDataFeedsValues call
        if (bytes4(updateCallData) != bytes4(IRedstoneAdapter.updateDataFeedsValues.selector)) {
            revert InvalidUserUpdateCall();
        }

        return "";
    }

    function _allocateValueCall(address, uint256 bidAmount, bytes calldata returnData) internal virtual override {
        if (bidAmount == 0) return;

        address oracle = abi.decode(returnData, (address));

        uint256 oevPercentBundler = RedstoneOevDappControl(_control()).bundlerOEVPercent();
        uint256 oevPercentAtlas = RedstoneOevDappControl(_control()).atlasOEVPercent();
        address vaultAtlas = RedstoneOevDappControl(_control()).atlasVault();
        address vaultOracle = RedstoneOevDappControl(_control()).oracleVaults(oracle);

        uint256 bundlerOev = (bidAmount * oevPercentBundler) / 100;
        uint256 atlasOev = (bidAmount * oevPercentAtlas) / 100;
        uint256 oracleOev = bidAmount - bundlerOev - atlasOev;

        if (oracleOev > 0) SafeTransferLib.safeTransferETH(vaultOracle, oracleOev);
        if (atlasOev > 0) SafeTransferLib.safeTransferETH(vaultAtlas, atlasOev);
        if (bundlerOev > 0) SafeTransferLib.safeTransferETH(_bundler(), bundlerOev);
    }

    // ---------------------------------------------------- //
    //                    UserOp Function                   //
    // ---------------------------------------------------- //

    /**
     * @notice Updates the oracle with the new values
     * @param oracle The oracle to update
     * @param callData The call data to update the oracle with
     * @return The encoded address of the updated oracle, that will be later on used in _allocateValueCall
     */
    function update(address oracle, bytes calldata callData) external returns (bytes memory) {
        // Parameters have already been validated in _preOpsCall
        (bool success,) = oracle.call(callData);
        if (!success) revert OracleUpdateFailed();

        return abi.encode(oracle);
    }

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
