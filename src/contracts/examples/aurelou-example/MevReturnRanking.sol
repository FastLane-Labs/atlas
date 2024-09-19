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

// Uniswap Imports
import {
    IUniswapV2Router01,
    IUniswapV2Router02
} from "src/contracts/examples/aurelou-example/interfaces/IUniswapV2Router.sol";

import { IMevReturnRanking } from "src/contracts/examples/aurelou-example/interfaces/IMevReturnRanking.sol";

/*
* @title CombinedDAppControl
* @notice This contract combines functionalities of V2RewardDAppControl and Ranking
* @dev This contract inherits from DAppControl and implements both reward and ranking systems
*/
contract CombinedDAppControl is DAppControl {
    address public immutable REWARD_TOKEN;
    address public immutable uniswapV2Router02;

    //   Selector   Boolean
    mapping(bytes4 => bool) public ERC20StartingSelectors;
    //   Selector   Boolean
    mapping(bytes4 => bool) public ETHStartingSelectors;
    //   Selector   Boolean
    mapping(bytes4 => bool) public exactINSelectors;

    event TokensRewarded(address indexed user, address indexed token, uint256 amount);

    // Ranking variables
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

    constructor(
        address _atlas,
        address _rewardToken,
        address _uniswapV2Router02
    )
        DAppControl(
            _atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: true,
                trackUserReturnData: true,
                delegateUser: true,
                requirePreSolver: false,
                requirePostSolver: false,
                requirePostOps: true,
                zeroSolvers: true,
                reuseUserOp: true,
                userAuctioneer: true,
                solverAuctioneer: false,
                unknownAuctioneer: true,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: true,
                invertBidValue: false,
                exPostBids: true,
                allowAllocateValueFailure: true
            })
        )
    {
        REWARD_TOKEN = _rewardToken;
        uniswapV2Router02 = _uniswapV2Router02;

        ERC20StartingSelectors[bytes4(IUniswapV2Router01.swapExactTokensForTokens.selector)] = true;
        ERC20StartingSelectors[bytes4(IUniswapV2Router01.swapTokensForExactTokens.selector)] = true;
        ERC20StartingSelectors[bytes4(IUniswapV2Router01.swapTokensForExactETH.selector)] = true;
        ERC20StartingSelectors[bytes4(IUniswapV2Router01.swapExactTokensForETH.selector)] = true;
        ERC20StartingSelectors[bytes4(IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector)]
        = true;
        ERC20StartingSelectors[bytes4(IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector)] =
            true;

        ETHStartingSelectors[bytes4(IUniswapV2Router01.swapExactETHForTokens.selector)] = true;
        ETHStartingSelectors[bytes4(IUniswapV2Router01.swapETHForExactTokens.selector)] = true;
        ETHStartingSelectors[bytes4(IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector)] =
            true;

        exactINSelectors[bytes4(IUniswapV2Router01.swapExactTokensForTokens.selector)] = true;
        exactINSelectors[bytes4(IUniswapV2Router01.swapExactTokensForETH.selector)] = true;
        exactINSelectors[bytes4(IUniswapV2Router02.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector)] =
            true;
        exactINSelectors[bytes4(IUniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens.selector)] = true;
        exactINSelectors[bytes4(IUniswapV2Router01.swapExactETHForTokens.selector)] = true;
        exactINSelectors[bytes4(IUniswapV2Router02.swapExactETHForTokensSupportingFeeOnTransferTokens.selector)] = true;
    }

    // V2RewardDAppControl functions
    function getTokenSold(bytes calldata userData) external view returns (address tokenSold, uint256 amountSold) {
        bytes4 funcSelector = bytes4(userData);

        require(
            ERC20StartingSelectors[funcSelector] || ETHStartingSelectors[funcSelector],
            "CombinedDAppControl: InvalidFunction"
        );

        if (ERC20StartingSelectors[funcSelector]) {
            address[] memory path;

            if (exactINSelectors[funcSelector]) {
                (amountSold,, path,,) = abi.decode(userData[4:], (uint256, uint256, address[], address, uint256));
            } else {
                (, amountSold, path,,) = abi.decode(userData[4:], (uint256, uint256, address[], address, uint256));
            }

            tokenSold = path[0];
        }
    }

    function _checkUserOperation(UserOperation memory userOp) internal view override {
        require(userOp.dapp == uniswapV2Router02, "CombinedDAppControl: InvalidDestination");
    }

    function _preOpsCall(UserOperation calldata userOp) internal override returns (bytes memory) {
        (address tokenSold, uint256 amountSold) = this.getTokenSold(userOp.data);

        _getAndApproveUserERC20(tokenSold, amountSold, uniswapV2Router02);

        return abi.encode(tokenSold);
    }

    function _allocateValueCall(address bidToken, uint256 bidAmount, bytes calldata) internal override {
        require(bidToken == REWARD_TOKEN, "CombinedDAppControl: InvalidBidToken");

        address user = _user();

        if (bidToken == address(0)) {
            SafeTransferLib.safeTransferETH(user, bidAmount);
        } else {
            SafeTransferLib.safeTransfer(REWARD_TOKEN, user, bidAmount);
        }

        emit TokensRewarded(user, REWARD_TOKEN, bidAmount);
    }

    function _postOpsCall(bool, bytes calldata data) internal override {
        address tokenSold = abi.decode(data, (address));
        uint256 balance;

        if (tokenSold == address(0)) {
            balance = address(this).balance;
            if (balance > 0) {
                SafeTransferLib.safeTransferETH(_user(), balance);
            }
        } else {
            balance = IERC20(tokenSold).balanceOf(address(this));
            if (balance > 0) {
                SafeTransferLib.safeTransfer(tokenSold, _user(), balance);
            }
        }
    }

    // Ranking functions
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

    // Modifiers from Ranking
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

    // Additional functions from Ranking
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

    // Getters and helpers from V2RewardDAppControl
    function getBidFormat(UserOperation calldata) public view override returns (address bidToken) {
        return REWARD_TOKEN;
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}
