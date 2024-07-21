//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

// Base Imports
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Atlas Imports
import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { DAppOperation } from "src/contracts/types/DAppOperation.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";
import "src/contracts/types/LockTypes.sol";
import "src/contracts/types/EscrowTypes.sol";

// Interface Import
import { IAtlasVerification } from "src/contracts/interfaces/IAtlasVerification.sol";
import { IExecutionEnvironment } from "src/contracts/interfaces/IExecutionEnvironment.sol";
import { IAtlas } from "src/contracts/interfaces/IAtlas.sol";

import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { FastLaneOnlineInner } from "src/contracts/examples/fastlane-online/FastLaneOnlineInner.sol";

import { SwapIntent, BaselineCall } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

interface IGeneralizedBackrunProxy {
    function getUser() external view returns (address);
}

contract OuterHelpers is FastLaneOnlineInner {

    constructor(address _atlas) FastLaneOnlineInner(_atlas) { }

    /////////////////////////////////////////////////////////
    //              CONTROL-LOCAL FUNCTIONS                //
    //                 (not delegated)                     //
    /////////////////////////////////////////////////////////
    function getUserOperation(
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline, 
        uint256 gas,
        uint256 maxFeePerGas
    ) external view returns (UserOperation memory userOp) {
        userOp = _getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas);
    }

    function _getUserOperation(
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline, 
        uint256 gas,
        uint256 maxFeePerGas
    ) 
        internal 
        view 
        returns (UserOperation memory userOp) 
    {
        userOp = UserOperation({
            from: address(this),
            to: ATLAS,
            gas: gas,
            maxFeePerGas: maxFeePerGas,
            nonce: _getNextUserNonce(swapper),
            deadline: deadline,
            value: 0,
            dapp: CONTROL,
            control: CONTROL,
            callConfig: CALL_CONFIG,
            sessionKey: address(0),
            data: abi.encodeCall(this.swap, (swapper, swapIntent, baselineCall)),
            signature: new bytes(0)
        });
    }

    function _getUserOperationHash(UserOperation memory userOp) internal view returns (bytes32 userOpHash) {
        userOpHash = IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(userOp);
    }

    //////////////////////////////////////////////
    /////            GETTERS                //////
    //////////////////////////////////////////////
    function getUser() external view onlyAsControl returns (address) {
        address _user = _userLock;
        if (_user == address(1)) revert();
        return _user;
    }

    function getNextUserNonce(address owner) external view returns (uint256 nonce) {
        nonce = _getNextUserNonce(owner);
    }

    function _getNextUserNonce(address owner) internal view returns (uint256 nonce) {
        nonce = uint256(keccak256(abi.encode(S_userNonces[owner] + 1, owner)));
    }

    function _getAccessData(address solverFrom) internal view returns (EscrowAccountAccessData memory) {
        (uint112 _bonded, uint32 _lastAccessedBlock, uint24 _auctionWins, uint24 _auctionFails, uint64 _totalGasUsed) = IAtlas(ATLAS).accessData(solverFrom);
        return EscrowAccountAccessData({
            bonded: _bonded,
            lastAccessedBlock: _lastAccessedBlock,
            auctionWins: _auctionWins,
            auctionFails: _auctionFails,
            totalGasUsed: _totalGasUsed
        });
    }

    //////////////////////////////////////////////
    /////            MODIFIERS              //////
    //////////////////////////////////////////////
    modifier onlyAsControl() {
        if (address(this) != CONTROL) revert();
        _;
    }

}