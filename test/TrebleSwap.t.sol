// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { SolverOperation } from "src/contracts/types/SolverOperation.sol";
import { UserOperation } from "src/contracts/types/UserOperation.sol";
import { DAppConfig } from "src/contracts/types/ConfigTypes.sol";
import { DAppOperation } from "src/contracts/types/DAppOperation.sol";
import { CallVerification } from "src/contracts/libraries/CallVerification.sol";

import { SolverBase } from "src/contracts/solver/SolverBase.sol";

import { BaseTest } from "./base/BaseTest.t.sol";
import { TrebleSwapDAppControl } from "src/contracts/examples/trebleswap/TrebleSwapDAppControl.sol";

// TODO refactor this (and other tests) using multi-chain forking and User/Solver/Dapp Op builders

contract TrebleSwapTest is BaseTest {
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct SwapTokenInfo {
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 outputMin;
    }

    struct Args {
        UserOperation userOp;
        SolverOperation[] solverOps;
        DAppOperation dAppOp;
        uint256 blockBefore; // block before real tx happened
        bool nativeInput;
        bool nativeOutput;
    }

    struct BeforeAndAfterVars {
        uint256 userInputTokenBalance;
        uint256 userOutputTokenBalance;
        uint256 solverInputTokenBalance;
        uint256 solverOutputTokenBalance;
        uint256 burnAddressTrebBalance;
        uint256 atlasGasSurcharge;
    }

    // Base addresses
    address constant ODOS_ROUTER = 0x19cEeAd7105607Cd444F5ad10dd51356436095a1;
    address constant BURN = address(0xdead);
    address constant ETH = address(0);
    address constant bWETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WUF = 0x4da78059D97f155E18B37765e2e042270f4E0fC4;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address constant TREB = 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed;
    // TODO DEGEN for now, replace when TREB available

    uint256 bundlerGasEth = 1e16;

    TrebleSwapDAppControl trebleSwapControl;
    address executionEnvironment;

    Sig sig;
    Args args;
    SwapTokenInfo swapInfo;
    BeforeAndAfterVars beforeVars;

    function setUp() public virtual override {
        // Fork Base
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), 18_906_794);
        // TODO make this before all tx blocks in this file - atlas deployed before

        _BaseTest_DeployAtlasContracts();

        // TODO refactor how BaseTest handles forking chains and deploying Atlas.

        vm.startPrank(governanceEOA);
        trebleSwapControl = new TrebleSwapDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(trebleSwapControl));
        vm.stopPrank();

        vm.prank(userEOA);
        executionEnvironment = atlas.createExecutionEnvironment(userEOA, address(trebleSwapControl));

        // TODO refactor all this into base properly
        deal(userEOA, 1e18); // give user ETH for metacall msg.value for Atlas surcharge

        vm.label(bWETH, "WETH");
        vm.label(USDC, "USDC");
        vm.label(WUF, "WUF");
        vm.label(DAI, "DAI");
        vm.label(TREB, "DEGEN"); // TODO change label to TREB when TREB token available
    }

    // ---------------------------------------------------- //
    //                     Scenario Tests                   //
    // ---------------------------------------------------- //

    function testTrebleSwap_Metacall_Erc20ToErc20_ZeroSolvers() public {
        // Tx: https://basescan.org/tx/0x0ef4a9c24bbede2b39e12f5e5417733fa8183f372e41ee099c2c7523064c1b55
        // Swaps 197.2 USDC for at least 198,080,836.0295 WUF

        args.blockBefore = 18_906_794;
        args.nativeInput = false;
        args.nativeOutput = false;
        swapInfo = SwapTokenInfo({
            inputToken: USDC,
            inputAmount: 197_200_000,
            outputToken: WUF,
            outputMin: 1_980_808_360_295
        });
        vm.roll(args.blockBefore);

        // Modify swapCompact() calldata to replace original caller (0xa4a9220dE44D699f453DdF7F7630A96cDEdf6463) with
        // user's Execution Environment address:
        bytes memory calldataPart1 =
            hex"83bd37f9000400014da78059d97f155e18b37765e2e042270f4e0fc4040bc108800601d1d9f50a5a028f5c0001f73f77f9466da712590ae432a80f07fd50a7de600001616535324976f8dbcef19df0705b95ace86ebb480001";
        bytes memory calldataPart2 =
            hex"0000000006020207003401000001020180000005020a0004040500000301010003060119ff0000000000000000000000000000000000000000000000000000000000000000616535324976f8dbcef19df0705b95ace86ebb48833589fcd6edb6e08f4c7c32d4f71b54bda02913569d81c17b5b4ac08929dc1769b8e39668d3ae29f6c0a374a483101e04ef5f7ac9bd15d9142bac95d9aaec86b65d86f6a7b5b1b0c42ffa531710b6ca42000000000000000000000000000000000000060000000000000000";
        bytes memory swapCompactCalldata = abi.encodePacked(calldataPart1, executionEnvironment, calldataPart2);

        _checkActualCalldataMatchesExpected(swapCompactCalldata);
        _buildUserOp(swapCompactCalldata);
        // no solverOps
        _buildAndSignDAppOp();
        _setBalancesAndApprovals();
        _checkSimulationsPass();
        _doMetacallAndChecks({ winningSolverEOA: address(0), winningSolver: address(0) });
    }

    function testTrebleSwap_Metacall_EthToErc20_ZeroSolvers() public {
        // Tx: https://basescan.org/tx/0xe138def4155bea056936038b9374546a366828ab8bf1233056f9e2fe4c6af999
        // Swaps 0.123011147164483512 ETH for at least 307.405807527716546728 DAI

        args.blockBefore = 19_026_442;
        args.nativeInput = true;
        args.nativeOutput = false;
        swapInfo = SwapTokenInfo({
            inputToken: ETH,
            inputAmount: 123_011_147_164_483_512,
            outputToken: DAI,
            outputMin: 307_405_807_527_716_546_728
        });
        vm.roll(args.blockBefore);

        // Modify swapCompact() calldata to replace original caller (0xadF6918eD87a5D7aE334bB42Ca2d98971B527306) with
        // user's Execution Environment address:
        bytes memory calldataPart1 =
            hex"83bd37f9000000050801b505fc9226ffb80910d5345f06a9650000028f5c0001f73f77f9466da712590ae432a80f07fd50a7de6000000001";
        bytes memory calldataPart2 =
            hex"000000000401020500040101020a000202030100340101000104007ffffffaff00000000005fb33b095c6e739be19364ab408cd8f102262bb672ab388e2e2f6facef59e3c3fa2c4e29011c2d384200000000000000000000000000000000000006833589fcd6edb6e08f4c7c32d4f71b54bda0291300000000000000000000000000000000";
        bytes memory swapCompactCalldata = abi.encodePacked(calldataPart1, executionEnvironment, calldataPart2);

        _checkActualCalldataMatchesExpected(swapCompactCalldata);
        _buildUserOp(swapCompactCalldata);
        // no solverOps
        _buildAndSignDAppOp();
        _setBalancesAndApprovals();
        _checkSimulationsPass();
        _doMetacallAndChecks({ winningSolverEOA: address(0), winningSolver: address(0) });
    }

    // ---------------------------------------------------- //
    //                    Helper Functions                  //
    // ---------------------------------------------------- //

    function _doMetacallAndChecks(address winningSolverEOA, address winningSolver) internal {
        bool auctionWonExpected = winningSolver != address(0);
        beforeVars.userInputTokenBalance = _balanceOf(swapInfo.inputToken, userEOA);
        beforeVars.userOutputTokenBalance = _balanceOf(swapInfo.outputToken, userEOA);
        beforeVars.solverInputTokenBalance = _balanceOf(swapInfo.inputToken, winningSolverEOA);
        beforeVars.solverOutputTokenBalance = _balanceOf(swapInfo.outputToken, winningSolverEOA);
        beforeVars.burnAddressTrebBalance = _balanceOf(address(TREB), BURN);
        beforeVars.atlasGasSurcharge = atlas.cumulativeSurcharge();
        uint256 msgValue = (args.nativeInput ? swapInfo.inputAmount : 0) + bundlerGasEth;
        if (args.nativeInput) beforeVars.userInputTokenBalance -= bundlerGasEth;

        vm.prank(userEOA);
        bool auctionWon = atlas.metacall{ value: msgValue }(args.userOp, args.solverOps, args.dAppOp);

        assertEq(auctionWon, auctionWonExpected, "auctionWon not as expected");

        // user input token
        assertEq(
            _balanceOf(swapInfo.inputToken, userEOA),
            beforeVars.userInputTokenBalance - swapInfo.inputAmount,
            "wrong user input token balance change"
        );

        // user output token
        assertTrue(
            _balanceOf(swapInfo.outputToken, userEOA) >= beforeVars.userOutputTokenBalance + swapInfo.outputMin,
            "wrong user output token balance change"
        );
    }

    function _checkSimulationsPass() internal {
        // TODO do all variations of sim calls here with checks
    }

    function _checkActualCalldataMatchesExpected(bytes memory userOpData) internal {
        bytes memory encodedCall = abi.encodePacked(TrebleSwapDAppControl.decodeUserOpData.selector, userOpData);
        (bool res, bytes memory returnData) = address(trebleSwapControl).staticcall(encodedCall);
        assertEq(res, true, "calldata check failed in decode call");

        SwapTokenInfo memory decodedInfo = abi.decode(returnData, (SwapTokenInfo));
        assertEq(decodedInfo.inputToken, swapInfo.inputToken, "inputToken mismatch");
        assertEq(decodedInfo.inputAmount, swapInfo.inputAmount, "inputAmount mismatch");
        assertEq(decodedInfo.outputToken, swapInfo.outputToken, "outputToken mismatch");
        assertEq(decodedInfo.outputMin, swapInfo.outputMin, "outputMin mismatch");
    }

    function _setBalancesAndApprovals() internal {
        // User input token and Atlas approval
        if (args.nativeInput) {
            deal(userEOA, swapInfo.inputAmount + bundlerGasEth);
        } else {
            deal(userEOA, bundlerGasEth);
            deal(swapInfo.inputToken, userEOA, swapInfo.inputAmount);
            vm.prank(userEOA);
            IERC20(swapInfo.inputToken).approve(address(atlas), swapInfo.inputAmount);
        }

        // TODO give solver contracts TREB for bids
    }

    function _buildUserOp(bytes memory userOpData) internal {
        args.userOp = UserOperation({
            from: userEOA,
            to: address(atlas),
            value: args.nativeInput ? swapInfo.inputAmount : 0,
            gas: 1_000_000,
            maxFeePerGas: tx.gasprice,
            nonce: 1,
            deadline: args.blockBefore + 2,
            dapp: ODOS_ROUTER,
            control: address(trebleSwapControl),
            callConfig: trebleSwapControl.CALL_CONFIG(),
            sessionKey: address(0),
            data: userOpData,
            signature: new bytes(0)
        });
    }

    function _buildAndSignDAppOp() internal {
        args.dAppOp = DAppOperation({
            from: governanceEOA,
            to: address(atlas),
            nonce: 1,
            deadline: args.blockBefore + 2,
            control: address(trebleSwapControl),
            bundler: address(0),
            userOpHash: atlasVerification.getUserOperationHash(args.userOp),
            callChainHash: CallVerification.getCallChainHash(args.userOp, args.solverOps),
            signature: new bytes(0)
        });

        (sig.v, sig.r, sig.s) = vm.sign(governancePK, atlasVerification.getDAppOperationPayload(args.dAppOp));
        args.dAppOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == ETH) {
            return account.balance;
        } else {
            return IERC20(token).balanceOf(account);
        }
    }
}

interface IOdosRouterV2 {
    function swapCompact() external payable returns (uint256);
}
