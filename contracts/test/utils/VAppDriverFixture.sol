// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";
import {MockStaking} from "../../src/mocks/MockStaking.sol";
import {MockVerifier} from "../../src/mocks/MockVerifier.sol";
import {
    ERC1967Proxy
} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Deploy only to a disposable local EVM. Proof verification is deliberately mocked.
contract VAppDriverFixture {
    SuccinctVApp public immutable vapp;
    Succinct public immutable token;

    constructor(bytes32 root, bytes32 vkey, address auctioneer, address user, uint256 amount) {
        require(block.chainid == 31337, "local test chain only");
        token = new Succinct(address(this));
        MockStaking staking =
            new MockStaking(address(1), address(0), address(token), address(token), address(2));
        vapp = SuccinctVApp(address(new ERC1967Proxy(address(new SuccinctVApp()), "")));
        vapp.initialize(
            auctioneer,
            address(token),
            address(token),
            auctioneer,
            address(staking),
            address(new MockVerifier()),
            1,
            vkey,
            root
        );
        staking.setVApp(address(vapp));
        token.mint(user, amount);
    }
}
