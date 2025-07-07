// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProverRegistry} from "./IProverRegistry.sol";

interface ISuccinctStaking is IProverRegistry {
    /// @dev Represents a claim for unstaking some amount of $stPROVE.
    /// @param stPROVE The requested amount of $stPROVE to unstake.
    /// @param iPROVESnapshot The expected $iPROVE to be received at time of unstake request.
    /// @param timestamp The timestamp when the unstake was requested. Used for comparing against
    ///        the `unstakePeriod()` to determine if the claim can be finished.
    struct UnstakeClaim {
        uint256 stPROVE;
        uint256 iPROVESnapshot;
        uint256 timestamp;
    }

    /// @dev Represents a claim to slash a prover for some amount of $iPROVE.
    /// @param iPROVE The requested amount of $iPROVE to slash.
    /// @param timestamp The timestamp when the slash was requested. Used for comparing against
    ///        the `slashPeriod()` to determine if the claim can be finished.
    struct SlashClaim {
        uint256 iPROVE;
        uint256 timestamp;
    }

    /// @dev Emitted when a staker first stakes to their delegated prover. This indicates that any
    ///      additional stake from the staker can only be added to this prover, unless unbound.
    event ProverBound(address indexed staker, address indexed prover);

    /// @dev Emitted when a staker fully unstakes from their delegated prover. This indicates that
    ///      the staker can now stake to a different prover.
    event ProverUnbound(address indexed staker, address indexed prover);

    /// @dev Emitted when a staker stakes into a prover.
    event Stake(
        address indexed staker,
        address indexed prover,
        uint256 PROVE,
        uint256 iPROVE,
        uint256 stPROVE
    );

    /// @dev Emitted when a staker requests to unstake $stPROVE from a prover.
    event UnstakeRequest(
        address indexed staker, address indexed prover, uint256 stPROVE, uint256 iPROVESnapshot
    );

    /// @dev Emitted when a staker unstakes from a prover.
    event Unstake(
        address indexed staker,
        address indexed prover,
        uint256 PROVE,
        uint256 iPROVE,
        uint256 stPROVE
    );

    /// @dev Emitted when a $PROVE reward is distributed to a prover.
    event Reward(address indexed prover, uint256 PROVE);

    /// @dev Emitted when a prover is requested to be slashed.
    event SlashRequest(address indexed prover, uint256 iPROVE, uint256 index);

    /// @dev Emitted when a prover slash request is canceled.
    event SlashCancel(address indexed prover, uint256 iPROVE, uint256 index);

    /// @dev Emitted when a prover slash request is executed.
    event Slash(address indexed prover, uint256 PROVE, uint256 iPROVE, uint256 index);

    /// @dev Emitted when stakers are dispensed $PROVE.
    event Dispense(uint256 PROVE);

    /// @dev Emitted when the dispenser is updated.
    event DispenserUpdate(address oldDispenser, address newDispenser);

    /// @dev Emitted when the dispense rate is updated.
    event DispenseRateUpdate(uint256 oldDispenseRate, uint256 newDispenseRate);

    /// @dev Thrown if the staker has insufficient balance to unstake, or if attempting to slash
    ///      more than the prover has.
    error InsufficientStakeBalance();

    /// @dev Thrown if the staker tries to unstake while not staked with the prover.
    error NotStaked();

    /// @dev Thrown if the staker tries to unstake while there is no unstake requests.
    error NoUnstakeRequests();

    /// @dev Thrown if the staker tries to unstake while they already have too many unstake
    ///      requests.
    error TooManyUnstakeRequests();

    /// @dev Thrown if the staker tries to stake or unstake a zero amount.
    error ZeroAmount();

    /// @dev Thrown if staking would result in a receipt token with a zero amount.
    error ZeroReceiptAmount();

    /// @dev Thrown if the staker tries to stake less than the minimum stake amount.
    error StakeBelowMinimum();

    /// @dev Thrown if the staker tries to deposit while already staked with a different prover.
    error AlreadyStakedWithDifferentProver(address existingProver);

