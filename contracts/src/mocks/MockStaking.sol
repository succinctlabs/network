// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {ProverRegistry} from "../libraries/ProverRegistry.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStaking is ProverRegistry, ISuccinctStaking {
    using SafeERC20 for IERC20;

    address public dispenser;
    uint256 public minStakeAmount;
    uint256 public maxUnstakeRequests;
    uint256 public unstakePeriod;
    uint256 public slashCancellationPeriod;
    uint256 public dispenseRate;
    uint256 public dispenseRateTimestamp;
    uint256 public dispenseEarned;
    uint256 public dispenseDistributed;

    mapping(address => address) internal stakerToProver;
    mapping(address => mapping(address => uint256)) internal proverVaultBalances;
    mapping(address => UnstakeClaim[]) internal unstakeClaims;
    mapping(address => SlashClaim[]) internal slashClaims;
    mapping(address => EscrowPool) internal escrowPools;

    constructor(
        address _governor,
        address _vapp,
        address _prove,
        address _iProve,
        address _dispenser
    ) {
        __ProverRegistry_init(_governor, _vapp, _prove, _iProve);
        dispenser = _dispenser;
    }

    function setDispenser(address _dispenser) external {
        dispenser = _dispenser;
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

    function escrowPool(address _prover) external view override returns (EscrowPool memory) {
        return escrowPools[_prover];
    }

    function unstakePending(address) external pure override returns (uint256) {
        return 0;
    }

    function previewUnstake(address, uint256) public pure override returns (uint256 amount) {
        return amount;
    }

    function maxDispense() public pure override returns (uint256) {
        return 0;
    }

    function createProver(address _owner, uint256 _stakerFeeBips) external returns (address) {
        return _deployProver(_owner, _stakerFeeBips);
    }

    function stake(address _prover, uint256 _amount) external override returns (uint256) {
        IERC20(prove).safeTransferFrom(msg.sender, address(this), _amount);
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
        address prover = stakerToProver[msg.sender];
        EscrowPool storage pool = escrowPools[prover];
        if (pool.slashFactor == 0) pool.slashFactor = 1e27;

        unstakeClaims[msg.sender].push(
            UnstakeClaim({
                iPROVEEscrow: _stPROVE,
                slashFactor: pool.slashFactor,
                timestamp: block.timestamp
            })
        );

        // Update escrow pool
        pool.iPROVEEscrow += _stPROVE;
    }

    function finishUnstake(address) external pure override returns (uint256) {
        return 0;
    }

    function requestSlash(address _prover, uint256 _iPROVE) external override returns (uint256) {
        uint256 index = slashClaims[_prover].length;
        slashClaims[_prover].push(
            SlashClaim({iPROVE: _iPROVE, timestamp: block.timestamp, resolved: false})
        );
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
