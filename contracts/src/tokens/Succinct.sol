// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISuccinct} from "../interfaces/ISuccinct.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

string constant NAME = "Succinct";
string constant SYMBOL = "PROVE";

/// @title Succinct
/// @author Succinct Labs
/// @notice The primary token for the Succinct Prover Network.
contract Succinct is ERC20, ERC20Permit, ERC20Burnable, Ownable, ISuccinct {
    constructor(address _owner) ERC20(NAME, SYMBOL) ERC20Permit(NAME) Ownable(_owner) {}

    /// @inheritdoc ISuccinct
    function mint(address _to, uint256 _amount) external override onlyOwner {
        _mint(_to, _amount);
    }
}
