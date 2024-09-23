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
    error InvalidOevShare();

    uint256 public constant OEV_SHARE_SCALE = 10_000;

    uint256 public oevShareBundler; // In hundredth of percent
    address public oevAllocationDestination;

    mapping(address bundler => bool isWhitelisted) public bundlerWhitelist;
    uint32 public NUM_WHITELISTED_BUNDLERS = 0;

    mapping(address oracle => bool isWhitelisted) public oracleWhitelist;
    uint32 public NUM_WHITELISTED_ORACLES = 0;

    constructor(
        address _atlas,
        uint256 _oevShareBundler,
        address _oevAllocationDestination
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
        oevShareBundler = _oevShareBundler;
        oevAllocationDestination = _oevAllocationDestination;
    }

    // ---------------------------------------------------- //
    //                   Custom Functions                   //
    // ---------------------------------------------------- //

    modifier onlyGov() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    function setOevShareBundler(uint256 _oevShareBundler) external onlyGov {
        if (_oevShareBundler > OEV_SHARE_SCALE) revert InvalidOevShare();
        oevShareBundler = _oevShareBundler;
    }

    function setOevAllocationDestination(address _oevAllocationDestination) external onlyGov {
        oevAllocationDestination = _oevAllocationDestination;
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

        (address oracle, bytes memory updateCallData) = abi.decode(userOp.data[4:], (address, bytes));

        // The called oracle must be whitelisted
        RedstoneOevDappControl(_control()).verifyOracleWhitelist(oracle);

        // The update call data must be a valid updateDataFeedsValues call
        if (bytes4(updateCallData) != bytes4(IRedstoneAdapter.updateDataFeedsValues.selector)) {
            revert InvalidUserUpdateCall();
        }

        return "";
    }

    /**
     * @notice Allocates the bid amount to the relevant parties
     * @param bidAmount The bid amount to be allocated
     * @param returnData The return data from the user operation
     */
    function _allocateValueCall(address, uint256 bidAmount, bytes calldata returnData) internal virtual override {
        if (bidAmount == 0) return;

        // Returned from the user operation
        address oracle = abi.decode(returnData, (address));

        // Get the OEV share for the bundler and transfer it
        uint256 oevShareBundler = bidAmount * RedstoneOevDappControl(_control()).oevShareBundler() / OEV_SHARE_SCALE;
        if (oevShareBundler > 0) SafeTransferLib.safeTransferETH(_bundler(), oevShareBundler);

        // Transfer the rest
        SafeTransferLib.safeTransferETH(
            RedstoneOevDappControl(_control()).oevAllocationDestination(), bidAmount - oevShareBundler
        );
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
