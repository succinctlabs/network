// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverRegistry} from "./libraries/ProverRegistry.sol";
import {StakedSuccinct} from "./tokens/StakedSuccinct.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {IIntermediateSuccinct} from "./interfaces/IIntermediateSuccinct.sol";
import {IProver} from "./interfaces/IProver.sol";
import {Initializable} from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title SuccinctStaking
/// @author Succinct Labs
/// @notice Manages staking, unstaking, dispensing, and slashing for the Succinct Prover Network.
contract SuccinctStaking is
    Initializable,
    Ownable,
    ProverRegistry,
    StakedSuccinct,
    ISuccinctStaking
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ISuccinctStaking
    address public override dispenser;

    /// @inheritdoc ISuccinctStaking
    uint256 public override minStakeAmount;

    /// @inheritdoc ISuccinctStaking
    uint256 public override maxUnstakeRequests;

    /// @inheritdoc ISuccinctStaking
    uint256 public override unstakePeriod;

    /// @inheritdoc ISuccinctStaking
    uint256 public override slashPeriod;

    /// @inheritdoc ISuccinctStaking
    uint256 public override dispenseRate;

    /// @inheritdoc ISuccinctStaking
    uint256 public override lastDispenseTimestamp;

    /// @dev A mapping from staker to the prover they are staked with.
    mapping(address => address) internal stakerToProver;

    /// @dev A mapping from staker to their unstake claims.
    mapping(address => UnstakeClaim[]) internal unstakeClaims;

    /// @dev A mapping from prover to their slash claims.
    mapping(address => SlashClaim[]) internal slashClaims;

    /*//////////////////////////////////////////////////////////////
                                MODIFIER
    //////////////////////////////////////////////////////////////*/

    modifier onlyDispenser() {
        if (msg.sender != dispenser) revert NotDispenser();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @dev Only the owner is set in the constructor. This is done because other contracts
    ///      (e.g. SuccinctVApp) need a reference to this contract, and this contract needs a
    ///      reference to it. So we deploy this first, then initialize it later.
    constructor(address _owner) Ownable(_owner) {}

    /// @dev We don't do this in the constructor because we must deploy this contract
    ///      first.
    function initialize(
        address _governor,
        address _vApp,
        address _prove,
        address _intermediateProve,
        address _dispenser,
        uint256 _minStakeAmount,
        uint256 _maxUnstakeRequests,
        uint256 _unstakePeriod,
        uint256 _slashPeriod,
        uint256 _dispenseRate
    ) external onlyOwner initializer {
        // Ensure that parameters critical for functionality are non-zero.
        if (
            _governor == address(0) || _vApp == address(0) || _prove == address(0)
                || _intermediateProve == address(0) || _dispenser == address(0)
        ) {
            revert ZeroAddress();
        }
        if (_maxUnstakeRequests == 0 || _unstakePeriod == 0 || _slashPeriod == 0) {
            revert ZeroAmount();
        }

        // Setup the initial state.
        __ProverRegistry_init(_governor, _vApp, _prove, _intermediateProve);
        dispenser = _dispenser;
        minStakeAmount = _minStakeAmount;
        maxUnstakeRequests = _maxUnstakeRequests;
        unstakePeriod = _unstakePeriod;
        slashPeriod = _slashPeriod;

        // Setup the dispense rate.
        _updateDispenseRate(_dispenseRate);
        lastDispenseTimestamp = block.timestamp;

        // Approve the $iPROVE contract to transfer $PROVE from this contract during stake().
        IERC20(prove).approve(iProve, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctStaking
    function stakedTo(address _staker) external view override returns (address) {
        return stakerToProver[_staker];
    }

    /// @inheritdoc ISuccinctStaking
    function staked(address _staker) external view override returns (uint256) {
        // Get the prover that the staker is staked with.
        address prover = stakerToProver[_staker];
        if (prover == address(0)) return 0;

        // Get the amount of $PROVE the staker would get if the staker's full $stPROVE balance was
        // unstaked.
        return previewUnstake(prover, balanceOf(_staker));
    }

    /// @inheritdoc ISuccinctStaking
    function proverStaked(address _prover) public view override returns (uint256) {
        // Get the amount of $iPROVE in the prover.
        uint256 iPROVE = IERC20(iProve).balanceOf(_prover);

        // Get the amount of $PROVE that would be received if the $iPROVE was redeemed.
        return IERC4626(iProve).previewRedeem(iPROVE);
    }

    /// @inheritdoc ISuccinctStaking
    function unstakeRequests(address _staker)
        external
        view
        override
        returns (UnstakeClaim[] memory)
    {
        return unstakeClaims[_staker];
    }

    /// @inheritdoc ISuccinctStaking
    function slashRequests(address _prover) external view override returns (SlashClaim[] memory) {
        return slashClaims[_prover];
    }

    /// @inheritdoc ISuccinctStaking
    function unstakePending(address _staker) external view override returns (uint256) {
        // Get the prover that the staker is staked with.
        address prover = stakerToProver[_staker];
        if (prover == address(0)) return 0;

        // Get the amount of $PROVE that would be received if the pending $stPROVE was redeemed.
        return previewUnstake(prover, _getUnstakeClaimBalance(_staker));
    }

    /// @inheritdoc ISuccinctStaking
    function previewUnstake(address _prover, uint256 _stPROVE)
        public
        view
        override
        returns (uint256)
    {
        // Get the amount of $iPROVE this staker has for this prover.
        uint256 iPROVE = IERC4626(_prover).previewRedeem(_stPROVE);

        // Get the amount of $PROVE that would be received if the $iPROVE was redeemed.
        return IERC4626(iProve).previewRedeem(iPROVE);
    }

    /// @inheritdoc ISuccinctStaking
    function maxDispense() public view override returns (uint256) {
        uint256 elapsedTime = block.timestamp - lastDispenseTimestamp;
        return elapsedTime * dispenseRate;
    }

    /*//////////////////////////////////////////////////////////////
                                 CORE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctStaking
    function stake(address _prover, uint256 _PROVE)
        external
        override
        onlyForProver(_prover)
        returns (uint256)
    {
        // Transfer $PROVE from the staker to this contract.
        IERC20(prove).safeTransferFrom(msg.sender, address(this), _PROVE);

        return _stake(msg.sender, _prover, _PROVE);
    }

    /// @inheritdoc ISuccinctStaking
    function permitAndStake(
        address _prover,
        address _from,
        uint256 _PROVE,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override onlyForProver(_prover) returns (uint256) {
        // If the $PROVE allowance is not equal to the amount being staked, permit the prover to
        // spend the $PROVE from the staker.
        if (IERC20(prove).allowance(_from, _prover) != _PROVE) {
            IERC20Permit(prove).permit(_from, _prover, _PROVE, _deadline, _v, _r, _s);
        }

        // Transfer $PROVE from the staker to this contract, by utilizing the prover as the
        // spender.
        IProver(_prover).transferProveToStaking(_from, _PROVE);

        return _stake(_from, _prover, _PROVE);
    }

    /// @inheritdoc ISuccinctStaking
    function requestUnstake(uint256 _stPROVE) external override {
        // Ensure unstaking a non-zero amount.
        if (_stPROVE == 0) revert ZeroAmount();

        // Get the prover that the staker is staked with.
        address prover = stakerToProver[msg.sender];
        if (prover == address(0)) revert NotStaked();

        // Check that this staker has not already requested too many unstake requests.
        if (unstakeClaims[msg.sender].length >= maxUnstakeRequests) revert TooManyUnstakeRequests();

        // Check that this prover is not in the process of being slashed.
        if (slashClaims[prover].length > 0) revert ProverHasSlashRequest();

        // Get the amount of $stPROVE this staker currently has.
        uint256 stPROVEBalance = balanceOf(msg.sender);

        // Get the amount $stPROVE this staker has in pending unstake claims.
        uint256 stPROVEClaim = _getUnstakeClaimBalance(msg.sender);

        // Check that this staker has enough $stPROVE to unstake this amount.
        if (stPROVEBalance < stPROVEClaim + _stPROVE) revert InsufficientStakeBalance();

        // Get the amount of $iPROVE that would be received if the specified $stPROVE was redeemed.
        uint256 iPROVESnapshot = IERC4626(prover).previewRedeem(_stPROVE);

        // Create a claim to unstake $stPROVE from the prover for the specified amount.
        unstakeClaims[msg.sender].push(
            UnstakeClaim({
                stPROVE: _stPROVE,
                iPROVESnapshot: iPROVESnapshot,
                timestamp: block.timestamp
            })
        );

        emit UnstakeRequest(msg.sender, prover, _stPROVE, iPROVESnapshot);
    }

    /// @inheritdoc ISuccinctStaking
    function finishUnstake(address _staker) external override returns (uint256 PROVE) {
        // Get the prover that the staker is staked with.
        address prover = stakerToProver[_staker];
        if (prover == address(0)) revert NotStaked();

        // Get the unstake claims for this staker.
        UnstakeClaim[] storage claims = unstakeClaims[_staker];
        if (claims.length == 0) revert NoUnstakeRequests();

        // Check that this prover is not in the process of being slashed.
        if (slashClaims[prover].length > 0) revert ProverHasSlashRequest();

        // Process the available unstake claims.
        PROVE += _finishUnstake(_staker, prover, claims);

        // If the staker has no remaining balance with this prover, remove the staker's delegate.
        // This allows them to choose a different prover if they stake again.
        if (balanceOf(_staker) == 0) {
            // Remove the staker's prover delegation.
            stakerToProver[_staker] = address(0);

            emit ProverUnbound(_staker, prover);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              AUTHORIZED
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctStaking
    function requestSlash(address _prover, uint256 _iPROVE)
        external
        override
        onlyVApp
        onlyForProver(_prover)
        returns (uint256 index)
    {
        // Ensure slashing a non-zero amount.
        if (_iPROVE == 0) revert ZeroAmount();

        // Create the slash claim.
        index = slashClaims[_prover].length;
        slashClaims[_prover].push(SlashClaim({iPROVE: _iPROVE, timestamp: block.timestamp}));

        emit SlashRequest(_prover, _iPROVE, index);
    }

    /// @inheritdoc ISuccinctStaking
    function cancelSlash(address _prover, uint256 _index)
        external
        override
        onlyOwner
        onlyForProver(_prover)
    {
        // Get the amount of $iPROVE.
        uint256 iPROVE = slashClaims[_prover][_index].iPROVE;

        // Delete the claim.
        if (_index != slashClaims[_prover].length - 1) {
            slashClaims[_prover][_index] = slashClaims[_prover][slashClaims[_prover].length - 1];
        }
        slashClaims[_prover].pop();

        emit SlashCancel(_prover, iPROVE, _index);
    }

    /// @inheritdoc ISuccinctStaking
    function finishSlash(address _prover, uint256 _index)
        external
        override
        onlyOwner
        onlyForProver(_prover)
        returns (uint256 iPROVE)
    {
        // Get the slash claim.
        SlashClaim storage claim = slashClaims[_prover][_index];

        // Ensure that the time has passed since the claim was created.
        if (block.timestamp < claim.timestamp + slashPeriod) revert SlashNotReady();

        // Determine how much can actually be slashed (cannot exceed the prover's current balance).
        uint256 iPROVEBalance = IERC20(iProve).balanceOf(_prover);
        iPROVE = claim.iPROVE > iPROVEBalance ? iPROVEBalance : claim.iPROVE;

        // Delete the claim.
        if (_index != slashClaims[_prover].length - 1) {
            slashClaims[_prover][_index] = slashClaims[_prover][slashClaims[_prover].length - 1];
        }
        slashClaims[_prover].pop();

        // Burn the $iPROVE and underlying $PROVE. This reduces the stake of the prover and all
        // of its stakers proportionally.
        uint256 PROVE = 0;
        if (iPROVE > 0) {
            PROVE = IIntermediateSuccinct(iProve).burn(_prover, iPROVE);
        }

        emit Slash(_prover, PROVE, iPROVE, _index);
    }

    /// @inheritdoc ISuccinctStaking
    function dispense(uint256 _PROVE) external override onlyDispenser {
        // Get the maximum amount of $PROVE that can be dispensed.
        uint256 available = maxDispense();

        // If caller passed in type(uint256).max, attempt to dispense the full available amount.
        uint256 amount = _PROVE == type(uint256).max ? available : _PROVE;

        // Ensure dispensing a non‐zero amount.
        if (amount == 0) revert ZeroAmount();

        // If caller passed a specific number, make sure it doesn't exceed available
        if (amount > available) revert AmountExceedsAvailableDispense();

        // Update the timestamp based on the (possibly‐adjusted) amount
        uint256 timeConsumed = (amount + dispenseRate - 1) / dispenseRate;
        lastDispenseTimestamp += timeConsumed;

        // Transfer the amount to the iPROVE vault. This distributes the $PROVE to all stakers.
        IERC20(prove).safeTransfer(iProve, amount);

        emit Dispense(amount);
    }

    /// @inheritdoc ISuccinctStaking
    function setDispenser(address _dispenser) external override onlyOwner {
        _setDispenser(_dispenser);
    }

    /// @inheritdoc ISuccinctStaking
    function updateDispenseRate(uint256 _rate) external override onlyOwner {
        _updateDispenseRate(_rate);
    }

    /*//////////////////////////////////////////////////////////////
                               INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Deposit a staker's $PROVE to mint $iPROVE, then deposit $iPROVE to mint $PROVER-N, and
    ///      then directly mint $stPROVE to the staker, which acts as the receipt token for staking.
    function _stake(address _staker, address _prover, uint256 _PROVE)
        internal
        stakingOperation
        returns (uint256 stPROVE)
    {
        // Ensure staking a non-zero amount.
        if (_PROVE == 0) revert ZeroAmount();

        // Ensure the staking amount is greater than the minimum stake amount.
        if (_PROVE < minStakeAmount) revert StakeBelowMinimum();

        // Check that this prover is not in the process of being slashed.
        if (slashClaims[_prover].length > 0) revert ProverHasSlashRequest();

        // Ensure the staker is not already staked with a different prover.
        address existingProver = stakerToProver[_staker];
        if (existingProver != address(0) && existingProver != _prover) {
            revert AlreadyStakedWithDifferentProver(existingProver);
        }

        // Set the prover as the staker's delegate.
        if (existingProver == address(0)) {
            stakerToProver[_staker] = _prover;

            emit ProverBound(_staker, _prover);
        }

        // Deposit $PROVE to mint $iPROVE, sending it to this contract.
        uint256 iPROVE = IERC4626(iProve).deposit(_PROVE, address(this));

        // Ensure this contract received non-zero $iPROVE.
        if (iPROVE == 0) revert ZeroReceiptAmount();

        // Deposit $iPROVE to mint $PROVER-N, sending it to this contract.
        // Note: The $stPROVE variable is used because it is 1:1 with the received $PROVER-N.
        stPROVE = IERC4626(_prover).deposit(iPROVE, address(this));

        // Ensure this contract received non-zero $PROVER-N.
        if (stPROVE == 0) revert ZeroReceiptAmount();

        // Mint $stPROVE to the staker as a receipt token representing their ownership of $PROVER-N.
        _mint(_staker, stPROVE);

        emit Stake(_staker, _prover, _PROVE, iPROVE, stPROVE);
    }

    /// @dev Burn a staker's $stPROVE and withdraw $PROVER-N to receive $iPROVE, then withdraw
    ///      $iPROVE to receive $PROVE, which gets sent to the staker.
    ///
    ///      The actual $iPROVE withdrawn is adjusted to ensure that prover rewards earned during the
    ///      unstaking period do not go to the staker, while ensuring that slashing that occurs during
    ///      the unstaking period does. This is implemented as follows:
    ///      - If received $iPROVE > snapshot $iPROVE: Rewards were earned during unstaking, so the
    ///        staker redeems only the snapshot amount, and the excess is returned to the prover.
    ///      - If received $iPROVE < snapshot $iPROVE: Slashing occurred during unstaking, so the
    ///        staker redeems the lower amount (received $iPROVE), bearing the loss from slashing.
    function _unstake(address _staker, address _prover, uint256 _stPROVE, uint256 _iPROVESnapshot)
        internal
        returns (uint256 PROVE)
    {
        // Ensure unstaking a non-zero amount.
        if (_stPROVE == 0) revert ZeroAmount();

        // Burn the $stPROVE from the staker
        _burn(_staker, _stPROVE);

        // Withdraw $PROVER-N from this contract to have this contract receive $iPROVE.
        uint256 iPROVEReceived = IERC4626(_prover).redeem(_stPROVE, address(this), address(this));

        // Determine how much $iPROVE to redeem for the staker based on rewards or slashing.
        uint256 iPROVE;
        if (iPROVEReceived > _iPROVESnapshot) {
            // Rewards were earned during unstaking. Return the excess to the prover.
            uint256 excess = iPROVEReceived - _iPROVESnapshot;
            IERC20(iProve).safeTransfer(_prover, excess);
            iPROVE = _iPROVESnapshot;
        } else {
            // Either no change or slashing occurred. Staker gets what's available.
            iPROVE = iPROVEReceived;
        }

        // Withdraw $iPROVE from this contract to have the staker receive $PROVE.
        PROVE = IERC4626(iProve).redeem(iPROVE, _staker, address(this));

        emit Unstake(_staker, _prover, PROVE, iPROVE, _stPROVE);
    }

    /// @dev Iterate over the unstake claims, processing each one that has passed the unstake
    ///      period.
    function _finishUnstake(address _staker, address _prover, UnstakeClaim[] storage _claims)
        internal
        stakingOperation
        returns (uint256 PROVE)
    {
        uint256 i = 0;
        while (i < _claims.length) {
            if (block.timestamp >= _claims[i].timestamp + unstakePeriod) {
                // Store claim before modifying the array.
                UnstakeClaim memory claim = _claims[i];

                // Swap with the last element and pop.
                _claims[i] = _claims[_claims.length - 1];
                _claims.pop();

                // Process the unstake.
                PROVE += _unstake(_staker, _prover, claim.stPROVE, claim.iPROVESnapshot);
            } else {
                i++;
            }
        }
    }

    /// @dev Get the $stPROVE sum of all unstake claims for a staker.
    function _getUnstakeClaimBalance(address _staker) internal view returns (uint256 stPROVE) {
        for (uint256 i = 0; i < unstakeClaims[_staker].length; i++) {
            stPROVE += unstakeClaims[_staker][i].stPROVE;
        }
    }

    /// @dev set the new dispenser
    function _setDispenser(address _dispenser) internal {
        emit DispenserUpdate(dispenser, _dispenser);

        dispenser = _dispenser;
    }

    /// @dev Set the new dispense rate.
    function _updateDispenseRate(uint256 _dispenseRate) internal {
        emit DispenseRateUpdate(dispenseRate, _dispenseRate);

        dispenseRate = _dispenseRate;
    }
}
