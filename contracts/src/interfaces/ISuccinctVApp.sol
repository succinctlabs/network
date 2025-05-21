// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ActionType} from "../libraries/PublicValues.sol";

/// @title vApp interface
/// @notice Interface for the vApp contract
interface ISuccinctVApp {
    /// @notice Errors
    error InvalidAmount();
    error ZeroAddress();
    error InvalidRoot();
    error InvalidOldRoot();
    error SweepTransferFailed();
    error NoWithdrawalToClaim();
    error ClaimTransferFailed();
    error InvalidVkey();
    error NotFrozen();
    error InvalidProof();
    error InvalidTimestamp();
    error TimestampInPast();
    error ProofFailed();
    error TokenNotWhitelisted();
    error TokenAlreadyWhitelisted();
    error InvalidSigner();
    error MinAmount();
    error ETHTransferFailed();

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /// @notice Updated staking
    event UpdatedStaking(address indexed staking);

    /// @notice Updated verifier
    event UpdatedVerifier(address indexed verifier);

    /// @notice Updated max action delay
    event UpdatedMaxActionDelay(uint64 indexed actionDelay);

    /// @notice Updated freeze duration
    event UpdatedFreezeDuration(uint64 indexed freezeDuration);

    /// @notice Token whitelist status changed
    event TokenWhitelist(address indexed token, bool allowed);

    /// @notice Minimum amount updated for a token
    event MinAmountUpdated(address indexed token, uint256 amount);

    /// @notice Fork the program
    event Fork(
        bytes32 indexed vkey, uint64 indexed block, bytes32 indexed newRoot, bytes32 oldRoot
    );

    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    /// @notice Generalized pending receipt event for all action types
    event ReceiptPending(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Withdrawal claimed event
    event WithdrawalClaimed(
        address indexed account, address indexed token, address sender, uint256 amount
    );

    /// @notice Emergency withdrawal event
    event EmergencyWithdrawal(
        address indexed account, address indexed token, uint256 balance, bytes32 root
    );

    function deposit(address account, address token, uint256 amount)
        external
        returns (uint64 receipt);

    function withdraw(address to, address token, uint256 amount)
        external
        returns (uint64 receipt);

    function claimWithdrawal(address to, address token) external returns (uint256 amount);

    function addDelegatedSigner(address signer) external returns (uint64 receipt);

    function removeDelegatedSigner(address signer) external returns (uint64 receipt);

    function hasDelegatedSigner(address owner, address signer) external view returns (uint256);

    function getDelegatedSigners(address owner) external view returns (address[] memory);

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function emergencyWithdraw(address token, uint256 balance, bytes32[] calldata proof) external;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice When a new block is committed
    event Block(uint64 indexed block, bytes32 indexed newRoot, bytes32 indexed oldRoot);

    /// @notice Generalized receipt completed event for all action types
    event ReceiptCompleted(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Generalized receipt failed event for all action types
    event ReceiptFailed(uint64 indexed receipt, ActionType indexed action, bytes data);

    function updateState(bytes calldata _publicValues, bytes calldata _proofBytes)
        external
        returns (uint64, bytes32, bytes32);

    function root() external view returns (bytes32);

    function timestamp() external view returns (uint64);
}
