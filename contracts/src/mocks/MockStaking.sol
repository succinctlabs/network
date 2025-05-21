// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MockStaking {
    address public PROVE;

    constructor(address _prove) {
        PROVE = _prove;
    }

    mapping(address => bool) public isProverVault;
    mapping(address => mapping(address => uint256)) public proverVaultBalances;
    mapping(address => bool) public provers;
    mapping(address => bool) internal _isProver;

    function hasProver(address _account) public view returns (bool) {
        return provers[_account];
    }

    function setHasProver(address _account, bool _status) external {
        provers[_account] = _status;
    }

    function isProver(address _account) public view returns (bool) {
        return _isProver[_account];
    }

    function setIsProver(address _account, bool _status) external {
        _isProver[_account] = _status;
    }

    function stake(address _depositor, address _proverVault, uint256 _amount) external {
        proverVaultBalances[_proverVault][_depositor] += _amount;

        IERC20(PROVE).transferFrom(_depositor, address(this), _amount);
    }

    function unstake(
        address _withdrawer,
        address _proverVault,
        address _destination,
        uint256 _amount
    ) external {
        proverVaultBalances[_proverVault][_withdrawer] -= _amount;

        IERC20(PROVE).transfer(_destination, _amount);
    }
}
