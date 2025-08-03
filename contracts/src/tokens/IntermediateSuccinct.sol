// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProverRegistry} from "../interfaces/IProverRegistry.sol";
import {IIntermediateSuccinct} from "../interfaces/IIntermediateSuccinct.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC4626} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {Nonces} from "../../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

string constant NAME = "IntermediateSuccinct";
string constant SYMBOL = "iPROVE";

/// @title IntermediateSuccinct
/// @author Succinct Labs
/// @notice The intermediary receipt token for receiving periodic $PROVE rewards.
/// @dev This contract accepts $PROVE and mints $iPROVE. It is non-transferable outside of
///      staking operations.
contract IntermediateSuccinct is ERC4626, ERC20Permit, ERC20Votes, IIntermediateSuccinct {
    /// @inheritdoc IIntermediateSuccinct
    address public override staking;

    constructor(address _underlying, address _staking)
        ERC20(NAME, SYMBOL)
        ERC4626(IERC20(_underlying))
        ERC20Permit(NAME)
    {
        staking = _staking;
    }

    /// @inheritdoc IIntermediateSuccinct
    function burn(address _from, uint256 _iPROVE) external override returns (uint256) {
        if (msg.sender != staking) {
            revert NonTransferable();
        }

        // Burn the $PROVE
        uint256 PROVE = previewRedeem(_iPROVE);
        ERC20Burnable(asset()).burn(PROVE);

        // Burn the $iPROVE
        _burn(_from, _iPROVE);

        return PROVE;
    }

    /// @dev Only the staking contract, the vApp, or the prover can transfer in certain
    ///      situations.
    ///
    ///      Each situation is as follows:
    ///      1a. The staking contract needs to transfer $iPROVE to a prover during stake():
    ///         - $iPROVE.deposit() - transfer from address(0) to staking
    ///         - $PROVER-N.deposit() - transfer from staking to prover
    ///      1b. The staking contract needs to transfer $iPROVE to a prover during unstake():
    ///         - $PROVER-N.redeem() - transfer from prover to staking
    ///         - $iPROVE.redeem() - transfer from staking to address(0)
    ///      2. The vApp contract needs to deposit to $iPROVE directly to a prover during
    ///         processWithdraw(to), when `to` is a prover to process it as a prover reward:
    ///         - $iPROVE.deposit() - transfer from address(0) to prover
    ///
    ///      This function is maximally constrained to only allow for the above situations.
    function _update(address _from, address _to, uint256 _value)
        internal
        override(ERC20, ERC20Votes)
    {
        // Check for (1).
        bool isStakeOrUnstake = msg.sender == staking
            || (IProverRegistry(staking).isProver(msg.sender) && (_from == staking || _to == staking));

        // If not (1), check for (2).
        bool isProverReward;
        if (!isStakeOrUnstake) {
            // vApp can deposit to provers only.
            isProverReward = msg.sender == IProverRegistry(staking).vapp() && _from == address(0)
                && IProverRegistry(staking).isProver(_to);
        }

        // If not (1) or (2), revert.
        if (!isStakeOrUnstake && !isProverReward) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }

    /// @dev Override to allow the staking contract to spend $iPROVE.
    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
        if (_spender == staking) {
            return;
        }

        super._spendAllowance(_owner, _spender, _amount);
    }

    // The following functions are for overriding the clock and clock mode for IERC6372. This
    // allows governance to be based on time instead of block number.

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // The following functions are overrides required by Solidity.

    function nonces(address _owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(_owner);
    }

    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }
}