    /// @dev Thrown if staking or unstaking while the prover has one or more pending slash requests.
    error ProverHasSlashRequest();

    /// @dev Thrown if the slash request is not ready to be completed.
    error SlashNotReady();

    /// @dev Thrown if the dispenser is not the owner.
    error NotDispenser();

    /// @dev Thrown if the specified dispense amount exceeds the maximum dispense amount.
    error AmountExceedsAvailableDispense();

    /// @notice The address of the contract that can dispense yield.
    function dispenser() external view returns (address);

    /// @notice The minimum amount of $PROVE that a staker needs to stake.
    function minStakeAmount() external view returns (uint256);

    /// @notice The maximum number of unstake requests that a staker can have at once.
    function maxUnstakeRequests() external view returns (uint256);

    /// @notice The minimum amount of time needed between `requestUnstake()` and `finishUnstake()`.
    function unstakePeriod() external view returns (uint256);

    /// @notice The minimum amount of time needed between `requestSlash()` and `finishSlash()`.
    function slashPeriod() external view returns (uint256);

    /// @notice The maximum amount of $PROVE that can be dispensed per second.
    function dispenseRate() external view returns (uint256);

    /// @notice The last time $PROVE was dispensed.
    function lastDispenseTimestamp() external view returns (uint256);

    /// @notice The prover that a staker is staked with.
    /// @dev A staker can only be staked with one prover at a time. To switch provers, they must
    ///      fully unstake from their current prover first.
    /// @param staker The address of the staker.
    /// @return The address of the prover.
    function stakedTo(address staker) external view returns (address);

    /// @notice The amount $PROVE that a staker would receive if their full $stPROVE balance was
    ///         unstaked.
    /// @dev This does not account for any slashing that could occur during the unstaking period.
    /// @param staker The address of the staker.
    /// @return The amount of $PROVE.
    function staked(address staker) external view returns (uint256);

    /// @notice The amount of $PROVE that a prover has staked to them.
    /// @param prover The address of the prover.
    /// @return The amount of $PROVE.
    function proverStaked(address prover) external view returns (uint256);

    /// @notice The unstake requests for a staker.
    /// @param staker The address of the staker.
    /// @return The unstake requests.
    function unstakeRequests(address staker) external view returns (UnstakeClaim[] memory);

    /// @notice The slash requests for a prover.
    /// @param prover The address of the prover.
    /// @return The slash requests.
    function slashRequests(address prover) external view returns (SlashClaim[] memory);

    /// @notice The amount of $PROVE that a staker would receive with their pending unstake requests.
    /// @dev Returns the sum of snapshotted $PROVE values for all pending unstake claims, adjusted
    ///      for any slashing that occurred after the requests were made.
    /// @param staker The address of the staker.
    /// @return The amount of $PROVE.
    function unstakePending(address staker) external view returns (uint256);

    /// @notice The amount of $PROVE that a staker would receive if they unstaked from a prover.
    /// @param prover The address of the prover.
    /// @param stPROVE The amount of $stPROVE to unstake.
    /// @return The amount of $PROVE.
    function previewUnstake(address prover, uint256 stPROVE) external view returns (uint256);

    /// @notice The maximum amount of $PROVE that can be dispensed currently.
    /// @return The maximum amount of $PROVE.
    function maxDispense() external view returns (uint256);

    /// @notice Stake $PROVE to a prover. Must have approved $PROVE with this contract as the
    ///         spender. You may only stake to one prover at a time.
    /// @dev Deposits $PROVE into the iPROVE vault to mint $iPROVE, then deposits $iPROVE into the
    ///      chosen prover to mint $PROVER-N/$stPROVE.
    /// @param prover The address of the prover to delegate $iPROVE to.
    /// @param PROVE The amount of $PROVE to deposit.
    /// @return The amount of $stPROVE received.
    function stake(address prover, uint256 PROVE) external returns (uint256);

