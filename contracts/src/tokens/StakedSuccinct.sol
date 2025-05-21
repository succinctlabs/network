// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "../../lib/openzeppelin-contracts/contracts/utils/Nonces.sol";

string constant NAME = "StakedSuccinct";
string constant SYMBOL = "stPROVE";

/// @title StakedSuccinct
/// @author Succinct Labs
/// @notice The terminal receipt token for staking in the Succinct Prover Network.
/// @dev This contract balance stays 1:1 with all $PROVER-N vaults to give one unified
///      source of truth to track delegated staked $PROVE.
abstract contract StakedSuccinct is ERC20, ERC20Permit, ERC20Votes {
    error NonTransferable();

    bool internal transient isStakingOperation;

    modifier stakingOperation() {
        isStakingOperation = true;
        _;
        isStakingOperation = false;
    }

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) {}

    function name() public pure virtual override returns (string memory) {
        return NAME;
    }

    function symbol() public pure virtual override returns (string memory) {
        return SYMBOL;
    }

    /// @dev Only can update balances when staking operations are happening. This is equivalent to
    /// the only staking checks that we have on $iPROVE and $PROVER-N tokens.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        if (!isStakingOperation) {
            revert NonTransferable();
        }

        super._update(from, to, value);
    }

    // The following functions are overrides required by Solidity.

    function nonces(address _owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(_owner);
    }
}
