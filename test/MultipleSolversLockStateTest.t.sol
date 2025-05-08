// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import {SolverBase} from "../src/contracts/solver/SolverBase.sol";
import {AtlasErrors} from "../src/contracts/types/AtlasErrors.sol";
import {DAppControl} from "../src/contracts/dapp/DAppControl.sol";
import {CallConfig} from "../src/contracts/types/ConfigTypes.sol";
import {SolverOperation} from "../src/contracts/types/SolverOperation.sol";
import {UserOperation} from "../src/contracts/types/UserOperation.sol";
import {DAppOperation} from "../src/contracts/types/DAppOperation.sol";
import {AtlasEvents} from "../src/contracts/types/AtlasEvents.sol";
import {SolverOutcome} from "../src/contracts/types/EscrowTypes.sol";
import {AtlasConstants} from "../src/contracts/types/AtlasConstants.sol";
import "../src/contracts/libraries/CallVerification.sol";
import "../src/contracts/interfaces/IAtlas.sol";

contract MultipleSolversLockStateTest is BaseTest, AtlasErrors, AtlasConstants {
    SolverLockDAppControl control;
    MockSolver solver1;
    MockSolver solver2;

    uint256 userOpSignerPK = 0x123456;
    address userOpSigner = vm.addr(userOpSignerPK);

    uint256 auctioneerPk = 0xabcdef;
    address auctioneer = vm.addr(auctioneerPk);

    uint256 bundlerPk = 0x123456;
    address bundler = vm.addr(bundlerPk);

    uint256 solverBidAmount = 1 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(governanceEOA);
        control = new SolverLockDAppControl(address(atlas));
        atlasVerification.initializeGovernance(address(control));
        atlasVerification.addSignatory(address(control), auctioneer);
        vm.stopPrank();

        vm.prank(solverOneEOA);
        solver1 = new MockSolver(address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver1), 10 * solverBidAmount);
        vm.prank(solverOneEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);

        vm.prank(solverTwoEOA);
        solver2 = new MockSolver(address(WETH_ADDRESS), address(atlas));
        vm.deal(address(solver2), 10 * solverBidAmount);
        vm.prank(solverTwoEOA);
        atlas.depositAndBond{value: 5 ether}(5 ether);
    }

    // Helper function to convert uint256 to binary string, focusing on relevant bits
    function toBinaryString(uint256 value) internal pure returns (string memory) {
        bytes memory binary = new bytes(256);
        for (uint i = 0; i < 256; i++) {
            binary[255 - i] = ((value & (1 << i)) != 0) ? bytes1("1") : bytes1("0");
        }
        return string(binary);
    }

    // Helper to print detailed lock state
    function printLockState(string memory label, uint256 lockValue) internal view {
        console.log("\n=== ", label, " ===");
        console.log("Raw value (decimal):", lockValue);
        console.log("Raw value (hex):", vm.toString(bytes32(lockValue)));
        
        // Print the binary representation in chunks for readability
        string memory binary = toBinaryString(lockValue);
        console.log("Binary representation:");
        console.log("Bits 256-193:", string(slice(binary, 0, 64)));
        console.log("Bits 192-129:", string(slice(binary, 64, 64)));
        console.log("Bits 128-65:", string(slice(binary, 128, 64)));
        console.log("Bits 64-1:", string(slice(binary, 192, 64)));
        
        // Print specific flag bits
        console.log("CALLED_BACK flag (bit 161):", (lockValue & _SOLVER_CALLED_BACK_MASK) != 0 ? "SET" : "NOT SET");
        console.log("FULFILLED flag (bit 162):", (lockValue & _SOLVER_FULFILLED_MASK) != 0 ? "SET" : "NOT SET");
        
        // Print the address portion
        console.log("Address portion (hex):", vm.toString(bytes20(uint160(lockValue))));
        
        // Print any unexpected bits
        uint256 expectedBits = uint256(uint160(type(uint160).max)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK;
        uint256 unexpectedBits = lockValue & ~expectedBits;
        if (unexpectedBits != 0) {
            console.log("!!! UNEXPECTED BITS FOUND !!!");
            console.log("Unexpected bits (hex):", vm.toString(bytes32(unexpectedBits)));
            console.log("Unexpected bits (binary):", toBinaryString(unexpectedBits));
        }
        console.log("==================\n");
    }

    // Helper to slice a string
    function slice(string memory str, uint256 start, uint256 length) internal pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(length);
        for(uint i = 0; i < length; i++) {
            result[i] = strBytes[i + start];
        }
        return result;
    }

    function test_multiple_solvers_lock_state() public {
        // Create UserOperation
        UserOperation memory userOp = UserOperation({
            from: userOpSigner,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: 1_000_000_000,
            nonce: 1,
            deadline: block.number + 100,
            dapp: address(control),
            control: address(control),
            callConfig: control.CALL_CONFIG(),
            dappGasLimit: 2_000_000,
            solverGasLimit: 1_000_000,
            bundlerSurchargeRate: 1_000,
            sessionKey: auctioneer,
            data: abi.encodeWithSelector(control.initiateAuction.selector),
            signature: new bytes(0)
        });
        Sig memory sig;
        (sig.v, sig.r, sig.s) = vm.sign(userOpSignerPK, atlasVerification.getUserOperationPayload(userOp));
        userOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Get execution environment and userOpHash
        (address executionEnvironment, ,) = IAtlas(address(atlas)).getExecutionEnvironment(userOpSigner, address(control));
        bytes32 userOpHash = atlasVerification.getUserOperationHash(userOp);

        // Create SolverOperations
        SolverOperation memory solverOp1 = SolverOperation({
            from: solverOneEOA,
            to: address(atlas),
            value: 0,
            gas: 1_000_000,
            maxFeePerGas: 1_000_000_000,
            deadline: block.number + 100,
            solver: address(solver1),
            control: address(control),
            userOpHash: userOpHash,
            bidToken: address(0),
            bidAmount: 0,
            data: abi.encodeWithSelector(solver1.solve.selector),
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(solverOnePK, atlasVerification.getSolverPayload(solverOp1));
        solverOp1.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation memory solverOp2 = SolverOperation({
            from: solverTwoEOA,
            to: address(atlas),
            value: 1 ether,
            gas: 1_000_000,
            maxFeePerGas: 1_000_000_000,
            deadline: block.number + 100,
            solver: address(solver2),
            control: address(control),
            userOpHash: userOpHash,
            bidToken: address(0),
            bidAmount: 1 ether,
            data: abi.encodeWithSelector(solver2.solve.selector),
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(solverTwoPK, atlasVerification.getSolverPayload(solverOp2));
        solverOp2.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        SolverOperation[] memory solverOps = new SolverOperation[](2);
        solverOps[0] = solverOp1;
        solverOps[1] = solverOp2;

        // Create DAppOperation
        bytes32 callChainHash = CallVerification.getCallChainHash(userOp, solverOps);
        DAppOperation memory dappOp = DAppOperation({
            from: auctioneer,
            to: address(atlas),
            nonce: 0,
            deadline: block.number + 100,
            control: address(control),
            bundler: bundler,
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });
        (sig.v, sig.r, sig.s) = vm.sign(auctioneerPk, atlasVerification.getDAppOperationPayload(dappOp));
        dappOp.signature = abi.encodePacked(sig.r, sig.s, sig.v);

        // Fund bundler and set gas price
        vm.deal(address(bundler), 2 ether);
        vm.txGasPrice(1 gwei);

        // Print initial state
        printLockState("Initial Lock State", atlas.getSolverLock());
        
        // Debug: Print solver addresses
        console.log("solverOneEOA:", solverOneEOA);
        console.log("solver1 address:", address(solver1));
        console.log("solverTwoEOA:", solverTwoEOA);
        console.log("solver2 address:", address(solver2));
        
        // Execute metacall
        vm.startPrank(bundler);
        vm.recordLogs();
        
        // Log state before metacall
        printLockState("Before metacall", atlas.getSolverLock());
        
        (bool success,) = address(atlas).call{gas: simulator.estimateMetacallGasLimit(userOp, solverOps)}(
            abi.encodeWithSelector(atlas.metacall.selector, userOp, solverOps, dappOp, address(0))
        );
        require(success, "metacall failed");
        
        // Log state immediately after metacall
        printLockState("After metacall", atlas.getSolverLock());
        
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Parse logs and print states
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("SolverTxResult(address,address,address,address,uint256,bool,bool,uint256)")) {
                address solverAddr = address(uint160(uint256(logs[i].topics[1])));
                
                if (solverAddr == address(solver1)) {
                    printLockState("After Solver1 Execution", atlas.getSolverLock());
                    assertEq(atlas.getSolverLock(), 
                        (uint256(uint160(solverTwoEOA)) | _SOLVER_CALLED_BACK_MASK | _SOLVER_FULFILLED_MASK),
                        "with multipleSuccessfulSolvers true, lock should show solver2's state");
                } else if (solverAddr == address(solver2)) {
                    printLockState("After Solver2 Execution", atlas.getSolverLock());
                }
            }
        }

        vm.stopPrank();
    }
}

contract SolverLockDAppControl is DAppControl {
    constructor(address atlas)
        DAppControl(
            atlas,
            msg.sender,
            CallConfig({
                userNoncesSequential: false,
                dappNoncesSequential: false,
                requirePreOps: true,
                trackPreOpsReturnData: false,
                trackUserReturnData: false,
                delegateUser: false,
                requirePreSolver: false,
                requirePostSolver: true,
                zeroSolvers: false, 
                reuseUserOp: false,
                userAuctioneer: false,
                solverAuctioneer: false,
                unknownAuctioneer: false,
                verifyCallChainHash: true,
                forwardReturnData: false,
                requireFulfillment: false,
                trustedOpHash: false,
                invertBidValue: false,
                exPostBids: false,
                multipleSuccessfulSolvers: true
            })
        )
    {}

    function initiateAuction() external {}

    function _preOpsCall(UserOperation calldata) internal override returns (bytes memory) {}

    function _postSolverCall(SolverOperation calldata, bytes calldata) internal override {}

    function _allocateValueCall(bool solved, address, uint256 bidAmount, bytes calldata) internal virtual override {
        require(!solved, "must be false when multipleSuccessfulSolvers is true");
    }

    function getBidFormat(UserOperation calldata) public pure override returns (address bidToken) {
        return address(0);
    }

    function getBidValue(SolverOperation calldata solverOp) public pure override returns (uint256) {
        return solverOp.bidAmount;
    }
}

contract MockSolver is SolverBase {
    constructor(address weth, address atlas) SolverBase(weth, atlas, msg.sender) {}
    
    function solve() external payable {
        // Mock successful solver execution
        console.log("MockSolver.solve() called");
    }
} 