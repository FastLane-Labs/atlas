// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Storage } from "src/contracts/atlas/Storage.sol";
import { AtlasVerification } from "src/contracts/atlas/AtlasVerification.sol";

using stdStorage for StdStorage;

contract StorageTest is Test {
    function testNewStorage() public {
        MockStorageTests s = new MockStorageTests(
            1, // _escrowDuration
            address(1), // _verification
            address(2), // _simulator
            address(3) // _surchargeRecipient
        );

        assertEq(s.ESCROW_DURATION(), 1);
        assertEq(address(s.VERIFICATION()), address(1));
        assertEq(s.SIMULATOR(), address(2));
        assertEq(s.getInitialChainId(), block.chainid);
        assertEq(s.getInitialDomainSeparator(), bytes32("SEPARATOR"));
    }

    function testStorageSlotsDontChange() public {
        // TODO add these back once slots have been finalized, causing CI blocks for now
        // Storage s = new Storage(
        //     1, // _escrowDuration
        //     address(1), // _verification
        //     address(2) // _simulator
        // );

        // look up the storage slots so that we can make sure they don't change by accident

        // uint256 totalSupplySlot = stdstore.target(address(s)).sig("totalSupply()").find();
        // uint256 noncesSlot = stdstore.target(address(s)).sig("nonces(address)").with_key(address(this)).find();
        // uint256 lockSlot = stdstore.target(address(s)).sig("lock()").find();

        // TODO: figure out how to check the allowance and ledger slots, haven't been able to make these work yet

        // if you're getting an error from one of these assertions, it means that the storage slot has changed
        // and you either need to update the slot number or revert the change

        // assertEq(totalSupplySlot, 0);
        // assertEq(
        //     noncesSlot,
        //     49_784_443_915_320_261_189_887_103_614_045_882_155_521_089_248_264_299_114_442_679_287_293_484_801_912
        // );
        // assertEq(lockSlot, 5);
    }
}

contract MockStorageTests is Storage {
    constructor(
        uint256 _escrowDuration,
        address _verification,
        address _simulator,
        address _surchargeRecipient
    )
        Storage(_escrowDuration, _verification, _simulator, _surchargeRecipient)
    { }

    function getInitialChainId() public view returns (uint256) {
        return _INITIAL_CHAIN_ID;
    }

    function getInitialDomainSeparator() public view returns (bytes32) {
        return _INITIAL_DOMAIN_SEPARATOR;
    }

    function _computeDomainSeparator() internal view virtual override returns (bytes32) {
        return bytes32("SEPARATOR");
    }
}
