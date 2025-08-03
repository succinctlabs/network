// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProverRegistry} from "./libraries/ProverRegistry.sol";
import {StakedSuccinct} from "./tokens/StakedSuccinct.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {IIntermediateSuccinct} from "./interfaces/IIntermediateSuccinct.sol";
import {IProver} from "./interfaces/IProver.sol";
import {SuccinctGovernor} from "./SuccinctGovernor.sol";
import {Initializable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {UUPSUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title SuccinctStaking
/// @author Succinct Labs
/// @notice Manages staking, unstaking, dispensing, and slashing for the Succinct Prover Network.
contract SuccinctStaking is
    Initializable,
    OwnableUpgradeable,
    ProverRegistry,
    StakedSuccinct,
    UUPSUpgradeable,
    ISuccinctStaking
{
    using SafeERC20 for IERC20;

    /// @dev Fixed‑point base used for slash‑factor math.
    ///
    ///      This allows for the multiplication of two 1e27‑scaled values without
    ///      overflowing 256 bits while keeping sub‑wei precision.
    uint256 internal constant SCALAR = 1e27;

    /// @inheritdoc ISuccinctStaking
    address public override dispenser;

    /// @inheritdoc ISuccinctStaking
    uint256 public override minStakeAmount;

    /// @inheritdoc ISuccinctStaking
    uint256 public override maxUnstakeRequests;

    /// @inheritdoc ISuccinctStaking
    uint256 public override unstakePeriod;

    /// @inheritdoc ISuccinctStaking
    uint256 public override slashCancellationPeriod;

    /// @inheritdoc ISuccinctStaking
    uint256 public override dispenseRate;

    /// @inheritdoc ISuccinctStaking
    uint256 public override dispenseRateTimestamp;

    /// @inheritdoc ISuccinctStaking
    uint256 public override dispenseEarned;

    /// @inheritdoc ISuccinctStaking
    uint256 public override dispenseDistributed;

    /// @dev A mapping from staker to the prover they are staked with.
    mapping(address => address) internal stakerToProver;

    /// @dev A mapping from staker to their unstake claims.
    mapping(address => UnstakeClaim[]) internal unstakeClaims;

    /// @dev A mapping from prover to their slash claims.
    mapping(address => SlashClaim[]) internal slashClaims;

    /// @dev A mapping from prover to their unresolved slash claim count.
    mapping(address => uint256) internal slashClaimCount;

    /// @dev A mapping from prover to their unstaking escrow pool.
    mapping(address => EscrowPool) internal escrowPools;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev We don't do this in the constructor because we must deploy this contract
    ///      first.
    function initialize(
        address _owner,
        address _governor,
        address _vApp,
        address _prove,
        address _intermediateProve,
        address _dispenser,
        uint256 _minStakeAmount,
        uint256 _maxUnstakeRequests,
        uint256 _unstakePeriod,
        uint256 _slashCancellationPeriod
    ) external initializer {
        // Ensure that parameters critical for functionality are non-zero.
        _requireNonZeroAddress(_owner);
        _requireNonZeroAddress(_governor);
        _requireNonZeroAddress(_vApp);
        _requireNonZeroAddress(_prove);
        _requireNonZeroAddress(_intermediateProve);
        _requireNonZeroAddress(_dispenser);
        _requireNonZeroNumber(_maxUnstakeRequests);
        _requireNonZeroNumber(_unstakePeriod);
        _requireNonZeroNumber(_slashCancellationPeriod);

        // Setup the initial state.
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        __StakedSuccinct_init();
        __ProverRegistry_init(_governor, _vApp, _prove, _intermediateProve);
        dispenser = _dispenser;
        minStakeAmount = _minStakeAmount;
        maxUnstakeRequests = _maxUnstakeRequests;
        unstakePeriod = _unstakePeriod;
        slashCancellationPeriod = _slashCancellationPeriod;

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
    function escrowPool(address _prover) external view override returns (EscrowPool memory) {
        return escrowPools[_prover];
    }

    /// @inheritdoc ISuccinctStaking
    function unstakePending(address _staker) external view override returns (uint256 PROVE) {
        // Get the prover that the staker is staked with.
        address prover = stakerToProver[_staker];
        if (prover == address(0)) return 0;

        // Calculate the pending $PROVE by iterating through claims and applying slash factor.
        UnstakeClaim[] memory claims = unstakeClaims[_staker];
        EscrowPool memory pool = escrowPools[prover];

        // If everything has been slashed to zero no claim can redeem anything.
        uint256 currentFactor = pool.slashFactor;
        if (currentFactor == 0) return 0;

        for (uint256 i = 0; i < claims.length; i++) {
            // Apply cumulative slash factor to the escrowed $iPROVE.
            uint256 iPROVEScaled =
                Math.mulDiv(claims[i].iPROVEEscrow, currentFactor, claims[i].slashFactor);
            // Convert $iPROVE to $PROVE.
            PROVE += IERC4626(iProve).previewRedeem(iPROVEScaled);
        }
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
        // The total earned is the historical accrual plus the current period earnings.
        uint256 totalEarned =
            dispenseEarned + (block.timestamp - dispenseRateTimestamp) * dispenseRate;

        // The maximum amount that can currently be dispensed is the total amount earned minus the
        // amount already dispensed.
        return totalEarned - dispenseDistributed;
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
    function requestUnstake(uint256 _stPROVE) external override stakingOperation {
        // Ensure unstaking a non-zero amount.
        _requireNonZeroNumber(_stPROVE);

        // Get the prover that the staker is staked with.
        address prover = stakerToProver[msg.sender];
        if (prover == address(0)) revert NotStaked();

        // Check that this staker has not already requested too many unstake requests.
        if (unstakeClaims[msg.sender].length >= maxUnstakeRequests) revert TooManyUnstakeRequests();

        // Check that this prover is not in the process of being slashed.
        _requireProverWithoutSlashRequests(prover);

        // Get the amount of $stPROVE this staker currently has.
        uint256 stPROVEBalance = balanceOf(msg.sender);

        // Check that this staker has enough $stPROVE to unstake this amount.
        if (stPROVEBalance < _stPROVE) revert InsufficientStakeBalance();

        // Escrow the $iPROVE.
        uint256 iPROVEEscrow = _escrowUnstakeRequest(msg.sender, prover, _stPROVE);

        // Get the prover's escrow pool.
        EscrowPool storage pool = escrowPools[prover];

        // If the escrow pool hasn't been initialized yet (or a prover was fully slashed),
        // set the slash factor to the starting value.
        if (pool.slashFactor == 0) pool.slashFactor = SCALAR;

        // Update the prover's escrow pool to account for the new escrowed $iPROVE.
        pool.iPROVEEscrow += iPROVEEscrow;

        // Record the unstake request.
        unstakeClaims[msg.sender].push(
            UnstakeClaim({
                iPROVEEscrow: iPROVEEscrow,
                slashFactor: pool.slashFactor,
                timestamp: block.timestamp
            })
        );

        emit UnstakeRequest(msg.sender, prover, _stPROVE, iPROVEEscrow);
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
        _requireProverWithoutSlashRequests(prover);

        // Process the available unstake claims.
        PROVE += _finishUnstake(_staker, prover, claims);

        // Reset the slash factor if all $iPROVE has been removed.
        EscrowPool storage pool = escrowPools[prover];
        if (pool.iPROVEEscrow == 0 && pool.slashFactor != SCALAR) {
            pool.slashFactor = SCALAR;
        }

        // If the staker has no remaining balance and no pending unstakes, remove the staker's
        // delegate. This allows them to choose a different prover if they stake again.
        if (balanceOf(_staker) == 0 && claims.length == 0) {
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
        _requireNonZeroNumber(_iPROVE);

        // Create the slash claim.
        index = slashClaims[_prover].length;
        slashClaims[_prover].push(
            SlashClaim({iPROVE: _iPROVE, timestamp: block.timestamp, resolved: false})
        );

        // Increment the unresolved claim counter.
        unchecked {
            ++slashClaimCount[_prover];
        }

        emit SlashRequest(_prover, _iPROVE, index);
    }

    /// @inheritdoc ISuccinctStaking
    function cancelSlash(address _prover, uint256 _index)
        external
        override
        onlyForProver(_prover)
    {
        // Get the slash claim.
        SlashClaim storage claim = slashClaims[_prover][_index];

        // Ensure the claim hasn't already been resolved.
        if (claim.resolved) revert SlashRequestAlreadyResolved();

        // Calculate the deadline for cancellation. Must be after the slash cancellation period
        // and governance latency has passed. This ensures that governance has had adequate time
        // to execute a proposal to call `finishSlash()`.
        uint256 votingDelay = SuccinctGovernor(payable(governor)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(governor)).votingPeriod();
        uint256 cancelDeadline =
            claim.timestamp + slashCancellationPeriod + votingDelay + votingPeriod;

        // Check if the deadline has passed.
        if (block.timestamp < cancelDeadline) revert SlashRequestNotReadyToCancel();

        // Mark the claim as resolved.
        claim.resolved = true;

        // Decrement the unresolved claim counter.
        unchecked {
            --slashClaimCount[_prover];
        }

        emit SlashCancel(_prover, claim.iPROVE, _index);
    }

    /// @inheritdoc ISuccinctStaking
    function finishSlash(address _prover, uint256 _index)
        external
        override
        onlyOwner
        onlyForProver(_prover)
        returns (uint256 iPROVEBurned)
    {
        // Get the slash claim.
        SlashClaim storage claim = slashClaims[_prover][_index];

        // Ensure the claim hasn't already been resolved.
        if (claim.resolved) revert SlashRequestAlreadyResolved();

        // Determine how much can actually be slashed (cannot exceed the prover's current balance).
        uint256 iPROVEBalance = IERC20(iProve).balanceOf(_prover);

        // Get the prover's escrow pool to include escrowed funds in total.
        EscrowPool storage pool = escrowPools[_prover];
        uint256 iPROVETotal = iPROVEBalance + pool.iPROVEEscrow;
        uint256 iPROVEToSlash = claim.iPROVE > iPROVETotal ? iPROVETotal : claim.iPROVE;

        // Mark the claim as resolved.
        claim.resolved = true;

        // Decrement the unresolved claim counter.
        unchecked {
            --slashClaimCount[_prover];
        }

        uint256 PROVEBurned = 0;
        iPROVEBurned = 0;
        if (iPROVEToSlash > 0) {
            // Pro‑rata split between vault and escrow.
            uint256 burnFromEscrow = Math.mulDiv(iPROVEToSlash, pool.iPROVEEscrow, iPROVETotal);
            uint256 burnFromVault = iPROVEToSlash - burnFromEscrow;

            // Burn in escrow.
            if (burnFromEscrow != 0) {
                pool.iPROVEEscrow -= burnFromEscrow;
                PROVEBurned += IIntermediateSuccinct(iProve).burn(address(this), burnFromEscrow);
                iPROVEBurned += burnFromEscrow;
            }

            // Burn in vault.
            if (burnFromVault != 0) {
                PROVEBurned += IIntermediateSuccinct(iProve).burn(_prover, burnFromVault);
                iPROVEBurned += burnFromVault;
            }

            // Update the prover's slash factor.
            uint256 iPROVERemaining = iPROVETotal - iPROVEToSlash;
            if (iPROVERemaining == 0) {
                // If there is nothing left to slash, set the slash factor to 0.
                pool.slashFactor = 0;
            } else {
                // If there is something left to slash, update the slash factor to the new ratio.
                uint256 ratio = Math.mulDiv(iPROVERemaining, SCALAR, iPROVETotal);
                if (pool.slashFactor == 0) pool.slashFactor = SCALAR;
                pool.slashFactor = Math.mulDiv(pool.slashFactor, ratio, SCALAR);
            }
        }

        emit Slash(_prover, PROVEBurned, iPROVEBurned, _index);

        // If the slashing caused the price-per-share to drop below the minimum, deactivate the
        // prover.
        _deactivateProverIfPriceBelowMin(_prover);
    }

    /// @inheritdoc ISuccinctStaking
    function dispense(uint256 _PROVE) external override onlyDispenser {
        // Get the maximum amount of $PROVE that can be dispensed.
        uint256 available = maxDispense();

        // If caller passed in type(uint256).max, attempt to dispense the full available amount.
        uint256 amount = _PROVE == type(uint256).max ? available : _PROVE;

        // Ensure dispensing a non-zero amount.
        _requireNonZeroNumber(amount);

        // If caller passed a specific number, make sure it doesn't exceed available.
        if (amount > available) revert AmountExceedsAvailableDispense();

        // Update the total dispensed amount.
        dispenseDistributed += amount;

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
        _requireNonZeroNumber(_PROVE);

        // Ensure the staking amount is greater than the minimum stake amount.
        if (_PROVE < minStakeAmount) revert StakeBelowMinimum();

        // Check that this prover is active.
        if (deactivatedProvers[_prover]) revert ProverNotActive();

        // Check that this prover is not in the process of being slashed.
        _requireProverWithoutSlashRequests(_prover);

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

    /// @dev Burn a staker's $stPROVE and withdraw $PROVER-N to receive $iPROVE.
    function _escrowUnstakeRequest(address _staker, address _prover, uint256 _stPROVE)
        internal
        returns (uint256 iPROVE)
    {
        // Burn the $stPROVE from the staker.
        _burn(_staker, _stPROVE);

        // Withdraw $PROVER-N from this contract to receive $iPROVE.
        // Note: This can return 0 if the prover has been fully slashed.
        iPROVE = IERC4626(_prover).redeem(_stPROVE, address(this), address(this));
    }

    /// @dev Withdraw the escrowed $iPROVE to receive $PROVE, which gets sent to the staker.
    function _finishUnstakeRequest(address _staker, address _prover, UnstakeClaim memory _claim)
        internal
        returns (uint256 PROVE)
    {
        // Get the prover's escrow pool.
        EscrowPool storage pool = escrowPools[_prover];

        // Apply cumulative slash factor to the escrowed $iPROVE.
        uint256 iPROVEScaled =
            Math.mulDiv(_claim.iPROVEEscrow, pool.slashFactor, _claim.slashFactor);

        // Clamp to the pool’s remaining balance (protects against rounding).
        if (iPROVEScaled > pool.iPROVEEscrow) {
            iPROVEScaled = pool.iPROVEEscrow;
        }

        // If there is $iPROVE left to redeem, update the escrow pool and redeem.
        if (iPROVEScaled != 0) {
            unchecked {
                pool.iPROVEEscrow -= iPROVEScaled;
            }

            // Withdraw $iPROVE from this contract to have the staker receive $PROVE.
            PROVE = IERC4626(iProve).redeem(iPROVEScaled, _staker, address(this));
        }

        emit Unstake(_staker, _prover, PROVE, iPROVEScaled);
    }

    /// @dev Iterate over the unstake claims, processing each one that has passed the unstake
    ///      period.
    function _finishUnstake(address _staker, address _prover, UnstakeClaim[] storage _claims)
        internal
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
                PROVE += _finishUnstakeRequest(_staker, _prover, claim);
            } else {
                i++;
            }
        }
    }

    /// @dev Set the new dispenser.
    function _setDispenser(address _dispenser) internal {
        emit DispenserUpdate(dispenser, _dispenser);

        dispenser = _dispenser;
    }

    /// @dev Set the new dispense rate.
    function _updateDispenseRate(uint256 _dispenseRate) internal {
        // Accrue all earnings up to this point at the old rate.
        dispenseEarned += (block.timestamp - dispenseRateTimestamp) * dispenseRate;

        // Update the timestamp to mark this new rate taking effect. All time before this timestamp
        // uses the old rate (already accrued above), and all time after uses the new rate.
        dispenseRateTimestamp = block.timestamp;

        emit DispenseRateUpdate(dispenseRate, _dispenseRate);

        dispenseRate = _dispenseRate;
    }

    /// @dev Thrown if a zero address is passed.
    function _requireNonZeroAddress(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    /// @dev Thrown if a zero number is passed.
    function _requireNonZeroNumber(uint256 _number) internal pure {
        if (_number == 0) revert ZeroAmount();
    }

    /// @dev Validates that a prover has no pending slash requests.
    function _requireProverWithoutSlashRequests(address _prover) private view {
        if (slashClaimCount[_prover] > 0) revert ProverHasSlashRequest();
    }

    /// @dev Authorizes an ERC1967 proxy upgrade to a new implementation contract.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
