// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockERC20} from "./MockERC20.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract MockERC4626 is MockERC20, IERC4626 {
    address public immutable asset;

    constructor(string memory name, string memory symbol, uint8 decimals_, address _asset)
        MockERC20(name, symbol, decimals_)
    {
        asset = _asset;
    }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        // Simple 1:1 conversion for testing.
        shares = assets;

        // Transfer assets from sender to this contract.
        IERC20(asset).transferFrom(msg.sender, address(this), assets);

        // Mint shares to receiver.
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = shares; // 1:1 conversion
        IERC20(asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        returns (uint256 shares)
    {
        shares = assets; // 1:1 conversion
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(asset).transfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        returns (uint256 assets)
    {
        assets = shares; // 1:1 conversion
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }
        _burn(owner, shares);
        IERC20(asset).transfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return assets;
    }

    function totalAssets() public view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 conversion
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1 conversion
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 conversion
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1 conversion
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return balanceOf(owner); // 1:1 conversion
    }

    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 conversion
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return shares; // 1:1 conversion
    }
}
