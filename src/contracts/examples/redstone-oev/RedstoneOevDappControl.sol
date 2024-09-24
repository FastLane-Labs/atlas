//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IRedstoneAdapter } from
    "lib/redstone-oracles-monorepo/packages/on-chain-relayer/contracts/core/IRedstoneAdapter.sol";

import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";

contract RedstoneOevDappControl is DAppControl {
    error OnlyGovernance();
    error OnlyWhitelistedBundlerAllowed();
    error OnlyWhitelistedOracleAllowed();
    error InvalidUserDestination();
    error InvalidUserEntryCall();
    error InvalidUserUpdateCall();
    error OracleUpdateFailed();
    error InvalidOevShare();
    error InvalidOevAllocationDestination();

    uint256 public constant OEV_SHARE_SCALE = 10_000;

    // OEV shares are in hundredth of percent
    uint256 public oevShareBundler;
    uint256 public oevShareFastlane;

    address public oevAllocationDestination;

    mapping(address bundler => bool isWhitelisted) public bundlerWhitelist;
    uint32 public whitelistedBundlersCount = 0;

    mapping(address oracle => bool isWhitelisted) public oracleWhitelist;
    uint32 public whitelistedOraclesCount = 0;

    constructor(
        address atlas,
        uint256 oevShareBundler_,
        uint256 oevShareFastlane_,
        address oevAllocationDestination_
    )
        DAppControl(
            atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
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
        if (oevShareBundler_ + oevShareFastlane_ > OEV_SHARE_SCALE) revert InvalidOevShare();
        if (oevAllocationDestination_ == address(0)) revert InvalidOevAllocationDestination();

        oevShareBundler = oevShareBundler_;
        oevShareFastlane = oevShareFastlane_;
        oevAllocationDestination = oevAllocationDestination_;
    }

    // ---------------------------------------------------- //
    //                   Custom Functions                   //
    // ---------------------------------------------------- //

    modifier onlyGov() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    function setOevShareBundler(uint256 oevShareBundler_) external onlyGov {
        if (oevShareBundler_ + oevShareFastlane > OEV_SHARE_SCALE) revert InvalidOevShare();
        oevShareBundler = oevShareBundler_;
    }

    function setOevShareFastlane(uint256 oevShareFastlane_) external onlyGov {
        if (oevShareFastlane_ + oevShareBundler > OEV_SHARE_SCALE) revert InvalidOevShare();
        oevShareFastlane = oevShareFastlane_;
    }

    function setOevAllocationDestination(address oevAllocationDestination_) external onlyGov {
        if (oevAllocationDestination_ == address(0)) revert InvalidOevAllocationDestination();
        oevAllocationDestination = oevAllocationDestination_;
    }

    // ---------------------------------------------------- //
    //              Bundler Related Functions               //
    // ---------------------------------------------------- //

    function verifyBundlerWhitelist() external view {
        // Whitelisting is enforced only if the whitelist is not empty
        if (whitelistedBundlersCount > 0 && !bundlerWhitelist[_bundler()]) revert OnlyWhitelistedBundlerAllowed();
    }

    function addBundlerToWhitelist(address bundler) external onlyGov {
        if (!bundlerWhitelist[bundler]) {
            bundlerWhitelist[bundler] = true;
            whitelistedBundlersCount++;
        }
    }

    function removeBundlerFromWhitelist(address bundler) external onlyGov {
        if (bundlerWhitelist[bundler]) {
            bundlerWhitelist[bundler] = false;
            whitelistedBundlersCount--;
        }
    }

    // ---------------------------------------------------- //
    //               Oracle Related Functions               //
    // ---------------------------------------------------- //

    function verifyOracleWhitelist(address oracle) external view {
        // Whitelisting is enforced only if the whitelist is not empty
        if (whitelistedOraclesCount > 0 && !oracleWhitelist[oracle]) revert OnlyWhitelistedOracleAllowed();
    }

    function addOracleToWhitelist(address oracle) external onlyGov {
        if (!oracleWhitelist[oracle]) {
            oracleWhitelist[oracle] = true;
            whitelistedOraclesCount++;
        }
    }

    function removeOracleFromWhitelist(address oracle) external onlyGov {
        if (oracleWhitelist[oracle]) {
            oracleWhitelist[oracle] = false;
            whitelistedOraclesCount--;
        }
    }

    // ---------------------------------------------------- //
    //                  Atlas Hook Overrides                //
    // ---------------------------------------------------- //

    /**
     * @notice Checks if the bundler is whitelisted and if the user is calling the update function
     * @param userOp The user operation to check
     * @return An empty bytes array
     * @dev This function is delegatcalled
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

        (address _oracle, bytes memory _updateCallData) = abi.decode(userOp.data[4:], (address, bytes));

        // The called oracle must be whitelisted
        RedstoneOevDappControl(_control()).verifyOracleWhitelist(_oracle);

        // The update call data must be a valid updateDataFeedsValues call
        if (bytes4(_updateCallData) != bytes4(IRedstoneAdapter.updateDataFeedsValues.selector)) {
            revert InvalidUserUpdateCall();
        }

        return "";
    }

    /**
     * @notice Allocates the bid amount to the relevant parties
     * @param bidAmount The bid amount to be allocated
     * @dev This function is delegatcalled
     */
    function _allocateValueCall(address, uint256 bidAmount, bytes calldata) internal virtual override {
        if (bidAmount == 0) return;

        // Get the OEV share for the bundler and transfer it
        uint256 _oevShareBundler = bidAmount * RedstoneOevDappControl(_control()).oevShareBundler() / OEV_SHARE_SCALE;
        if (_oevShareBundler > 0) SafeTransferLib.safeTransferETH(_bundler(), _oevShareBundler);

        // Get the OEV share for Fastlane and transfer it
        uint256 _oevShareFastlane = bidAmount * RedstoneOevDappControl(_control()).oevShareFastlane() / OEV_SHARE_SCALE;
        if (_oevShareFastlane > 0) SafeTransferLib.safeTransferETH(oevAllocationDestination, _oevShareFastlane);

        // Transfer the rest
        uint256 _oevShareDestination = bidAmount - _oevShareBundler - _oevShareFastlane;
        if (_oevShareDestination > 0) {
            SafeTransferLib.safeTransferETH(
                RedstoneOevDappControl(_control()).oevAllocationDestination(), _oevShareDestination
            );
        }
    }

    // ---------------------------------------------------- //
    //                    UserOp Function                   //
    // ---------------------------------------------------- //

    /**
     * @notice Updates the oracle with the new values
     * @param oracle The oracle to update
     * @param callData The call data to update the oracle with
     * @return An empty bytes array
     */
    function update(address oracle, bytes calldata callData) external returns (bytes memory) {
        // Parameters have already been validated in _preOpsCall
        (bool success,) = oracle.call(callData);
        if (!success) revert OracleUpdateFailed();

        return "";
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
