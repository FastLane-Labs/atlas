// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { GasAccLib, GasLedger, BorrowsLedger } from "../src/contracts/libraries/GasAccLib.sol";
import { AccountingMath } from "../src/contracts/libraries/AccountingMath.sol";
import { SolverOperation } from "../src/contracts/types/SolverOperation.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

contract GasAccLibTest is Test {
    using SafeCast for uint128;
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;
    using GasAccLib for uint256;
    using AccountingMath for uint256;

    MockL2GasCalculator mockL2GasCalc;
    MemoryToCalldataHelper memoryToCalldataHelper;

    function setUp() public {
        mockL2GasCalc = new MockL2GasCalculator();
        memoryToCalldataHelper = new MemoryToCalldataHelper();
    }

    function test_GasAccLib_GasLedger_packAndUnpack() public pure {
        GasLedger memory before = GasLedger({
            remainingMaxGas: 1,
            writeoffsGas: 2,
            solverFaultFailureGas: 3,
            unreachedSolverGas: 4,
            maxApprovedGasSpend: 5
        });

        uint256 packed = before.pack();
        GasLedger memory unpacked = packed.toGasLedger();

        assertEq(unpacked.remainingMaxGas, before.remainingMaxGas, "remainingMaxGas mismatch");
        assertEq(unpacked.writeoffsGas, before.writeoffsGas, "writeoffsGas mismatch");
        assertEq(unpacked.solverFaultFailureGas, before.solverFaultFailureGas, "solverFaultFailureGas mismatch");
        assertEq(unpacked.unreachedSolverGas, before.unreachedSolverGas, "unreachedSolverGas mismatch");
        assertEq(unpacked.maxApprovedGasSpend, before.maxApprovedGasSpend, "maxApprovedGasSpend mismatch");
    }

    function test_GasAccLib_BorrowsLedger_packAndUnpack() public pure {
        BorrowsLedger memory before = BorrowsLedger({
            borrows: 12345,
            repays: 987654
        });

        uint256 packed = before.pack();
        BorrowsLedger memory unpacked = packed.toBorrowsLedger();

        assertEq(unpacked.borrows, before.borrows, "borrows mismatch");
        assertEq(unpacked.repays, before.repays, "repays mismatch");
    }

    function test_GasAccLib_netRepayments() public pure {
        BorrowsLedger memory bL = BorrowsLedger({
            borrows: 100,
            repays: 50
        });

        assertEq(bL.netRepayments(), bL.repays.toInt256() - bL.borrows.toInt256(), "netRepayments unexpected");
        assertTrue(bL.netRepayments() < 0, "netRepayments should be negative");

        bL.repays = 200;

        assertEq(bL.netRepayments(), bL.repays.toInt256() - bL.borrows.toInt256(), "netRepayments unexpected");
        assertTrue(bL.netRepayments() > 0, "netRepayments should be positive");
    }

    function test_GasAccLib_solverGasLiability() public {
        uint256 totalSurchargeRate = 20_000_000; // 200%

        GasLedger memory gL = GasLedger({
            remainingMaxGas: 10_000,
            writeoffsGas: 0,
            solverFaultFailureGas: 0,
            unreachedSolverGas: 5_000,
            maxApprovedGasSpend: 0
        });

        vm.txGasPrice(5);

        // Should be: (10_000 - 5_000) * (100% + 200%) * 5 = 5000 * 3 * 5 = 75_000
        uint256 expected = uint256(gL.remainingMaxGas - gL.unreachedSolverGas).withSurcharge(totalSurchargeRate) * tx.gasprice;
        assertEq(gL.solverGasLiability(totalSurchargeRate), expected, "solverGasLiability unexpected");
    }

    function test_GasAccLib_solverOpCalldataGas() public view {
        uint256 calldataLength = 500;

        // First, the default calculation, using address(0) as the GasCalculator:
        uint256 expectedDefaultGas = (calldataLength + GasAccLib._SOLVER_OP_BASE_CALLDATA) * GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED;

        assertEq(GasAccLib.solverOpCalldataGas(calldataLength, address(0)), expectedDefaultGas, "solverOpCalldataGas (default) unexpected");

        // Now, with a mock L2GasCalculator, that returns 5x the default calldata gas:
        uint256 expectedMockGas = 5 * expectedDefaultGas;

        assertEq(GasAccLib.solverOpCalldataGas(calldataLength, address(mockL2GasCalc)), expectedMockGas, "solverOpCalldataGas (5x mock) unexpected");
    }

    function test_GasAccLib_sumSolverOpsCalldataGas() public view {
        SolverOperation[] memory solverOps = new SolverOperation[](3);
        solverOps[0].data = new bytes(100);
        solverOps[1].data = new bytes(200);
        solverOps[2].data = new bytes(500);

        // First, the default calculation, using address(0) as the GasCalculator:
        uint256 expectedDefaultGas = ((solverOps.length * GasAccLib._SOLVER_OP_BASE_CALLDATA) + 100 + 200 + 500) * GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED;

        assertEq(memoryToCalldataHelper.sumSolverOpsCalldataGas(solverOps, address(0)), expectedDefaultGas, "sumSolverOpsCalldataGas (default) unexpected");

        // Now, with a mock L2GasCalculator, that returns 5x the default calldata gas:
        uint256 expectedMockGas = 5 * expectedDefaultGas;

        assertEq(memoryToCalldataHelper.sumSolverOpsCalldataGas(solverOps, address(mockL2GasCalc)), expectedMockGas, "sumSolverOpsCalldataGas (5x mock) unexpected");
    }

    function test_GasAccLib_metacallCalldataGas() public view {
        uint256 msgDataLength = 3_000;

        // First, the default calculation, using address(0) as the GasCalculator:
        uint256 expectedDefaultGas = msgDataLength * GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED;

        assertEq(GasAccLib.metacallCalldataGas(msgDataLength, address(0)), expectedDefaultGas, "metacallCalldataGas (default) unexpected");

        // Now, with a mock L2GasCalculator, that returns 5x the default calldata gas:
        uint256 expectedMockGas = 5 * expectedDefaultGas;

        assertEq(GasAccLib.metacallCalldataGas(msgDataLength, address(mockL2GasCalc)), expectedMockGas, "metacallCalldataGas (5x mock) unexpected");
    }
}

contract MockL2GasCalculator {
    // Should return 5x the default calldata gas
    function getCalldataGas(uint256 calldataLength) external view returns (uint256 calldataGas) {
        return calldataLength * GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED * 5;
    }

    function initialGasUsed(uint256 calldataLength) external view returns (uint256 gasUsed) {
        return calldataLength * GasAccLib._CALLDATA_LENGTH_PREMIUM_HALVED * 5;
    }
}

// Basic helper to convert the SolverOperations[] memory to calldata for testing
contract MemoryToCalldataHelper {
    function sumSolverOpsCalldataGas(
        SolverOperation[] calldata solverOps,
        address l2GasCalculator
    )
        public
        view
        returns (uint256 sumCalldataGas)
    {
        return GasAccLib.sumSolverOpsCalldataGas(solverOps, l2GasCalculator);
    }
}