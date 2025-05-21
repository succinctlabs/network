// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title IWeth
/// @notice Interface for the Wrapped Ether (WETH) token contract
interface IWeth is IERC20 {
    /// @notice Deposit ETH and receive WETH tokens
    function deposit() external payable;

    /// @notice Withdraw ETH by burning WETH tokens
    /// @param wad The amount of WETH to burn and ETH to receive
    function withdraw(uint256 wad) external;

    /// @notice Get the name of the token
    /// @return The name of the token
    function name() external view returns (string memory);

    /// @notice Get the symbol of the token
    /// @return The symbol of the token
    function symbol() external view returns (string memory);

    /// @notice Get the number of decimals the token uses
    /// @return The number of decimals
    function decimals() external view returns (uint8);
}
