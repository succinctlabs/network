// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract CreateProverAndStakeScript is BaseScript {
    string internal constant KEY = "PROVER";

    function run() external broadcaster {
        // Read config
        address STAKING = readAddress("STAKING");
        address PROVE = readAddress("PROVE");
        uint256 STAKER_FEE_BIPS = 1000; // 10%
        uint256 STAKE_AMOUNT = 10_000e18;

        // Ensure not already staked
        if (SuccinctStaking(STAKING).balanceOf(msg.sender) > 0) {
            revert("Already staked");
        }

        // Create prover
        address prover = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        // Check if needs to approve PROVE
        if (IERC20(PROVE).allowance(msg.sender, STAKING) < STAKE_AMOUNT) {
            IERC20(PROVE).approve(STAKING, STAKE_AMOUNT);
        }

        // Stake
        SuccinctStaking(STAKING).stake(prover, STAKE_AMOUNT);

        // Write address
        writeAddress(KEY, prover);
    }
}
