//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";

// Interface Import
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";

struct Approval {
    address token;
    address spender;
    address amount; // 0 = balanceOf(address(this))
}

struct Beneficiary {
    address owner;
    uint256 percentage; // out of 100
}
// NOTE user gets remainder


interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

contract GeneralizedBackrunUserBundler is DAppControl {

    address private storage _userLock = address(1); // TODO: Convert to transient storage

    address public immutable VERIFICATION;

    address private constant _FEE_BASE = 100;


    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: true,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: false,
                reuseUserOp: false,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: true
            })
        )
    { 
        VERIFICATION = IAtlas(_atlas).VERIFICATION();
    }

    // ---------------------------------------------------- //
    //                       Custom                         //
    // ---------------------------------------------------- //

    // Control functions that aren't delegated

    modifier withUserLock() {
        if (address(this) != CONTROL) revert();
        if (_userLock != address(1)) revert();
        _userLock = msg.sender;
        _;
        _userLock = address(1);
    }

    function getUser() external view returns (address) {
        address _user = _userLock;
        if (_user == address(1)) revert();
        if (address(this) != CONTROL) revert();
        return _user;
    }

    // Entrypoint function
    function forward(
        Approval[] calldata approvals, 
        address[] calldata receivables,
        Beneficiary[] calldata beneficiaries,
        address innerTarget,
        bytes calldata innerData
        SolverOperation[] calldata solverOps,
    )  
        external 
        payable 
        withUserLock
    {

        bytes memory _outerData = abi.encodeCall(this.proxyCall, (approvals, receivables, beneficiaries, innerTarget, innerData));

        UserOperation memory userOp = UserOperation({
            from: address(this), // User address (replaced with this entrypoint)
            to: ATLAS, // Atlas address
            value: msg.value, // Amount of ETH required for the user operation (used in `value` field of the user call)
            gas: gasleft(), // Gas limit for the user operation
            maxFeePerGas: tx.gasprice,// Max fee per gas for the user operation
            nonce: uint256(keccak256(block.number, msg.sender)), // Atlas nonce of the user operation available in the AtlasVerification contract
            deadline: block.number, // block.number deadline for the user operation
            dapp: address(this), // Nested "to" for user's call (used in `to` field of the user call)
            control: address(this), // Address of the DAppControl contract
            callConfig: CALL_CONFIG, // Call configuration expected by user, refer to `src/contracts/types/ConfigTypes.sol:CallConfig`
            sessionKey: address(this), // Address of the temporary session key which is used to sign the DappOperation
            data: _outerData, // User operation calldata (used in `data` field of the user call)
            signature: new bytes(0) // User operation signature signed by UserOperation.from
        });
        
        bytes32 _userOpHash = IAtlasVerification(VERIFICATION).getUserOperationHash(userOp);

        DAppOperation memory dAppOp =  DAppOperation({
            from: address(this), // signer of the DAppOperation
            to: ATLAS,  // Atlas address
            nonce: 0, // Atlas nonce of the DAppOperation available in the AtlasVerification contract
            deadline: block.number,  // block.number deadline for the DAppOperation
            control: address(this), // DAppControl address
            bundler: address(this), // Signer of the atlas tx (msg.sender)
            userOpHash: _userOpHash,// keccak256 of userOp.to, userOp.data
            callChainHash: bytes32(0), // keccak256 of the solvers' txs
            signature: new bytes(0) // DAppOperation signed by DAppOperation.from
        });
        
    }

    // NOTE: this is delegatecalled
    function proxyCall(
        Approval[] calldata approvals, 
        address[] calldata receivables,
        Beneficiary[] calldata beneficiaries,
        address innerTarget,
        bytes calldata innerData
    )  
        external 
        onlyAtlasEnvironment 
        returns (Beneficiary[] memory)
    {
        if (address(this) == )
        // Handle approvals
        for (uint256 i; i < approvals.length; i++) {
            Approval calldata approval = approvals[i];

            // Transfer the User's token to the EE:
            _transferUserERC20(approval.token, address(this), approval.amount);

            // Have the EE approve the User's target:
            IERC20(approval.token).approve(approval.spender, approval.amount);
        }

        // Do the actual call
        (bool _success,) = innerTarget.call{ value: msg.value}(innerData);
        // Bubble up the revert message (note there's not really a reason to do this, 
        // we'll replace with a custom error soon.
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        address _recipient = _user();
        if (_recipient == CONTROL) _recipient = IGeneralizedBackrunProxy(CONTROL).getUser();

        // Reset approvals for the EE
        for (uint256 i; i < approvals.length; i++) {
            Approval calldata approval = approvals[i];

            // Remove the EE's approvals
            IERC20(approval.token).approve(approval.spender, 0);

            uint256 _balance = IERC20(approval.token).balanceOf(address(this));

            // Transfer any leftover tokens back to the User
            if (_balance != 0) {
                IERC20(transfer.token).transfer(_user(), _balance);
            }
        }

        // Return the receivable tokens to the user
        for (uint256 i; i < receivables.length; i++) {

            address _receivable = receivables[i];
            uint256 _balance = IERC20(receivable).balanceOf(address(this));

            // Transfer the EE's tokens (note that this will revert if balance is insufficient)
            if (_balance != 0) {
                IERC20(_receivable).transfer(_user(), _balance);
            }
        }

        // Forward any value that accrued
        uint256 _balance = address(this).balance;
        if (_balance > 0) {
            SafeTransferLib.safeTransferETH(_user(), _balance);
        }
        return beneficiaries;
    }

    // ---------------------------------------------------- //
    //                     Atlas hooks                      //
    // ---------------------------------------------------- //

    /*
    * @notice This function is called after a solver has successfully paid their bid
    * @dev This function is delegatecalled: msg.sender = Atlas, address(this) = ExecutionEnvironment
    * @dev It transfers all the available bid tokens on the contract (instead of only the bid amount,
    *      to avoid leaving any dust on the contract)
    * @param bidToken The address of the token used for the winning solver operation's bid
    * @param _
    * @param _
    */
    function _allocateValueCall(address bidToken, uint256, bytes calldata returnData) internal override {
        uint256 _balance = address(this).balance;

        // NOTE: The _user() receives any remaining balance after the other beneficiaries are paid.
        Beneficiary[] memory _beneficiaries = abi.decode(returnData, (Beneficiary[]));

        //struct Beneficiary {
        //    address owner;
        //    uint256 percentage; // out of 100
        //}

        uint256 _unallocatedPercent = _FEE_BASE;

        // Return the receivable tokens to the user
        for (uint256 i; i < _beneficiaries.length; i++) {
            uint256 _percentage = _beneficiaries[i].percentage;
            if (percentage < _unallocatedPercent) {
                _unallocatedPercent -= _percentage;
                SafeTransferLib.safeTransferETH(_beneficiaries[i].owner, _balance * _percentage / _FEE_BASE);
            } else {
                SafeTransferLib.safeTransferETH(_beneficiaries[i].owner, address(this).balance);
            }
        }

        // Transfer the remaining value to the user
        if (_unallocatedPercent != 0) {
            SafeTransferLib.safeTransferETH(_user(), address(this).balance);
        }
    }

    // ---------------------------------------------------- //
    //                 Getters and helpers                  //
    // ---------------------------------------------------- //

    function getBidFormat(UserOperation calldata userOp) public pure override returns (address bidToken) {
        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}