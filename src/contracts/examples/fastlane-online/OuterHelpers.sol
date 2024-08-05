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
import { ISimulator } from "src/contracts/interfaces/ISimulator.sol";

import { FastLaneOnlineControl } from "src/contracts/examples/fastlane-online/FastLaneControl.sol";
import { FastLaneOnlineInner } from "src/contracts/examples/fastlane-online/FastLaneOnlineInner.sol";

import { SwapIntent, BaselineCall, Reputation } from "src/contracts/examples/fastlane-online/FastLaneTypes.sol";

contract OuterHelpers is FastLaneOnlineInner {
    // NOTE: Any funds collected in excess of the therapy bills required for the Cardano engineering team
    // will go towards buying stealth drones programmed to apply deodorant to coders at solana hackathons.
    address public immutable CARDANO_ENGINEER_THERAPY_FUND;

    // Simulator
    address public immutable SIMULATOR;

    constructor(address _atlas, address _simulator) FastLaneOnlineInner(_atlas) {
        CARDANO_ENGINEER_THERAPY_FUND = msg.sender;
        SIMULATOR = _simulator;
    }

    /////////////////////////////////////////////////////////
    //              CONTROL-LOCAL FUNCTIONS                //
    //                 (not delegated)                     //
    /////////////////////////////////////////////////////////
    function getUserOperationAndHash(
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas
    )
        external
        view
        returns (UserOperation memory userOp, bytes32 userOpHash)
    {
        userOp = _getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas);
        userOpHash = _getUserOperationHash(userOp);
    }

    function getUserOpHash(
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas
    )
        external
        view
        returns (bytes32 userOpHash)
    {
        userOpHash =
            _getUserOperationHash(_getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas));
    }

    function getUserOperation(
        address swapper,
        SwapIntent calldata swapIntent,
        BaselineCall calldata baselineCall,
        uint256 deadline,
        uint256 gas,
        uint256 maxFeePerGas
    )
        external
        view
        returns (UserOperation memory userOp)
    {
        userOp = _getUserOperation(swapper, swapIntent, baselineCall, deadline, gas, maxFeePerGas);
    }

    function makeThogardsWifeHappy() external onlyAsControl withUserLock(msg.sender) {
        require(msg.sender == CARDANO_ENGINEER_THERAPY_FUND, "ERR - NOT MAD JUST DISAPPOINTED");
        uint256 _rake = rake;
        rake = 0;
        SafeTransferLib.safeTransferETH(CARDANO_ENGINEER_THERAPY_FUND, _rake);
    }

    function _simulateSolverOp(
        UserOperation calldata userOp,
        SolverOperation calldata solverOp
    )
        internal
        returns (bool valid)
    {
        DAppOperation memory _dAppOp = _getDAppOp(solverOp.userOpHash, userOp.deadline);

        // NOTE: Valid is false when the solver fails even if postOps is successful
        (valid,,) = ISimulator(SIMULATOR).simSolverCall(userOp, solverOp, _dAppOp);
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
            data: abi.encodeCall(this.swap, (swapIntent, baselineCall)),
            signature: new bytes(0) // User must sign
         });
    }

    function _getUserOperationHash(UserOperation memory userOp) internal view returns (bytes32 userOpHash) {
        userOpHash = IAtlasVerification(ATLAS_VERIFICATION).getUserOperationHash(userOp);
    }

    function _getDAppOp(bytes32 userOpHash, uint256 deadline) internal view returns (DAppOperation memory dAppOp) {
        dAppOp = DAppOperation({
            from: CONTROL, // signer of the DAppOperation
            to: ATLAS, // Atlas address
            nonce: 0, // Atlas nonce of the DAppOperation available in the AtlasVerification contract
            deadline: deadline, // block.number deadline for the DAppOperation
            control: CONTROL, // DAppControl address
            bundler: CONTROL, // Signer of the atlas tx (msg.sender)
            userOpHash: userOpHash, // keccak256 of userOp.to, userOp.data
            callChainHash: bytes32(0), // keccak256 of the solvers' txs
            signature: new bytes(0) // DAppOperation signed by DAppOperation.from
         });
    }

    function _processCongestionRake(
        uint256 startingBalance,
        bytes32 userOpHash,
        bool solversSuccessful
    )
        internal
        returns (uint256 netGasRefund)
    {
        uint256 _grossGasRefund = address(this).balance - startingBalance;

        uint256 _congestionBuyIns = S_aggCongestionBuyIn[userOpHash];

        if (_congestionBuyIns > 0) {
            if (solversSuccessful) {
                _grossGasRefund += _congestionBuyIns;
            }
            delete S_aggCongestionBuyIn[userOpHash];
        }

        uint256 _netRake = _grossGasRefund * _CONGESTION_RAKE / _CONGESTION_BASE;

        // Increment cumulative rake
        if (solversSuccessful) {
            rake += _netRake;
        } else {
            // NOTE: We do not refund the congestion buyins to the user because we do not want to create a
            // scenario in which the user can profit from Solvers failing. We also shouldn't give these to the
            // validator for the same reason.
            // TODO: _congestionBuyIns to protocol guild or something because contract authors should be credibly
            // neutral too
            rake += (_netRake + _congestionBuyIns);
        }

        // Return the netGasRefund
        netGasRefund = _grossGasRefund - _netRake;
    }

    function _sortSolverOps(SolverOperation[] memory unsortedSolverOps)
        internal
        view
        returns (SolverOperation[] memory sortedSolverOps)
    {
        // This could be made more gas efficient

        uint256 _length = unsortedSolverOps.length;
        if (_length == 0) {
            return unsortedSolverOps;
        }

        sortedSolverOps = new SolverOperation[](_length);

        uint256 _topBidAmount;
        uint256 _topBidIndex;
        bool _matched;

        for (uint256 i; i < _length; i++) {
            _topBidAmount = 0;
            _topBidIndex = 0;
            _matched = false;

            for (uint256 j; j < _length; j++) {
                uint256 _bidAmount = unsortedSolverOps[j].bidAmount;

                if (_bidAmount >= _topBidAmount && _bidAmount != 0) {
                    _topBidAmount = _bidAmount;
                    _topBidIndex = j;
                    _matched = true;
                }
            }

            if (_matched) {
                // Get the highest solverOp and add it to sorted array
                SolverOperation memory _solverOp = unsortedSolverOps[_topBidIndex];
                sortedSolverOps[i] = _solverOp;

                // Mark it as sorted in old array
                unsortedSolverOps[_topBidIndex].bidAmount = 0;
            }
        }

        return sortedSolverOps;
    }

    function _updateSolverReputation(
        SolverOperation[] memory solverOps,
        uint128 magnitude,
        bool solversSuccessful
    )
        internal
    {
        uint256 _length = solverOps.length;
        for (uint256 i; i < _length; i++) {
            if (solversSuccessful) {
                S_solverReputations[solverOps[i].from].successCost += magnitude;
            } else {
                S_solverReputations[solverOps[i].from].failureCost += magnitude;
            }
        }
    }

    //////////////////////////////////////////////
    /////            GETTERS                //////
    //////////////////////////////////////////////
    function _getNextUserNonce(address owner) internal view returns (uint256 nonce) {
        nonce = IAtlasVerification(ATLAS).getUserNextNonce(owner, false);
    }

    function isUserNonceValid(address owner, uint256 nonce) external view returns (bool valid) {
        valid = _isUserNonceValid(owner, nonce);
    }

    function _isUserNonceValid(address owner, uint256 nonce) internal view returns (bool valid) {
        uint248 _wordIndex = uint248(nonce >> 8);
        uint8 _bitPos = uint8(nonce);
        uint256 _bitmap = IAtlasVerification(ATLAS).userNonSequentialNonceTrackers(owner, _wordIndex);
        valid = _bitmap & 1 << _bitPos != 1;
    }

    function _getAccessData(address solverFrom) internal view returns (EscrowAccountAccessData memory) {
        (uint112 _bonded, uint32 _lastAccessedBlock, uint24 _auctionWins, uint24 _auctionFails, uint64 _totalGasUsed) =
            IAtlas(ATLAS).accessData(solverFrom);
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
