// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {IProverRegistry} from "../interfaces/IProverRegistry.sol";

contract MockStaking is ISuccinctStaking {
    address public PROVE;
    address public vapp;
    uint256 public minStakeAmount;
    uint256 public unstakePeriod;
    uint256 public slashPeriod;
    uint256 public dispenseRate;
    uint256 public lastDispenseTimestamp;

    // IProverRegistry state
    address public iprove;
    uint256 public proverCounter;
    mapping(address => address) public proverToOwner;
    mapping(address => address) public ownerToProver;

    mapping(address => bool) public isProverVault;
    mapping(address => mapping(address => uint256)) public proverVaultBalances;
    mapping(address => bool) public provers;
    mapping(address => bool) internal _isProver;
    mapping(address => address) internal stakerToProver;
    mapping(address => UnstakeClaim[]) internal unstakeClaims;
    mapping(address => SlashClaim[]) internal slashClaims;

    constructor(address _prove) {
        PROVE = _prove;
    }

    function setVApp(address _vapp) external {
        vapp = _vapp;
    }

    // IProverRegistry implementation
    function prove() external view override returns (address) {
        return PROVE;
    }

    function iProve() external view override returns (address) {
        return iprove;
    }

    function proverCount() external view override returns (uint256) {
        return proverCounter;
    }

    function ownerOf(address _prover) external view override returns (address) {
        return proverToOwner[_prover];
    }

    function getProver(address _owner) external view override returns (address) {
        return ownerToProver[_owner];
    }

    function createProver(uint256) external override returns (address) {
        proverToOwner[msg.sender] = msg.sender;
        ownerToProver[msg.sender] = msg.sender;
        proverCounter++;
        return msg.sender;
    }

    // ISuccinctStaking implementation
    function hasProver(address _account) public view override returns (bool) {
        return provers[_account];
    }

    function setHasProver(address _account, bool _status) external {
        provers[_account] = _status;
    }

    function isProver(address _account) public view override returns (bool) {
        return _isProver[_account];
    }

    function setIsProver(address _account, bool _status) external {
        _isProver[_account] = _status;
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

    function stake(address _prover, uint256 _amount) external override returns (uint256) {
        IERC20(PROVE).transferFrom(msg.sender, address(this), _amount);
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
            UnstakeClaim({stPROVE: _stPROVE, timestamp: block.timestamp})
        );
    }

    function finishUnstake() external pure override returns (uint256) {
        return 0;
    }

    function reward(address _prover, uint256 _amount) external override {
        // Verify caller is VApp
        require(msg.sender == vapp, "Not authorized");
        // Note: The VApp has already transferred the staker reward amount to this contract
        // In a real staking contract, this would distribute rewards to stakers
        // For the mock, we just emit the event to indicate the reward was processed
        emit Reward(_prover, _amount);
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
