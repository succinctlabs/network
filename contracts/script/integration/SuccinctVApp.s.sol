// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {MockERC20} from "../../test/utils/MockERC20.sol";
import {MockStaking} from "../../src/mocks/MockStaking.sol";
import {FixtureLoader, SP1ProofFixtureJson, Fixture} from "../../test/utils/FixtureLoader.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {SP1VerifierGateway} from "../../lib/sp1-contracts/contracts/src/SP1VerifierGateway.sol";
import {SP1Verifier} from "../../lib/sp1-contracts/contracts/src/v5.0.0/SP1VerifierGroth16.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";

contract DeployProveAndVAppScript is BaseScript, FixtureLoader {
    string internal constant PROVE_KEY = "PROVE";
    string internal constant STAKING_KEY = "STAKING";
    string internal constant VAPP_KEY = "VAPP";

    // Get from the corresponding chain deployment here:
    // https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    address internal SP1_VERIFIER_GATEWAY_GROTH16 = 0x397A5f7f3dBd538f23DE225B51f532c34448dA9B;

    function run() external broadcaster {
        // Deploy the SP1VerifierGatway.
        SP1VerifierGateway gateway = new SP1VerifierGateway(msg.sender);
        SP1Verifier groth16 = new SP1Verifier();
        gateway.addRoute(address(groth16));

        // Deploy SuccinctStaking.
        SuccinctStaking staking = new SuccinctStaking(msg.sender);

        // Deploy MockERC20 PROVE and iPROVE tokens.
        Succinct prove = new Succinct(msg.sender);
        IntermediateSuccinct iProve = new IntermediateSuccinct(address(prove), address(staking));

        // Deploy VApp contract
        bytes32 vkey = bytes32(0x008191fd1466cbb0dc44b6bf0b09d3c302fc2891c15bd66a28106e74c8edc907);
        bytes32 genesisStateRoot =
            bytes32(0x4b15a7d34ea0ec471d0d6ab9170cc2910f590819ee168e2a799e25244e327116);
        uint64 genesisTimestamp = 0;
        address vAppImpl = address(new SuccinctVApp());
        SuccinctVApp vApp = SuccinctVApp(payable(address(new ERC1967Proxy(vAppImpl, ""))));
        vApp.initialize(
            msg.sender,
            address(prove),
            address(iProve),
            msg.sender,
            address(staking),
            address(gateway),
            0,
            vkey,
            genesisStateRoot
        );

        // Initialize SuccinctStaking.
        staking.initialize(address(vApp), address(prove), address(iProve), 10e18, 1 days, 1 days, 0);

        // ===== MINT PROVE TOKENS =====
        console.log("=== Minting PROVE tokens ===");
        uint256 totalMintAmount = 1000000 * 1e18;
        prove.mint(msg.sender, totalMintAmount);
        console.log("Minted %s PROVE tokens to %s", totalMintAmount / 1e18, msg.sender);
        console.log("Your PROVE balance: %s", prove.balanceOf(msg.sender) / 1e18);

        // ===== CREATE PROVER =====
        console.log("\n=== Creating prover ===");
        address prover = staking.createProver(10000);
        console.log("Created prover: %s", prover);

        // ===== STAKE TO PROVER =====
        console.log("\n=== Staking to prover ===");
        prove.approve(address(staking), staking.minStakeAmount());
        staking.stake(prover, staking.minStakeAmount());
        console.log("Staked %s PROVE tokens to prover", totalMintAmount / 1e18);
        console.log("Prover PROVE balance: %s", prove.balanceOf(prover) / 1e18);

        // ===== PROCESS 10 DEPOSITS =====
        console.log("\n=== Processing 10 deposits ===");

        // Pre-calculate total approval needed to reduce transactions
        uint256 totalApprovalNeeded = 0;
        for (uint256 i = 0; i < 10; i++) {
            uint256 depositAmount = (100 + (i * 10)) * 1e18;
            totalApprovalNeeded += depositAmount;
        }

        // Single approval for all deposits
        prove.approve(address(vApp), totalApprovalNeeded);
        console.log("Approved %s PROVE tokens for batch deposits", totalApprovalNeeded / 1e18);

        uint256 totalDeposited = 0;
        uint64[] memory depositReceipts = new uint64[](10);

        for (uint256 i = 0; i < 10; i++) {
            // Vary deposit amounts: base amount + some variation based on index
            uint256 depositAmount = (100 + (i * 10)) * 1e18; // 100, 110, 120, ... 190 PROVE

            uint64 receipt = SuccinctVApp(address(vApp)).deposit(depositAmount);
            depositReceipts[i] = receipt;
            totalDeposited += depositAmount;

            // Log every 5th deposit to avoid spam
            if ((i + 1) % 5 == 0) {
                console.log(
                    "Completed %s deposits. Latest: %s PROVE (Receipt #%s)",
                    i + 1,
                    depositAmount / 1e18,
                    receipt
                );
            }
        }

        console.log("Total deposited: %s PROVE", totalDeposited / 1e18);
        console.log("VApp PROVE balance: %s", prove.balanceOf(address(vApp)) / 1e18);
        console.log("Your remaining PROVE balance: %s", prove.balanceOf(msg.sender) / 1e18);

        // ===== PROCESS 10 WITHDRAWAL REQUESTS =====
        console.log("\n=== Processing 10 withdrawal requests ===");

        uint256 totalWithdrawRequested = 0;
        uint64[] memory withdrawalReceipts = new uint64[](10);

        for (uint256 i = 0; i < 10; i++) {
            // Vary withdrawal amounts: smaller amounts to ensure we don't exceed deposits
            uint256 withdrawAmount = (50 + (i * 5)) * 1e18; // 50, 55, 60, ... 545 PROVE

            uint64 withdrawReceipt =
                SuccinctVApp(address(vApp)).requestWithdraw(msg.sender, withdrawAmount);
            withdrawalReceipts[i] = withdrawReceipt;
            totalWithdrawRequested += withdrawAmount;

            // Log every 5th withdrawal to avoid spam
            if ((i + 1) % 5 == 0) {
                console.log(
                    "Completed %s withdrawals. Latest: %s PROVE (Receipt #%s)",
                    i + 1,
                    withdrawAmount / 1e18,
                    withdrawReceipt
                );
            }
        }

        console.log("Total withdrawal requested: %s PROVE", totalWithdrawRequested / 1e18);

        // ===== SUMMARY =====
        console.log("\n=== Summary ===");
        console.log("PROVE Token Address: %s", address(prove));
        console.log("MockStaking Address: %s", address(staking));
        console.log("SuccinctVApp Address: %s", address(vApp));
        console.log("Current Receipt Number: %s", SuccinctVApp(address(vApp)).currentOnchainTxId());
        console.log("VApp PROVE Balance: %s", prove.balanceOf(address(vApp)) / 1e18);
        console.log("Your PROVE Balance: %s", prove.balanceOf(msg.sender) / 1e18);
        console.log("Total Deposits Made: 10");
        console.log("Total Withdrawals Requested: 10");
        console.log("Net Deposited: %s PROVE", (totalDeposited - totalWithdrawRequested) / 1e18);
    }
}
