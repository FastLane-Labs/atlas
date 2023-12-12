// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

contract BoAtlETH {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                            METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public constant name = "Bonded Atlas ETH";
    string public constant symbol = "boAtlETH";
    uint8 public constant decimals = 18;

    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    /*//////////////////////////////////////////////////////////////
                              ATLAS
    //////////////////////////////////////////////////////////////*/

    address public immutable atlas;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _atlas) {
        atlas = _atlas;
    }

    /*//////////////////////////////////////////////////////////////
                               BOATLETH
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyAtlas {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyAtlas {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    modifier onlyAtlas() {
        require(msg.sender == atlas, "BoAtlETH: Only Atlas can call this function");
        _;
    }
}
