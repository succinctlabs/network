// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VmSafe} from "../../lib/forge-std/src/Vm.sol";
import {stdJson} from "../../lib/forge-std/src/StdJson.sol";

enum Fixture {
    Groth16,
    Plonk
}

struct ProofFixtureJson {
    bytes proof;
    bytes publicValues;
    bytes32 vkey;
}

contract FixtureLoader {
    using stdJson for string;

    function loadFixture(VmSafe vm, Fixture fixture)
        public
        view
        returns (ProofFixtureJson memory)
    {
        string memory fixturePath;
        if (fixture == Fixture.Groth16) {
            fixturePath = "/fixtures/groth16-fixture.json";
        } else if (fixture == Fixture.Plonk) {
            fixturePath = "/fixtures/plonk-fixture.json";
        } else {
            revert("Invalid fixture");
        }

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, fixturePath);
        string memory json = vm.readFile(path);
        bytes memory jsonBytes = json.parseRaw(".");
        return abi.decode(jsonBytes, (ProofFixtureJson));
    }
}
