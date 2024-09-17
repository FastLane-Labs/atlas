//SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { DAppControl } from "src/contracts/dapp/DAppControl.sol";
import { CallConfig } from "src/contracts/types/ConfigTypes.sol";
import { IMevReturnRanking } from "src/contracts/examples/aurelou-example/IMevReturnRanking.sol";
import "src/contracts/types/UserOperation.sol";
import "src/contracts/types/SolverOperation.sol";

/// @title MevReturnRanking
/// @notice This contract is a ranking of the best MEV return solvers.
/// @dev This contract is a ranking of the best MEV return solvers.
/// @author 0xAurelou
contract Ranking is DAppControl {
    address private _userLock = address(1); // TODO: Convert to transient storage

    uint256 private constant _FEE_BASE = 100;

    //      USER                TOKEN       AMOUNT
    mapping(address => mapping(address => uint256)) internal s_deposits;

    //   SolverOpHash   SolverOperation
    mapping(bytes32 => SolverOperation) public S_solverOpCache;

    //      UserOpHash  SolverOpHash[]
    mapping(bytes32 => bytes32[]) public S_solverOpHashes;

    //      USER        POINTS
    mapping(address => uint256) public S_userPointBalances;

    constructor(address _atlas)
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: false,
                trackPreOpsReturnData: false,
                trackUserReturnData: true,
                delegateUser: true,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: false,
                zeroSolvers: true,
                reuseUserOp: true,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: true,
                invertBidValue: false,
                exPostBids: false,
                allowAllocateValueFailure: true
            })
        )
    { }

    function getUserRanking(address user) external view returns (IMevReturnRanking.RankingType) {
        uint256 points = S_userPointBalances[user];
        if (points == 0) {
            return IMevReturnRanking.RankingType.LOW;
        } else if (points < 100) {
            return IMevReturnRanking.RankingType.MEDIUM;
        } else {
            return IMevReturnRanking.RankingType.HIGH;
        }
    }

    // ---------------------------------------------------- //
    //                       Custom                         //
    // ---------------------------------------------------- //

    /////////////////////////////////////////////////////////
    //              CONTROL FUNCTIONS                      //
    //                 (not delegated)                     //
    /////////////////////////////////////////////////////////

    modifier onlyAsControl() {
        if (address(this) != CONTROL) revert();
        _;
    }

    modifier withUserLock(address user) {
        if (_userLock != address(1)) revert();
        _userLock = user;
        _;
        _userLock = address(1);
    }

    modifier onlyWhenUnlocked() {
        if (_userLock != address(1)) revert();
        _;
    }

    function getUser() external view onlyAsControl returns (address) {
        address _user = _userLock;
        if (_user == address(1)) revert();
        return _user;
    }

    function addSolverOp(SolverOperation calldata solverOp) external onlyAsControl {
        if (msg.sender != solverOp.from) revert();

        bytes32 _solverOpHash = keccak256(abi.encode(solverOp));

        S_solverOpCache[_solverOpHash] = solverOp;
        S_solverOpHashes[solverOp.userOpHash].push(_solverOpHash);
    }

    function _getSolverOps(bytes32[] calldata solverOpHashes)
        internal
        view
        returns (SolverOperation[] memory solverOps)
    {
        uint256 solverHashLength = solverOpHashes.length;
        solverOps = new SolverOperation[](solverHashLength);

        uint256 _j;
        for (uint256 i; i < solverHashLength;) {
            SolverOperation memory _solverOp = S_solverOpCache[solverOpHashes[i]];
            if (_solverOp.from != address(0)) {
                solverOps[_j++] = _solverOp;
            }
            unchecked {
                ++i;
            }
        }
    }
}
