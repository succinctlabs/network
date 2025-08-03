// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from
    "../../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

string constant NAME = "StakedSuccinct";
string constant SYMBOL = "stPROVE";

/// @title StakedSuccinct
/// @author Succinct Labs
/// @notice The terminal receipt token for staking in the Succinct Prover Network.
/// @dev This contract balance stays 1:1 with $PROVER-N vaults to give one unified
///      source of truth to track staked $PROVE. It is non-transferable outside of
///      staking operations.
abstract contract StakedSuccinct is ERC20Upgradeable {
    error NonTransferable();

    /// @dev Only true if in the process of staking or unstaking.
    bool internal transient isStakingOperation;

    /// @dev This empty reserved space to add new variables without shifting down storage.
    uint256[10] private __gap;

    modifier stakingOperation() {
        isStakingOperation = true;
        _;
        isStakingOperation = false;
    }

    function __StakedSuccinct_init() internal onlyInitializing {
        __ERC20_init(NAME, SYMBOL);
    }

    function name() public pure virtual override returns (string memory) {
        return NAME;
    }

    function symbol() public pure virtual override returns (string memory) {
        return SYMBOL;
    }

    /// @dev Only can update balances when staking operations are occuring. This is equivalent to
    /// the only staking checks that we have on $iPROVE and $PROVER-N tokens.
    function _update(address _from, address _to, uint256 _value)
        internal
        override(ERC20Upgradeable)
    {
        if (!isStakingOperation) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }
}
