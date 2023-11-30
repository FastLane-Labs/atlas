// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";

import { Storage } from "src/contracts/atlas/Storage.sol";

using stdStorage for StdStorage;


contract StorageTest is Test {
    function testNewStorage() public {
        Storage s = new Storage(
            1, // _escrowDuration
            address(1), // _factory
            address(2), // _verification
            address(3), // _gasAccLib
            address(4), // _safetyLocksLib
            address(5) // _simulator
        );

        assertEq(s.ESCROW_DURATION(), 1);
        assertEq(s.FACTORY(), address(1));
        assertEq(s.VERIFICATION(), address(2));
        assertEq(s.GAS_ACC_LIB(), address(3));
        assertEq(s.SAFETY_LOCKS_LIB(), address(4));
        assertEq(s.SIMULATOR(), address(5));
    }

    function testStorageSlotsDontChange() public {
        Storage s = new Storage(
            1, // _escrowDuration
            address(1), // _factory
            address(2), // _verification
            address(3), // _gasAccLib
            address(4), // _safetyLocksLib
            address(5) // _simulator
        );

        // look up the storage slots so that we can make sure they don't change by accident
        
        uint256 totalSupplySlot = stdstore.target(address(s)).sig('totalSupply()').find();
        uint256 noncesSlot = stdstore.target(address(s)).sig('nonces(address)').with_key(address(this)).find();
        uint256 lockSlot = stdstore.target(address(s)).sig('lock()').find();

        // TODO: figure out how to check the allowance and ledger slots, haven't been able to make these work yet

        // if you're getting an error from one of these assertions, it means that the storage slot has changed
        // and you either need to update the slot number or revert the change

        assertEq(totalSupplySlot, 0);
        assertEq(noncesSlot, 49784443915320261189887103614045882155521089248264299114442679287293484801912);
        assertEq(lockSlot, 4);
    }
}
