// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISP1Verifier} from "../../lib/sp1-contracts/contracts/src/ISP1Verifier.sol";

contract MockVerifier is ISP1Verifier {
    function verifyProof(bytes32, bytes calldata, bytes calldata) external view {
        // No-op
    }
}
