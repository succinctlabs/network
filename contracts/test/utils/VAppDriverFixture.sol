// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockStaking} from "../../src/mocks/MockStaking.sol";
import {MockVerifier} from "../../src/mocks/MockVerifier.sol";
import {
    ERC1967Proxy
} from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Local integration fixture that makes gas estimates reject otherwise valid large steps.
contract ExpensiveTransferToken is MockERC20 {
    constructor() MockERC20("Local receipt gas test", "TEST", 18) {}

    function transfer(address to, uint256 value) public override returns (bool) {
        uint256 start = gasleft();
        while (start - gasleft() < 250_000) {}
        return super.transfer(to, value);
    }
}

/// @dev Deploy only to a disposable local EVM. Proof verification is deliberately mocked.
contract VAppDriverFixture {
    SuccinctVApp public immutable vapp;
    ExpensiveTransferToken public immutable token;

    constructor(bytes32 root, bytes32 vkey, address auctioneer, address user, uint256 amount) {
        require(block.chainid == 31337, "local test chain only");
        token = new ExpensiveTransferToken();
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
