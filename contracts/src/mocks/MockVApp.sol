// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
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

    uint256 internal constant FEE_UNIT = 10000;
    address internal immutable STAKING;
    address internal immutable FEE_VAULT;
    uint256 internal immutable PROTOCOL_FEE_BIPS;

    constructor(address _staking, address _prove, address _feeVault, uint256 _protocolFeeBips)
        Bridge(_prove)
    {
        STAKING = _staking;
        FEE_VAULT = _feeVault;
        PROTOCOL_FEE_BIPS = _protocolFeeBips;
    }

    function staking() external view returns (address) {
        return STAKING;
    }

    /// @dev We still maintain the same fee splitting logic as the real VApp.
    function processReward(address _prover, uint256 _amount) external {
        uint256 totalAmount = _amount;
        uint256 remainingAmount = totalAmount;

        // Step 1: Calculate and process protocol fee (if any).
        uint256 protocolFee = 0;
        if (PROTOCOL_FEE_BIPS > 0) {
            protocolFee = totalAmount * PROTOCOL_FEE_BIPS / FEE_UNIT;
            remainingAmount -= protocolFee;
            IERC20(PROVE).safeTransfer(FEE_VAULT, protocolFee);
        }

        // Step 2: Calculate and process staker reward (if any).
        uint256 stakerReward = 0;
        uint256 stakerFeeBips = IProver(_prover).stakerFeeBips();
        if (stakerFeeBips > 0) {
            stakerReward = remainingAmount * stakerFeeBips / FEE_UNIT;
            remainingAmount -= stakerReward;

            // Process the staker reward.
            IERC20(PROVE).safeTransfer(STAKING, stakerReward);
            ISuccinctStaking(STAKING).reward(_prover, stakerReward);
        }

        // Step 3: Process the prover owner reward (remainder)
        if (remainingAmount > 0) {
            address owner = IProver(_prover).owner();
            IERC20(PROVE).safeTransfer(owner, remainingAmount);
        }
    }

    function processSlash(address _prover, uint256 _amount) external returns (uint256) {
        return ISuccinctStaking(STAKING).requestSlash(_prover, _amount);
    }
}
