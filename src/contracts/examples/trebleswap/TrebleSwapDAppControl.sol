//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";

// NOTES:
// Support for native in/out?
// Support for bid token (TREB) in/out?

contract TrebleSwapDAppControl is DAppControl {
    // TODO WETH on Base for now, change to TREB when token deployed
    address public constant TREB = address(0x4200000000000000000000000000000000000006);
    address internal constant _NATIVE_TOKEN = address(0);

    constructor(
        address atlas
    )
        DAppControl(
            atlas,
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
                requirePostOps: true,
                zeroSolvers: true,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: true, // TODO confirm: bids discovered on-chain?
                allowAllocateValueFailure: false
            })
        )
    { }

    // ---------------------------------------------------- //
    //                     ATLAS HOOKS                      //
    // ---------------------------------------------------- //

    function _preOpsCall(UserOperation calldata userOp) internal virtual override returns (bytes memory) {
        // User approves Atlas before tx, so pull tokens via Permit69 here, to be used in UserOperation.
        // Use preOps hook to extract swap data (tokenIn, tokenOut, amounts)
        // Validate userOp.data is correct format for UserOperation call to router
        // Return extracted swap data for safety checks in allocateValue
    }

    // UserOperation happens here. EE calls router (userOp.dapp) with userOp.data as calldata.

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata data) internal virtual override {
        // Solver bid (in TREB) gets burnt here
        // Send user back their tokenOut from the swap, and any leftover tokenIn
        // Revert here if swap fails
    }

    // ---------------------------------------------------- //
    //                 GETTERS AND HELPERS                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata) public view virtual override returns (address bidToken) {
        return TREB;
    }

    function getBidValue(SolverOperation calldata solverOp) public view virtual override returns (uint256) {
        return solverOp.bidAmount;
    }
}
