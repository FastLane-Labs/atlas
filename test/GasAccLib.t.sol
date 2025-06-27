// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { GasAccLib, GasLedger, BorrowsLedger } from "../src/contracts/libraries/GasAccLib.sol";
import { AccountingMath } from "../src/contracts/libraries/AccountingMath.sol";
import { SolverOperation } from "../src/contracts/types/SolverOperation.sol";

import { MockL2GasCalculator } from "./base/MockL2GasCalculator.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

contract GasAccLibTest is Test {
    using SafeCast for uint128;
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;
    using GasAccLib for uint256;
    using AccountingMath for uint256;

    MockL2GasCalculator mockL2GasCalc;

    function setUp() public {
        mockL2GasCalc = new MockL2GasCalculator();
    }

    function test_GasAccLib_GasLedger_packAndUnpack() public pure {
        GasLedger memory before = GasLedger({
            remainingMaxGas: 1,
            writeoffsGas: 2,
            solverFaultFailureGas: 3,
            unreachedSolverGas: 4,
            maxApprovedGasSpend: 5,
            atlasSurchargeRate: 6,
            bundlerSurchargeRate: 7
        });

        uint256 packed = before.pack();
        GasLedger memory unpacked = packed.toGasLedger();

        assertEq(unpacked.remainingMaxGas, before.remainingMaxGas, "remainingMaxGas mismatch");
        assertEq(unpacked.writeoffsGas, before.writeoffsGas, "writeoffsGas mismatch");
        assertEq(unpacked.solverFaultFailureGas, before.solverFaultFailureGas, "solverFaultFailureGas mismatch");
        assertEq(unpacked.unreachedSolverGas, before.unreachedSolverGas, "unreachedSolverGas mismatch");
        assertEq(unpacked.maxApprovedGasSpend, before.maxApprovedGasSpend, "maxApprovedGasSpend mismatch");
        assertEq(unpacked.atlasSurchargeRate, before.atlasSurchargeRate, "atlasSurchargeRate mismatch");
        assertEq(unpacked.bundlerSurchargeRate, before.bundlerSurchargeRate, "bundlerSurchargeRate mismatch");
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
        uint256 totalSurchargeRate = 8_000; // 80%

        GasLedger memory gL = GasLedger({
            remainingMaxGas: 10_000,
            writeoffsGas: 0,
            solverFaultFailureGas: 0,
            unreachedSolverGas: 5_000,
            maxApprovedGasSpend: 0,
            atlasSurchargeRate: 3_000, // 30%
            bundlerSurchargeRate: 5_000 // 50%
        });

        vm.txGasPrice(5);

        // Should be: (10_000 - 5_000) * (100% + 80%) * 5 = 5_000 * 1.8 * 5 = 45_000
        uint256 expected = uint256(gL.remainingMaxGas - gL.unreachedSolverGas).withSurcharge(totalSurchargeRate) * tx.gasprice;
        assertEq(gL.solverGasLiability(), expected, "solverGasLiability unexpected");
    }

    function test_GasAccLib_solverOpCalldataGas() public view {
        uint256 calldataLength = 500;

        // First, the default calculation, using address(0) as the GasCalculator:
        uint256 expectedDefaultGas = (calldataLength + GasAccLib._SOLVER_OP_STATIC_LENGTH) * GasAccLib._GAS_PER_CALLDATA_BYTE;

        assertEq(GasAccLib.solverOpCalldataGas(calldataLength, address(0)), expectedDefaultGas, "solverOpCalldataGas (default) unexpected");

        // Now, with a mock L2GasCalculator, that returns 5x the default calldata gas:
        uint256 expectedMockGas = 5 * expectedDefaultGas;

        assertEq(GasAccLib.solverOpCalldataGas(calldataLength, address(mockL2GasCalc)), expectedMockGas, "solverOpCalldataGas (5x mock) unexpected");
    }

    function test_GasAccLib_metacallCalldataGas() public view {
        uint256 msgDataLength = 3_000;

        // First, the default calculation, using address(0) as the GasCalculator:
        uint256 expectedDefaultGas = msgDataLength * GasAccLib._GAS_PER_CALLDATA_BYTE;

        assertEq(GasAccLib.metacallCalldataGas(msgDataLength, address(0)), expectedDefaultGas, "metacallCalldataGas (default) unexpected");

        // Now, with a mock L2GasCalculator, that returns 5x the default calldata gas:
        uint256 expectedMockGas = 5 * expectedDefaultGas;

        assertEq(GasAccLib.metacallCalldataGas(msgDataLength, address(mockL2GasCalc)), expectedMockGas, "metacallCalldataGas (5x mock) unexpected");
    }
}