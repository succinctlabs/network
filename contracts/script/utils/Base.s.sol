// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Vm.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Script} from "forge-std/Script.sol";

/// @notice Script to inherit from to get access to helper functions for deployments.
abstract contract BaseScript is Script {
    using stdJson for string;

    /// @notice Run the command with the `--broadcast` flag to send the transaction to the chain,
    /// otherwise just simulate the transaction execution.
    modifier broadcaster() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    /// @notice Returns the directory of the deployments.
    function directory() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/");
    }

    /// @notice Returns the file name for the current chain.
    function file() internal view returns (string memory) {
        return string.concat(vm.toString(block.chainid), ".json");
    }

    /// @notice Returns the path to the deployments file for the current chain.
    function path() internal view returns (string memory) {
        return string.concat(directory(), file());
    }

    /// @notice Returns the deployments file contents for the current chain.
    function deployments() internal view returns (string memory) {
        return vm.readFile(path());
    }

    /// @notice Ensures that the deployments file exists for the current chain.
    function ensureExists() internal {
        if (!vm.exists(directory())) {
            vm.createDir(directory(), true);
        }

        if (!vm.exists(path())) {
            vm.writeFile(path(), "{}");
        }
    }

    /// @notice Tries to read an address from the env.
    function envAddress(string memory key) internal view returns (address) {
        return vm.envOr(key, address(0));
    }

    /// @notice Tries to read a bytes32 from the env.
    function envBytes32(string memory key) internal view returns (bytes32) {
        return vm.envOr(key, bytes32(0));
    }

    /// @notice Tries to read a bool from the env.
    function envBool(string memory key) internal view returns (bool) {
        return vm.envOr(key, false);
    }

    /// @notice Tries to read an address from the env first, then from the deployments file for the current chain.
    function readAddress(string memory key) internal view returns (address) {
        if (envAddress(key) != address(0)) {
            return envAddress(key);
        }
        return deployments().readAddress(string.concat(".", key));
    }

    /// @notice Tries to read a bytes32 from the env first, then from the deployments file for the current chain.
    function readBytes32(string memory key) internal view returns (bytes32) {
        if (envBytes32(key) != bytes32(0)) {
            return envBytes32(key);
        }
        return deployments().readBytes32(string.concat(".", key));
    }

    /// @notice Tries to read a bool from the env.
    function readBool(string memory key) internal view returns (bool) {
        return envBool(key);
    }

    /// @notice Tries to read a string from the env.
    function readString(string memory key) internal view returns (string memory) {
        return vm.envString(key);
    }

    /// @notice Tries to read a uint256 from the env.
    function readUint256(string memory key) internal view returns (uint256) {
        return vm.envUint(key);
    }

    /// @notice Tries to read a uint64 from the env.
    function readUint64(string memory key) internal view returns (uint64) {
        return uint64(vm.envUint(key));
    }

    /// @notice Tries to read a uint48 from the env.
    function readUint48(string memory key) internal view returns (uint48) {
        return uint48(vm.envUint(key));
    }

    /// @notice Tries to read a uint32 from the env.
    function readUint32(string memory key) internal view returns (uint32) {
        return uint32(vm.envUint(key));
    }

    /// @notice Writes an address to the deployments file for the current chain.
    function writeAddress(string memory key, address value) internal {
        ensureExists();

        if (vm.keyExists(deployments(), string.concat(".", key))) {
            vm.writeJson(vm.toString(value), path(), string.concat(".", key));
        } else {
            string memory root = "root";
            vm.serializeJson(root, deployments());
            vm.writeJson(vm.serializeAddress(root, key, value), path());
        }
    }

    /// @notice Writes a bytes32 to the deployments file for the current chain.
    function writeBytes32(string memory key, bytes32 value) internal {
        ensureExists();

        if (vm.keyExists(deployments(), string.concat(".", key))) {
            vm.writeJson(vm.toString(value), path(), string.concat(".", key));
        } else {
            string memory root = "root";
            vm.serializeJson(root, deployments());
            vm.writeJson(vm.serializeBytes32(root, key, value), path());
        }
    }
}
