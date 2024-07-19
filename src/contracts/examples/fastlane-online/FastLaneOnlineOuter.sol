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

contract FastLaneOnlineOuter is FastLaneOnlineInner {

    uint256 private constant _maxSolversPerTx = 16;

    address private _userLock = address(1); // TODO: Convert to transient storage

    //   SolverOpHash   SolverOperation
    mapping(bytes32 => SolverOperation) public S_solverOpCache;

    //      UserOpHash  SolverOpHash[]
    mapping(bytes32 => bytes32[]) public S_solverOpHashes;

    //      User        Nonce
    mapping(address => uint256) public S_userNonces;

    constructor(address _atlas) FastLaneOnlineInner(_atlas) { }

    /////////////////////////////////////////////////////////
    //              CONTROL-LOCAL FUNCTIONS                //
    //                 (not delegated)                     //
    /////////////////////////////////////////////////////////
    function addSolverOp(SolverOperation calldata solverOp) external onlyAsControl onlyWhenUnlocked {
        if (msg.sender != solverOp.from) revert();
        if (solverOp.from == address(0)) revert();

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        S_solverOpCache[_solverOpHash] = solverOp;
        S_solverOpHashes[solverOp.userOpHash].push(_solverOpHash);
    }

    function _getSolverOps(bytes32 userOpHash) internal view returns (SolverOperation[] memory solverOps) {
        solverOps = new SolverOperation[](_maxSolversPerTx);

        uint256 _cumulativeSolverGas = 500_000; // start at buffer

        for (uint256 _i; _i < _maxSolversPerTx; _i++) {
            bytes32 _solverOpHash = S_solverOpHashes[userOpHash][_i];
            SolverOperation memory _solverOp = S_solverOpCache[_solverOpHash];
            if (_solverOp.from == address(0)) {
                break;
                // NOTE address() solverOp.from is checked at addSolverOp
            }

            // NOTE double the SolverOp gas because this is ex post bids.
            if (_cumulativeSolverGas + (_solverOp.gas * 2) + 100_000 > gasleft()) {
                break;
            }

            solverOps[_i] = _solverOp;
            _cumulativeSolverGas += _solverOp.gas;
        }
    }

    //////////////////////////////////////////////
    // THIS IS WHAT THE USER INTERACTS THROUGH.
    //////////////////////////////////////////////
    function fastOnlineSwap(UserOperation calldata userOp) external payable withUserLock onlyAsControl {
        _validateUserOp(userOp);

        (address _swapper, SwapIntent memory _swapIntent,) =
            abi.decode(userOp.data[4:], (address, SwapIntent, BaselineCall));

        // Verify that user is caller (userOp.from is this address - this contract spoofs the user)
        require(_swapper == msg.sender, "ERR - USER NOT SENDER");

        // Transfer the user's sell tokens to here and then approve Atlas for that amount.
        SafeTransferLib.safeTransferFrom(
            _swapIntent.tokenUserSells, _swapper, address(this), _swapIntent.amountUserSells
        );
        SafeTransferLib.safeApprove(_swapIntent.tokenUserSells, ATLAS, _swapIntent.amountUserSells);

        // Get any SolverOperations
        bytes32 _userOpHash = IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(userOp);

        // Get the SolverOperations
        SolverOperation[] memory _solverOps = _getSolverOps(_userOpHash);

        // Build DAppOp
        DAppOperation memory _dAppOp = DAppOperation({
            from: address(this), // signer of the DAppOperation
            to: ATLAS, // Atlas address
            nonce: 0, // Atlas nonce of the DAppOperation available in the AtlasVerification contract
            deadline: userOp.deadline, // block.number deadline for the DAppOperation
            control: address(this), // DAppControl address
            bundler: address(this), // Signer of the atlas tx (msg.sender)
            userOpHash: _userOpHash, // keccak256 of userOp.to, userOp.data
            callChainHash: bytes32(0), // keccak256 of the solvers' txs
            signature: new bytes(0) // DAppOperation signed by DAppOperation.from
         });

        // Metacall
        (bool _success, bytes memory _data) =
            ATLAS.call{ value: msg.value }(abi.encodeCall(IAtlas.metacall, (userOp, _solverOps, _dAppOp)));
        if (!_success) {
            assembly {
                revert(add(_data, 32), mload(_data))
            }
        }

        // Revert the token approval
        SafeTransferLib.safeApprove(_swapIntent.tokenUserSells, ATLAS, 0);
    }

    /////
    // TODO: If there are no Solvers, go ahead and just do the swap here and skip Atlas.
    ////

    //////////////////////////////////////////////
    /////            GETTERS                //////
    //////////////////////////////////////////////
    function getUser() external view onlyAsControl returns (address) {
        address _user = _userLock;
        if (_user == address(1)) revert();
        return _user;
    }

    function getNextUserNonce(address owner) external view returns (uint256 nonce) {
        nonce = uint256(keccak256(abi.encode(S_userNonces[owner] + 1, owner)));
    }

    function _validateUserOp(UserOperation calldata userOp) internal {
        require(address(this) == userOp.from, "ERR - INVALID FROM"); // This contract acts as both User and Control
        require(userOp.to == ATLAS, "ERR - MUST BE TO ATLAS");
        require(
            userOp.nonce == uint256(keccak256(abi.encode(++S_userNonces[msg.sender], msg.sender))), "ERR - INVALID NONCE"
        );
        require(tx.gasprice <= userOp.maxFeePerGas, "ERR - INVALID GASPRICE");
        require(userOp.dapp == CONTROL, "ERR - INVALID DAPP");
        require(userOp.control == address(this), "ERR - INVALID CONTROL");
        require(userOp.deadline >= block.number, "ERR - DEADLINE PASSED");
        require(userOp.callConfig == CALL_CONFIG, "ERR - INVALID CONFIG");
    }

    //////////////////////////////////////////////
    /////            MODIFIERS              //////
    //////////////////////////////////////////////
    modifier onlyAsControl() {
        if (address(this) != CONTROL) revert();
        _;
    }

    modifier withUserLock() {
        if (_userLock != address(1)) revert();
        _userLock = msg.sender;
        _;
        _userLock = address(1);
    }

    modifier onlyWhenUnlocked() {
        if (_userLock != address(1)) revert();
        _;
    }
}
