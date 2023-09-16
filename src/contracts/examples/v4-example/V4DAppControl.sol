// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

// Base Imports
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

// Atlas Base Imports
import {ISafetyLocks} from "../../interfaces/ISafetyLocks.sol";
import {SafetyBits} from "../../libraries/SafetyBits.sol";

import "../../types/CallTypes.sol";
import "../../types/LockTypes.sol";

// Atlas DApp-Control Imports
import {DAppControl} from "../../dapp/DAppControl.sol";

// V4 Imports
import {IPoolManager} from "./IPoolManager.sol";
import {IHooks} from "./IHooks.sol";

contract V4DAppControl is DAppControl {
    struct PreOpsReturn {
        address approvedToken;
        IPoolManager.PoolKey poolKey;
    }

    struct PoolKey {
        bool initialized;
        IPoolManager.PoolKey key;
    }

    bytes4 public constant SWAP = IPoolManager.swap.selector;
    address public immutable hook;
    address public immutable v4Singleton;

    // Storage lock
    // keccak256(poolKey, executionEnvironment)
    bytes32 public hashLock; // TODO: Transient storage <-

    // Map to track when "Non Adversarial" flow is allowed.
    // NOTE: This hook is meant to be used for multiple pairs
    // key: keccak(token0, token1, block.number)
    mapping(bytes32 => bool) public sequenceLock;

    PoolKey internal _currentKey; // TODO: Transient storage <-

    constructor(address _escrow, address _v4Singleton)
        DAppControl(
            _escrow, 
            msg.sender, 
            CallConfig({
                sequenced: false,
                requirePreOps: true,
                trackPreOpsReturnData: true,
                trackUserReturnData: false,
                localUser: false,
                delegateUser: false,
                preSolver: false,
                postSolver: false,
                requirePostOps: false,
                zeroSolvers: true,
                reuseUserOp: false,
                userBundler: true,
                dAppBundler: true,
                unknownBundler: true
            })
        )
    {
        hook = address(this);
        v4Singleton = _v4Singleton;
    }

    /////////////////////////////////////////////////////////
    //                   ATLAS CALLS                       //
    /////////////////////////////////////////////////////////

    /////////////// DELEGATED CALLS //////////////////
    function _preOpsCall(UserCall calldata uCall)
        internal
        override
        returns (bytes memory preOpsData)
    {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Atlas Escrow


        require(!_currentKey.initialized, "ERR-H09 AlreadyInitialized");

        require(bytes4(uCall.data) == SWAP, "ERR-H10 InvalidFunction");

        require(uCall.to == v4Singleton, "ERR-H11 InvalidTo");

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that DAppControl supplied a valid signature
        require(msg.sender == escrow, "ERR-H00 InvalidCaller");


        (IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory params) =
            abi.decode(uCall.data[4:], (IPoolManager.PoolKey, IPoolManager.SwapParams));

        // Perform more checks and activate the lock
        V4DAppControl(hook).setLock(key);

        // Store the key so that we can access it at verification
        _currentKey = PoolKey({
            initialized: true, // TODO: consider using a lock array like v4 so we can handle multiple?
            key: key
        });

        // Handle forwarding of token approvals, or token transfers.
        // NOTE: The user will have approved the ExecutionEnvironment in a prior call
        PreOpsReturn memory preOpsReturn = PreOpsReturn({
            approvedToken: (
                params.zeroForOne
                    ? IPoolManager.Currency.unwrap(key.currency0)
                    : IPoolManager.Currency.unwrap(key.currency1)
                ),
            poolKey: key
        });

        // TODO: Determine if optimistic transfers are possible
        // (An example)
        if (params.zeroForOne) {
            if (params.amountSpecified > 0) {
                // Buying Pool's token1 with amountSpecified of User's token0
                // ERC20(token0).approve(v4Singleton, amountSpecified);
                SafeTransferLib.safeTransferFrom(
                    ERC20(IPoolManager.Currency.unwrap(key.currency0)),
                    uCall.from,
                    v4Singleton, // <- TODO: confirm
                    uint256(params.amountSpecified)
                );
            } else {
                // Buying amountSpecified of Pool's token1 with User's token0
            }
        } else {
            if (params.amountSpecified > 0) {
                // Buying Pool's token0 with amountSpecified of User's token1
            } else {
                // Buying amountSpecified of Pool's token0 with User's token1
            }
        }

        // Return value
        preOpsData = abi.encode(preOpsReturn);
    }

    // This occurs after a Solver has successfully paid their bid, which is
    // held in ExecutionEnvironment.
    function _allocatingCall(bytes calldata data) internal override {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        require(!_currentKey.initialized, "ERR-H09 AlreadyInitialized");
        
        // Pull the calldata into memory
        (, BidData[] memory bids) = abi.decode(data, (uint256, BidData[]));

        // NOTE: DAppVerification has verified the BidData[] format
        // BidData[0] = token0
        // BidData[1] = token1

        uint256 token0DonateAmount = bids[0].bidAmount;
        uint256 token1DonateAmount = bids[1].bidAmount;

        IPoolManager.PoolKey memory key = _currentKey.key;

        IPoolManager(v4Singleton).donate(key, token0DonateAmount, token1DonateAmount);

        // Flag the pool to be open for trading for the remainder of the block
        bytes32 sequenceKey = keccak256(
            abi.encodePacked(
                IPoolManager.Currency.unwrap(key.currency0), IPoolManager.Currency.unwrap(key.currency1), block.number
            )
        );

        sequenceLock[sequenceKey] = true;
    }

    function _postOpsCall(bytes calldata data) internal override returns (bool) {
        // This function is delegatecalled
        // address(this) = ExecutionEnvironment
        // msg.sender = Escrow

        (bytes memory returnData) = abi.decode(data, (bytes));

        PreOpsReturn memory preOpsReturn = abi.decode(returnData, (PreOpsReturn));

        V4DAppControl(hook).releaseLock(preOpsReturn.poolKey);

        delete _currentKey;

        return true;
    }

    /////////////// EXTERNAL CALLS //////////////////
    function setLock(IPoolManager.PoolKey memory key) external {
        // This function is a standard call
        // address(this) = hook
        // msg.sender = ExecutionEnvironment

        EscrowKey memory escrowKey = ISafetyLocks(escrow).getLockState();

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that DAppControl supplied a valid signature
        require(address(this) == hook, "ERR-H00 InvalidCallee");
        require(hook == escrowKey.approvedCaller, "ERR-H01 InvalidCaller");
        require(escrowKey.lockState == SafetyBits._LOCKED_X_STAGING_X_UNSET, "ERR-H02 InvalidLockStage");
        require(hashLock == bytes32(0), "ERR-H03 AlreadyActive");

        // Set the storage lock to block reentry / concurrent trading
        hashLock = keccak256(abi.encode(key, msg.sender));
    }

    function releaseLock(IPoolManager.PoolKey memory key) external {
        // This function is a standard call
        // address(this) = hook
        // msg.sender = ExecutionEnvironment

        EscrowKey memory escrowKey = ISafetyLocks(escrow).getLockState();

        // Verify that the swapper went through the FastLane Atlas MEV Auction
        // and that DAppControl supplied a valid signature
        require(address(this) == hook, "ERR-H20 InvalidCallee");
        require(hook == escrowKey.approvedCaller, "ERR-H21 InvalidCaller");
        require(escrowKey.lockState == SafetyBits._LOCKED_X_VERIFICATION_X_UNSET, "ERR-H22 InvalidLockStage");
        require(hashLock == keccak256(abi.encode(key, msg.sender)), "ERR-H23 InvalidKey");

        // Release the storage lock
        delete hashLock;
    }

    ///////////////// GETTERS & HELPERS // //////////////////
    function getPayeeData(bytes calldata data) external pure override returns (PayeeData[] memory) {
        // This function is called by the backend to get the
        // payee data, and by the Atlas Factory to generate a
        // hash to verify the backend.

        IPoolManager.PoolKey memory key = abi.decode(data, (IPoolManager.PoolKey));

        PaymentData[] memory payments = new PaymentData[](1);

        payments[0] = PaymentData({payee: address(key.hooks), payeePercent: 100});

        PayeeData[] memory payeeData = new PayeeData[](2);

        payeeData[0] = PayeeData({token: IPoolManager.Currency.unwrap(key.currency0), payments: payments, data: data});

        payeeData[1] = PayeeData({token: IPoolManager.Currency.unwrap(key.currency1), payments: payments, data: data});

        return payeeData;
    }

    function getBidFormat(UserCall calldata uCall) external pure override returns (BidData[] memory) {
        // This is a helper function called by solvers
        // so that they can get the proper format for
        // submitting their bids to the hook.

        (IPoolManager.PoolKey memory key,) =
            abi.decode(uCall.data, (IPoolManager.PoolKey, IPoolManager.SwapParams));

        BidData[] memory bidData = new BidData[](2);

        bidData[0] = BidData({
            token: IPoolManager.Currency.unwrap(key.currency0),
            bidAmount: 0 // <- solver must update
        });

        bidData[1] = BidData({
            token: IPoolManager.Currency.unwrap(key.currency1),
            bidAmount: 0 // <- solver must update
        });

        return bidData;
    }

    function getBidValue(SolverOperation calldata solverOp)
        external
        pure
        override
        returns (uint256) 
    {
        return solverOp.bids[0].bidAmount;
    }
}