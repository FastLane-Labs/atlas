// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    )
        ERC20(_name, _symbol, _decimals)
        Ownable()
    { }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}
