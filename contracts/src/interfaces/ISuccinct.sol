// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ISuccinct {
    /// @notice Mints the specified amount of $PROVE to the specified address. Only callable by the owner.
    /// @param to The address to mint $PROVE to.
    /// @param amount The amount of $PROVE to mint.
    function mint(address to, uint256 amount) external;
}
