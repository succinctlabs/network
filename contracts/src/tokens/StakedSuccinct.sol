// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

string constant NAME = "StakedSuccinct";
string constant SYMBOL = "stPROVE";

/// @title StakedSuccinct
/// @author Succinct Labs
/// @notice The terminal receipt token for staking in the Succinct Prover Network.
/// @dev This contract balance stays 1:1 with $PROVER-N vaults to give one unified
///      source of truth to track staked $PROVE. It is non-transferable outside of
///      staking operations.
abstract contract StakedSuccinct is ERC20 {
    error NonTransferable();

    /// @dev Only true if in the process of staking or unstaking.
    bool internal transient isStakingOperation;

    modifier stakingOperation() {
        isStakingOperation = true;
        _;
        isStakingOperation = false;
    }

    constructor() ERC20(NAME, SYMBOL) {}

    function name() public pure virtual override returns (string memory) {
        return NAME;
    }

    function symbol() public pure virtual override returns (string memory) {
        return SYMBOL;
    }

    /// @dev Only can update balances when staking operations are occuring. This is equivalent to
    /// the only staking checks that we have on $iPROVE and $PROVER-N tokens.
    function _update(address _from, address _to, uint256 _value) internal override(ERC20) {
        if (!isStakingOperation) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }
}
