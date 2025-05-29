// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProverRegistry} from "../interfaces/IProverRegistry.sol";
import {IIntermediateSuccinct} from "../interfaces/IIntermediateSuccinct.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

string constant NAME = "IntermediateSuccinct";
string constant SYMBOL = "iPROVE";

/// @title IntermediateSuccinct
/// @author Succinct Labs
/// @notice The intermediary receipt token for receiving periodic PROVE rewards.
/// @dev This contract accepts $PROVE and mints $iPROVE:
///      - It can gain underlying from SuccinctStaking.dispense()
///      - It is non-transferable outside of deposit/withdraw
contract IntermediateSuccinct is ERC4626, IIntermediateSuccinct {
    /// @inheritdoc IIntermediateSuccinct
    address public override staking;

    constructor(address _underlying, address _staking)
        ERC20(NAME, SYMBOL)
        ERC4626(IERC20(_underlying))
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

    /// @dev Only the staking contract or the prover can deposit or withdraw. The latter needs
    ///      to be able to so because it is the underlying token in the prover vault and functions
    ///      require transferring it (e.g. $PROVER-N.deposit() and $PROVER-N.redeem()).
    function _update(address _from, address _to, uint256 _value) internal override(ERC20) {
        bool isDepositOrWithdraw =
            IProverRegistry(staking).isProver(msg.sender) && (_from == staking || _to == staking);

        // TODO pass in vapp addr
        address vapp = IProverRegistry(staking).vapp();

        if (msg.sender != staking && msg.sender != vapp && !isDepositOrWithdraw) {
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
}
