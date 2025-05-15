// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract Bridge {
    using SafeERC20 for IERC20;

    /// @dev The PROVE token address, which is used as the underlying asset for this bridge.
    address internal immutable PROVE;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    constructor(address _prove) {
        PROVE = _prove;
    }

    function prove() external view returns (address) {
        return PROVE;
    }

    function permitAndDeposit(
        address _from,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit(PROVE).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        _deposit(_from, _amount);
    }

    function deposit(uint256 _amount) public {
        _deposit(msg.sender, _amount);
    }

    function withdraw(address _to, uint256 _amount) external {
        IERC20(PROVE).safeTransfer(_to, _amount);

        emit Withdrawal(_to, _amount);
    }

    function _deposit(address _from, uint256 _amount) internal {
        IERC20(PROVE).safeTransferFrom(_from, address(this), _amount);

        emit Deposit(_from, _amount);
    }
}

/// @dev A mock vApp implementation. The vApp is responsible for dispensing, rewarding, and slashing.
contract MockVApp is Bridge {
    using SafeERC20 for IERC20;

    address internal immutable STAKING;

    constructor(address _staking, address _prove) Bridge(_prove) {
        STAKING = _staking;
    }

    function staking() external view returns (address) {
        return STAKING;
    }

    function processReward(address _prover, uint256 _amount) external {
        // Transfer PROVE from VApp to STAKING first
        IERC20(PROVE).safeTransfer(STAKING, _amount);

        // Now call reward (no need for approval as STAKING already has the tokens)
        ISuccinctStaking(STAKING).reward(_prover, _amount);
    }

    function processSlash(address _prover, uint256 _amount) external returns (uint256) {
        return ISuccinctStaking(STAKING).requestSlash(_prover, _amount);
    }
}
