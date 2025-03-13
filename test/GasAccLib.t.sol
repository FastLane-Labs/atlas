// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import { GasAccLib, GasLedger, BorrowsLedger } from "../src/contracts/libraries/GasAccLib.sol";
import { AccountingMath } from "../src/contracts/libraries/AccountingMath.sol";
import { BaseTest } from "./base/BaseTest.t.sol";

contract GasAccLibTest is Test {
    using SafeCast for uint128;
    using GasAccLib for GasLedger;
    using GasAccLib for BorrowsLedger;
    using GasAccLib for uint256;
    using AccountingMath for uint256;

    function setUp() public {}

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

    function test_solverGasLiability() public {
        // TODO
    }

    function test_sumSolverOpsCalldataGas() public {
        // TODO
    }

    function test_metacallCalldataGas() public {
        // TODO
    }
}