// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

string constant NAME = "MockUSDC";
string constant SYMBOL = "USDC";

contract MockUSDC is ERC20 {
    constructor() ERC20(NAME, SYMBOL) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }
}
