// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "../../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

contract MockERC20 is ERC20, ERC20Permit, ERC20Votes {
    uint8 internal _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(address _from, address _to, uint256 _value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(_from, _to, _value);
    }

    function nonces(address _owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(_owner);
    }

    function decimals() public view virtual override(ERC20) returns (uint8) {
        return _decimals;
    }
}
