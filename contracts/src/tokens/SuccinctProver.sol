// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
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

    address internal immutable STAKING;
    uint256 internal immutable PROVER_ID;
    address internal immutable OWNER;

    constructor(address _underlying, address _staking, uint256 _id, address _owner)
        ERC20(
            string.concat(NAME_PREFIX, "-", _id.toString()),
            string.concat(SYMBOL_PREFIX, "-", _id.toString())
        )
        ERC4626(IERC20(_underlying))
    {
        STAKING = _staking;
        PROVER_ID = _id;
        OWNER = _owner;
    }

    /// @inheritdoc IProver
    function id() external view override returns (uint256) {
        return PROVER_ID;
    }

    /// @inheritdoc IProver
    function owner() external view override returns (address) {
        return OWNER;
    }

    /// @inheritdoc IProver
    function staking() external view override returns (address) {
        return STAKING;
    }

    /// @dev Override to prevent transfers of PROVER-N tokens except for stake/unstake
    function _update(address _from, address _to, uint256 _value) internal override(ERC20) {
        if (msg.sender != STAKING) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }

    /// @dev Override to allow the staking contract to spend $PROVER-N.
    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
        if (_spender == STAKING) {
            return;
        }

        super._spendAllowance(_owner, _spender, _amount);
    }
}
