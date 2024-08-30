// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract HoneyPotTestToken is ERC20, Ownable {
    constructor()
        ERC20("HoneyPotTestToken", "HPTest")
        Ownable(msg.sender)
    {
        _mint(msg.sender, 100);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}