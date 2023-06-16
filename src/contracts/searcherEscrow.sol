//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.16;


library Escrow {

    struct SearcherEscrow {
        uint128 total;
        uint128 escrowed;
        uint32 accessible; // block.number when funds are available. 200 years from now using polygon numbers
        uint32 nonce; // EOA nonce. honestly bro you deserve to get wrecked if you overflow
        address searcherContract; // only one searcher contract per EOA
    }

    function available(SearcherEscrow memory self) internal pure returns (uint256) {
        return uint256(self.total - self.escrowed);
    }

}