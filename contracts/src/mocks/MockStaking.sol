// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {ProverRegistry} from "../libraries/ProverRegistry.sol";

contract MockStaking is ProverRegistry, ISuccinctStaking {
    uint256 public minStakeAmount;
    uint256 public unstakePeriod;
    uint256 public slashPeriod;
    uint256 public dispenseRate;
    uint256 public lastDispenseTimestamp;

    mapping(address => address) internal stakerToProver;
    mapping(address => mapping(address => uint256)) internal proverVaultBalances;
    mapping(address => UnstakeClaim[]) internal unstakeClaims;
    mapping(address => SlashClaim[]) internal slashClaims;

    constructor(address _governor, address _prove, address _iProve) {
        __ProverRegistry_init(_governor, address(this), _prove, _iProve);
    }

    function setVApp(address _vapp) external {
        vapp = _vapp;
    }

    function stakedTo(address _staker) external view override returns (address) {
        return stakerToProver[_staker];
    }

    function staked(address _staker) external view override returns (uint256) {
        return proverVaultBalances[stakerToProver[_staker]][_staker];
    }

    function proverStaked(address) public pure override returns (uint256) {
        return 1;
    }

    function unstakeRequests(address _staker)
        external
        view
        override
        returns (UnstakeClaim[] memory)
    {
        return unstakeClaims[_staker];
    }

    function slashRequests(address _prover) external view override returns (SlashClaim[] memory) {
        return slashClaims[_prover];
    }

    function unstakePending(address) external pure override returns (uint256) {
        return 0;
    }

    function previewRedeem(address, uint256) public pure override returns (uint256 amount) {
        return amount;
    }

    function maxDispense() public pure override returns (uint256) {
        return 0;
    }

    function createProver(address _owner, uint256 _stakerFeeBips) external returns (address) {
        return _deployProver(_owner, _stakerFeeBips);
    }

    function stake(address _prover, uint256 _amount) external override returns (uint256) {
        IERC20(prove).transferFrom(msg.sender, address(this), _amount);
        proverVaultBalances[_prover][msg.sender] += _amount;
        stakerToProver[msg.sender] = _prover;
        return _amount;
    }

    function permitAndStake(address, address, uint256 _amount, uint256, uint8, bytes32, bytes32)
        external
        pure
        override
        returns (uint256)
    {
        return _amount;
    }

    function requestUnstake(uint256 _stPROVE) external override {
        unstakeClaims[msg.sender].push(
            UnstakeClaim({stPROVE: _stPROVE, iPROVESnapshot: _stPROVE, timestamp: block.timestamp})
        );
    }

    function finishUnstake(address _staker, uint256 _maxClaims)
        external
        override
        returns (uint256)
    {
        // Process all unstake claims for the staker.
        UnstakeClaim[] storage claims = unstakeClaims[_staker];
        uint256 totalAmount = 0;
        uint256 claimsToProcess = claims.length;

        if (_maxClaims > 0 && _maxClaims < claimsToProcess) {
            claimsToProcess = _maxClaims;
        }

        for (uint256 i = 0; i < claimsToProcess; i++) {
            totalAmount += claims[i].iPROVESnapshot;
        }

        // Remove processed claims.
        for (uint256 i = 0; i < claimsToProcess; i++) {
            claims[0] = claims[claims.length - 1];
            claims.pop();
        }

        // Transfer the PROVE tokens to the staker.
        if (totalAmount > 0) {
            address prover = stakerToProver[_staker];
            proverVaultBalances[prover][_staker] -= totalAmount;
            IERC20(prove).transfer(_staker, totalAmount);
        }

        return totalAmount;
    }

    function requestSlash(address _prover, uint256 _iPROVE) external override returns (uint256) {
        uint256 index = slashClaims[_prover].length;
        slashClaims[_prover].push(SlashClaim({iPROVE: _iPROVE, timestamp: block.timestamp}));
        return index;
    }

    function cancelSlash(address _prover, uint256 _index) external override {
        if (_index != slashClaims[_prover].length - 1) {
            slashClaims[_prover][_index] = slashClaims[_prover][slashClaims[_prover].length - 1];
        }
        slashClaims[_prover].pop();
    }

    function finishSlash(address _prover, uint256 _index) external override returns (uint256) {
        uint256 iPROVE = slashClaims[_prover][_index].iPROVE;
        if (_index != slashClaims[_prover].length - 1) {
            slashClaims[_prover][_index] = slashClaims[_prover][slashClaims[_prover].length - 1];
        }
        slashClaims[_prover].pop();
        return iPROVE;
    }

    function dispense(uint256 _amount) external override {
        emit Dispense(_amount);
    }

    function updateDispenseRate(uint256 _newRate) external override {
        uint256 oldRate = dispenseRate;
        dispenseRate = _newRate;
        emit DispenseRateUpdate(oldRate, _newRate);
    }
}