    /// @notice Stake $PROVE to a prover. You may only stake to one prover at a time.
    /// @dev Deposits $PROVE to mint $iPROVE, then deposits $iPROVE into the chosen
    ///      prover to mint $PROVER-N/$stPROVE. The prover is the spender of the permit, rather
    ///      than the staking contract, to avoid someone using the permit signature for an
    ///      unintended prover.
    /// @param prover The address of the prover to delegate $PROVE to.
    /// @param staker The address if the staker. Must correspond to the signer of the permit
    ///        signature.
    /// @param PROVE The amount of $PROVE to spend for the deposit.
    /// @param deadline The deadline for the permit signature.
    /// @param v The v component of the permit signature.
    /// @param r The r component of the permit signature.
    /// @param s The s component of the permit signature.
    /// @return The amount of $stPROVE the staker received.
    function permitAndStake(
        address prover,
        address staker,
        uint256 PROVE,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256);

    /// @notice Creates a request to unstake $stPROVE from the prover for the specified amount.
    /// @dev The staker must have enough $stPROVE that is not already in the unstake request queue.
    ///      The $iPROVE value is snapshotted at request time to prevent earning rewards during
    ///      the unstaking period.
    /// @param stPROVE The amount of $stPROVE to unstake.
    function requestUnstake(uint256 stPROVE) external;

    /// @notice Finishes the unstaking process for the specified address. Can be called by anyone.
    ///         Must have first called `requestUnstake()` and waited for the unstake period to pass.
    /// @dev For each claim, if any snapshotted $iPROVE is lower than the actual $iPROVE that was
    ///      received, then the difference is given back to the prover.
    /// @param staker The address whose unstake claims to finish.
    /// @return The amount of $PROVE received.
    function finishUnstake(address staker) external returns (uint256);

    /// @notice Creates a request to slash a prover for the specified amount. Only callable by the
    ///         VApp.
    /// @param prover The address of the prover to slash.
    /// @param iPROVE The amount of $iPROVE to slash.
    /// @return The index of the new slash request in this prover's slash requests storage array.
    ///         Because when slash requests are processed, it alters the order of the array, it is
    ///         best to first call `slashRequests(prover)` to get the index of the specific slash
    ///         request that is intended to be executed.
    function requestSlash(address prover, uint256 iPROVE) external returns (uint256);

    /// @notice Cancels a slash request. Only callable by the owner.
    /// @dev The index may not match what was originally returned by `requestSlash()`, and
    ///      should be re-calculated by calling `slashRequests(prover)` first.
    /// @param prover The address of the prover to slash.
    /// @param index The index of the slash request to cancel.
    function cancelSlash(address prover, uint256 index) external;

    /// @notice Finishes the slashing process. Must have first called `requestSlash()` and waited
    ///         for the slash period to pass. Decreases the value of $stPROVE for all stakers of that
    ///         prover. Only callable by the owner.
    /// @dev The index may not match what was originally returned by `requestSlash()`, and
    ///      should be re-calculated by calling `slashRequests(prover)` first.
    /// @param prover The address of the prover to slash.
    /// @param index The index of the slash request to finish.
    /// @return The amount of $iPROVE slashed.
    function finishSlash(address prover, uint256 index) external returns (uint256);

    /// @notice Rewards all stakers ($iPROVE holders) with $PROVE. Only callable by the dispenser.
    /// @dev The amount MUST be less than or equal to maxDispense() (if not type(uint256).max), and
    ///      the amount MUST be less than or equal to the amount of $PROVE balance of this contract.
    /// @param PROVE The amount of $PROVE to dispense. If this is `type(uint256).max`, dispense the
    ///        maximum available amount.
    function dispense(uint256 PROVE) external;

    /// @notice Updates the dispenser. Only callable by the owner.
    /// @param dispenser The new dispenser.
    function setDispenser(address dispenser) external;

    /// @notice Updates the dispense rate. Only callable by the owner.
    /// @param dispenseRate The new dispense rate.
    function updateDispenseRate(uint256 dispenseRate) external;
}
