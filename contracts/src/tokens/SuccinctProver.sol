// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {ISuccinctVApp} from "../interfaces/ISuccinctVApp.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

string constant NAME_PREFIX = "SuccinctProver";
string constant SYMBOL_PREFIX = "PROVER";

/// @title SuccinctProver
/// @author Succinct Labs
/// @notice The per-prover receipt token for delegating stake to a prover.
/// @dev This contract accepts $iPROVE and mints $PROVER-N:
///      - Each prover has their own deployment of this contract
///        - underlying, reward, and staking are all the same across all provers
///        - id and owner are unique to each prover
///      - Stakers choose which prover to delegate to
///      - It can gain rewards from SuccinctStaking.reward()
///      - It can lose underlying by SuccinctStaking.slash()
///      - It is non-transferable outside of stake/unstake
contract SuccinctProver is ERC4626, IProver {
    using Strings for uint256;

    /// @inheritdoc IProver
    address public immutable override staking;

    /// @inheritdoc IProver
    address public immutable override owner;

    /// @inheritdoc IProver
    uint256 public immutable override id;

    /// @inheritdoc IProver
    uint256 public immutable override stakerFeeBips;

    constructor(
        address _underlying,
        address _staking,
        address _owner,
        uint256 _id,
        uint256 _stakerFeeBips
    )
        ERC20(
            string.concat(NAME_PREFIX, "-", _id.toString()),
            string.concat(SYMBOL_PREFIX, "-", _id.toString())
        )
        ERC4626(IERC20(_underlying))
    {
        staking = _staking;
        owner = _owner;
        id = _id;
        stakerFeeBips = _stakerFeeBips;
    }

    /// @inheritdoc IProver
    function claimRewards() external override {
        address vapp = ISuccinctStaking(staking).vapp();

        ISuccinctVApp(vapp).claimWithdrawal(msg.sender);
    }

    /// @dev Override to prevent transfers of $PROVER-N tokens except for stake/unstake
    function _update(address _from, address _to, uint256 _value) internal override(ERC20) {
        if (msg.sender != staking) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }

    /// @dev Override to allow the staking contract to spend $PROVER-N.
    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
        if (_spender == staking) {
            return;
        }

        super._spendAllowance(_owner, _spender, _amount);
    }
}
