// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {FeeCalculator} from "../libraries/FeeCalculator.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProverRegistry} from "../interfaces/IProverRegistry.sol";

/// @dev A mock vApp implementation. The vApp is responsible for dispensing, rewarding, and slashing.
contract MockVApp {
    using SafeERC20 for IERC20;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);

    address public immutable staking;
    address public immutable prove;
    address public immutable iProve;
    address public immutable feeVault;
    uint256 public immutable protocolFeeBips;

    /// @dev Balances mapping - simulates offchain balances which is the case in the real VApp.
    mapping(address => uint256) public balances;

    /// @dev Simple withdraw claims mapping - In the real VApp this would only get updated after an `updateState`.
    mapping(address => uint256) public withdrawClaims;

    constructor(
        address _staking,
        address _prove,
        address _iProve,
        address _feeVault,
        uint256 _protocolFeeBips
    ) {
        staking = _staking;
        prove = _prove;
        iProve = _iProve;
        feeVault = _feeVault;
        protocolFeeBips = _protocolFeeBips;

        // Approve the $iPROVE contract to transfer $PROVE from this contract during prover withdrawal.
        IERC20(prove).approve(_iProve, type(uint256).max);
    }

    function permitAndDeposit(
        address _from,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit(prove).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        _deposit(_from, _amount);
    }

    function deposit(uint256 _amount) public {
        _deposit(msg.sender, _amount);
    }

    function withdraw(address _to, uint256 _amount) external {
        IERC20(prove).safeTransfer(_to, _amount);

        emit Withdrawal(_to, _amount);
    }

    function _deposit(address _from, uint256 _amount) internal {
        IERC20(prove).safeTransferFrom(_from, address(this), _amount);

        emit Deposit(_from, _amount);
    }

    function addDelegatedSignerForProver(address, address) external pure returns (uint64) {
        return 0;
    }

    function claimableWithdrawal(address) external view returns (uint256) {
        return withdrawClaims[msg.sender];
    }

    function requestWithdraw(address account, uint256 amount) external returns (uint64) {
        // If amount is max, withdraw all
        if (amount == type(uint256).max) {
            amount = balances[account];
        }

        balances[account] -= amount;
        withdrawClaims[account] += amount;

        // Return a dummy receipt ID (in real VApp this would be meaningful)
        return 1;
    }

    function finishWithdrawal(address account) external {
        uint256 amount = withdrawClaims[account];
        if (amount == 0) {
            revert("No withdrawal claim");
        }

        withdrawClaims[account] = 0;

        if (IProverRegistry(staking).isProver(account)) {
            // Deposit $PROVE to mint $iPROVE, sending it to this contract.
            uint256 iPROVE = IERC4626(iProve).deposit(amount, address(this));

            // Transfer the $iPROVE from this contract to the prover vault.
            IERC20(iProve).safeTransfer(account, iPROVE);
        } else {
            IERC20(prove).safeTransfer(account, amount);
        }
    }

    /// @dev This simulates a prover finishing a proof fulfillment. Offchain, this adds to the balances
    ///      of the prover, the prover owner, and the fee vault. We update our balances mapping to
    ///      simulate this.
    ///
    ///      The fee splitting logic is the same as the real VApp STF.
    function processReward(address _prover, uint256 _amount) external {
        uint256 stakerFeeBips = IProver(_prover).stakerFeeBips();

        (uint256 protocolReward, uint256 stakerReward, uint256 ownerReward) =
            FeeCalculator.calculateFeeSplit(_amount, protocolFeeBips, stakerFeeBips);

        address proverOwner = IProver(_prover).owner();

        balances[feeVault] += protocolReward;
        balances[_prover] += stakerReward;
        balances[proverOwner] += ownerReward;
    }

    function processSlash(address _prover, uint256 _amount) external returns (uint256) {
        return ISuccinctStaking(staking).requestSlash(_prover, _amount);
    }
}
