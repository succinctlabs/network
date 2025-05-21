// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";
import {Initializable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MerkleProof} from
    "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISuccinctVApp} from "./interfaces/ISuccinctVApp.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {
    Receipt,
    Actions,
    ActionsInternal,
    DepositInternal,
    WithdrawInternal,
    AddSignerInternal,
    RemoveSignerInternal,
    SlashInternal,
    RewardInternal,
    ProverStateInternal,
    FeeUpdateInternal
} from "./libraries/Actions.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction,
    SlashAction,
    RewardAction,
    ProverStateAction,
    FeeUpdateAction
} from "./libraries/PublicValues.sol";
import {UUPSUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title SuccinctVApp
/// @author Succinct Labs
/// @notice Settlement layer for the vApp, processes deposits and withdrawals resulting from state transitions.
contract SuccinctVApp is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ISuccinctVApp
{
    using SafeERC20 for ERC20;

    /// @notice The maximum fee value (100% in basis points)
    uint256 public constant FEE_UNIT = 10000;

    /// @notice The address of the PROVE token
    address public PROVE;

    /// @notice The address of the succinct staking contract
    address public staking;

    /// @notice The address of the SP1 verifier contract.
    /// @dev This can either be a specific SP1Verifier for a specific version, or the
    ///      SP1VerifierGateway which can be used to verify proofs for any version of SP1.
    ///      For the list of supported verifiers on each chain, see:
    ///      https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    address public verifier;

    /// @notice The verification key for the fibonacci program.
    bytes32 public vappProgramVKey;

    /// @notice The block number of the last state update
    uint64 public blockNumber;

    /// @notice State root for each block
    mapping(uint64 => bytes32) public roots;

    /// @notice Timestamp for each block
    mapping(uint64 => uint64) public timestamps;

    /// @notice The maximum delay for actions to be committed, in seconds
    uint64 public maxActionDelay;

    /// @notice How long it takes for the state to be frozen
    uint64 public freezeDuration;

    /// @notice Mapping of whitelisted tokens
    mapping(address => bool) public whitelistedTokens;

    /// @notice The minimum amount for deposit/withdraw operations for each token
    mapping(address => uint256) public minAmounts;

    /// @notice The total deposits for each token on the vapp
    mapping(address => uint256) public totalDeposits;

    /// @notice Tracks the incrementing receipt counter
    uint64 public currentReceipt;

    /// @notice The receipt of the last finalized deposit
    uint64 public finalizedReceipt;

    /// @notice Receipts for pending actions
    mapping(uint64 => Receipt) public receipts;

    /// @notice The total pending withdrawal claims for each token
    mapping(address => uint256) public pendingWithdrawalClaims;

    /// @notice The delegated signers for each owner of a prover
    mapping(address => address[]) public delegatedSigners;

    /// @notice The signers that have been used for delegation
    mapping(address => bool) public usedSigners;

    /// @notice The claimable withdrawals for each account and token
    mapping(address => mapping(address => uint256)) public withdrawalClaims;

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializer
    /// @custom:oz-upgrades-unsafe-allow-initializers
    function initialize(
        address _owner,
        address _prove,
        address _staking,
        address _verifier,
        bytes32 _vappProgramVKey
    ) external initializer {
        if (_owner == address(0) || _prove == address(0)) {
            revert ZeroAddress();
        }

        __ReentrancyGuard_init();
        __Ownable_init(_owner);

        PROVE = _prove;
        staking = _staking;
        verifier = _verifier;
        vappProgramVKey = _vappProgramVKey;
        maxActionDelay = 1 days;
        freezeDuration = 1 days;

        emit UpdatedStaking(_staking);
        emit UpdatedVerifier(_verifier);
        emit Fork(_vappProgramVKey, 0, bytes32(0), bytes32(0));
        emit UpdatedMaxActionDelay(maxActionDelay);
        emit UpdatedFreezeDuration(freezeDuration);
    }

    /// @notice Returns the state root for the current block.
    function root() public view returns (bytes32) {
        return roots[blockNumber];
    }

    /// @notice Returns the timestamp for the current block.
    function timestamp() public view returns (uint64) {
        return timestamps[blockNumber];
    }

    /// @notice Returns the index of a delegated signer for an owner
    /// @param _owner The owner to check
    /// @param _signer The signer to check
    /// @return index The index of the signer, returns type(uint256).max if not found
    function hasDelegatedSigner(address _owner, address _signer) public view returns (uint256) {
        address[] memory signers = delegatedSigners[_owner];
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == _signer) {
                return i;
            }
        }

        return type(uint256).max;
    }

    /// @notice Get the delegated signers for an owner
    /// @param _owner The owner to get the delegated signers for
    /// @return The delegated signers
    function getDelegatedSigners(address _owner) external view returns (address[] memory) {
        return delegatedSigners[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the succinct staking contract address
    /// @dev Only callable by the owner
    /// @param _staking The new staking contract address
    function updateStaking(address _staking) external onlyOwner {
        staking = _staking;

        emit UpdatedStaking(_staking);
    }

    /// @notice Updates the verifier address
    /// @dev Only callable by the owner
    /// @param _verifier The new verifier address
    function updateVerifier(address _verifier) external onlyOwner {
        verifier = _verifier;

        emit UpdatedVerifier(verifier);
    }

    /// @notice Updates the max action delay
    /// @dev Only callable by the owner
    /// @param _actionDelay The new max action delay
    function updateActionDelay(uint64 _actionDelay) external onlyOwner {
        maxActionDelay = _actionDelay;

        emit UpdatedMaxActionDelay(maxActionDelay);
    }

    /// @notice Updates the freeze duration
    /// @dev Only callable by the owner
    /// @param _freezeDuration The new freeze duration
    function updateFreezeDuration(uint64 _freezeDuration) external onlyOwner {
        freezeDuration = _freezeDuration;

        emit UpdatedFreezeDuration(freezeDuration);
    }

    /// @notice Adds a token to the whitelist
    /// @dev Only callable by the owner
    /// @param _token The token address to add
    function addToken(address _token) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        if (whitelistedTokens[_token]) revert TokenAlreadyWhitelisted();

        whitelistedTokens[_token] = true;

        emit TokenWhitelist(_token, true);
    }

    /// @notice Removes a token from the whitelist
    /// @dev Only callable by the owner
    /// @param _token The token address to remove
    function removeToken(address _token) external onlyOwner {
        if (!whitelistedTokens[_token]) revert TokenNotWhitelisted();

        whitelistedTokens[_token] = false;

        emit TokenWhitelist(_token, false);
    }

    /// @notice Sets the minimum amount for a token for deposit/withdraw operations
    /// @dev Only callable by the owner, if amount is 0, minimum check is skipped
    /// @param _token The token address
    /// @param _amount The minimum amount
    function setMinAmount(address _token, uint256 _amount) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();

        minAmounts[_token] = _amount;

        emit MinAmountUpdated(_token, _amount);
    }

    /// @notice Updates the vapp program verification key, forks the state root
    /// @dev Only callable by the owner, executes a state update
    /// @param _vkey The new vkey
    /// @param _newOldRoot The old root committed by the new program
    /// @param _publicValues The encoded public values
    /// @param _proofBytes The encoded proof
    function fork(
        bytes32 _vkey,
        bytes32 _newOldRoot,
        bytes calldata _publicValues,
        bytes calldata _proofBytes
    ) external onlyOwner returns (uint64, bytes32, bytes32) {
        // Update the vkey.
        vappProgramVKey = _vkey;

        // Update the root and produce a new block.
        bytes32 _oldRoot = bytes32(0);
        uint64 _block = blockNumber;
        if (_block != 0) {
            _oldRoot = roots[_block];
        }
        roots[++_block] = _newOldRoot;

        emit Block(_block, _newOldRoot, _oldRoot);
        emit Fork(vappProgramVKey, _block, _newOldRoot, _oldRoot);

        return updateState(_publicValues, _proofBytes);
    }

    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit
    /// @dev Scales the deposit amount by the UNIT factor
    /// @param account The account to deposit to
    /// @param token The token to deposit
    /// @param amount The amount to deposit
    function deposit(address account, address token, uint256 amount)
        external
        nonReentrant
        returns (uint64 receipt)
    {
        if (account == address(0)) revert ZeroAddress();
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        // Check minimum amount if set (skip check if minimum is 0)
        uint256 minAmount = minAmounts[token];
        if (minAmount > 0 && amount < minAmount) {
            revert MinAmount();
        }

        bytes memory data =
            abi.encode(DepositAction({account: account, token: token, amount: amount}));
        receipt = _createReceipt(ActionType.Deposit, data);

        totalDeposits[token] += amount;

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw from the sender's account to a recipient address
    /// @dev Submit a withdraw request on the contract, can fail if balance is insufficient
    /// @param to The recipient address to receive the withdrawn funds
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function withdraw(address to, address token, uint256 amount)
        external
        nonReentrant
        returns (uint64 receipt)
    {
        if (to == address(0)) revert ZeroAddress();
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        // Check minimum amount if set (skip check if minimum is 0)
        uint256 minAmount = minAmounts[token];
        if (minAmount > 0 && amount < minAmount) {
            revert MinAmount();
        }

        bytes memory data =
            abi.encode(WithdrawAction({account: msg.sender, token: token, amount: amount, to: to}));
        receipt = _createReceipt(ActionType.Withdraw, data);
    }

    /// @notice Claim a withdrawal
    /// @dev Anyone can claim a withdrawal for an account
    /// @param to The address to claim the withdrawal for
    /// @param token The token to claim
    function claimWithdrawal(address to, address token)
        external
        nonReentrant
        returns (uint256 amount)
    {
        amount = withdrawalClaims[to][token];
        if (amount == 0) revert NoWithdrawalToClaim();

        // Adjust the balances.
        pendingWithdrawalClaims[token] -= amount;
        withdrawalClaims[to][token] = 0;

        // Transfer the withdrawal.
        ERC20(token).safeTransfer(to, amount);

        emit WithdrawalClaimed(to, token, msg.sender, amount);
    }

    /// @notice Add a delegated signer for an owner
    /// @dev Only callable by the prover owner
    /// @param _signer The delegated signer to add
    function addDelegatedSigner(address _signer) external returns (uint64 receipt) {
        if (_signer == address(0)) revert ZeroAddress();
        if (usedSigners[_signer]) revert InvalidSigner();
        if (!ISuccinctStaking(staking).hasProver(msg.sender)) revert ZeroAddress();
        if (ISuccinctStaking(staking).isProver(_signer)) revert InvalidSigner();
        if (ISuccinctStaking(staking).hasProver(_signer)) revert InvalidSigner();

        bytes memory data = abi.encode(AddSignerAction({owner: msg.sender, signer: _signer}));
        receipt = _createReceipt(ActionType.AddSigner, data);

        delegatedSigners[msg.sender].push(_signer);
        usedSigners[_signer] = true;
    }

    /// @notice Remove a delegated signer for an owner
    /// @dev Only callable by the prover owner
    /// @param _signer The delegated signer to remove
    function removeDelegatedSigner(address _signer) external returns (uint64 receipt) {
        uint256 index = hasDelegatedSigner(msg.sender, _signer);
        if (index == type(uint256).max) revert InvalidSigner();
        if (!usedSigners[_signer]) revert InvalidSigner();

        bytes memory data = abi.encode(RemoveSignerAction({owner: msg.sender, signer: _signer}));
        receipt = _createReceipt(ActionType.RemoveSigner, data);

        delegatedSigners[msg.sender][index] =
            delegatedSigners[msg.sender][delegatedSigners[msg.sender].length - 1];
        delegatedSigners[msg.sender].pop();
        usedSigners[_signer] = false;
    }

    /// @notice Creates a receipt for an action
    /// @dev Internal function to simplify receipt creation
    /// @param actionType The type of action
    /// @param data The encoded action data
    /// @return receipt The receipt ID
    function _createReceipt(ActionType actionType, bytes memory data)
        internal
        returns (uint64 receipt)
    {
        receipt = ++currentReceipt;
        receipts[receipt] = Receipt({
            action: actionType,
            status: ReceiptStatus.Pending,
            timestamp: uint64(block.timestamp),
            data: data
        });

        emit ReceiptPending(receipt, actionType, data);
    }

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency withdraw.
    /// @dev Anyone can call this function to withdraw their balance after the freeze duration has passed
    /// @param _token The token to withdraw
    /// @param _balance The balance to withdraw
    /// @param _proof The proof of the balance
    function emergencyWithdraw(address _token, uint256 _balance, bytes32[] calldata _proof)
        external
        nonReentrant
    {
        if (_proof.length == 0) revert InvalidProof();
        if (!whitelistedTokens[_token]) revert TokenNotWhitelisted();
        if (block.timestamp < timestamp() + freezeDuration) revert NotFrozen();

        bytes32 leaf = sha256(abi.encodePacked(msg.sender, _token, _balance));
        bytes32 _root = root();
        bool isValid = MerkleProof.verifyCalldata(_proof, _root, leaf, _hashPair);
        if (!isValid) revert ProofFailed();

        _processWithdraw(msg.sender, _token, _balance);

        emit EmergencyWithdrawal(msg.sender, _token, _balance, _root);
    }

    /// @notice The entrypoint for verifying the state transition proof, commits actions and updates the state root
    /// @dev Reverts if the committed actions are invalid, callable by anyone
    /// @param _proofBytes The encoded proof
    /// @param _publicValues The encoded public values
    function updateState(bytes calldata _publicValues, bytes calldata _proofBytes)
        public
        nonReentrant
        returns (uint64, bytes32, bytes32)
    {
        // Verify the proof
        ISP1Verifier(verifier).verifyProof(vappProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        if (publicValues.newRoot == bytes32(0)) revert InvalidRoot();

        // Verify the old root
        if (blockNumber != 0 && roots[blockNumber] != publicValues.oldRoot) {
            revert InvalidOldRoot();
        }

        // Assert that the timestamp is not in the future and is increasing
        if (publicValues.timestamp > block.timestamp) revert InvalidTimestamp();
        if (blockNumber != 0 && timestamps[blockNumber] > publicValues.timestamp) {
            revert TimestampInPast();
        }

        // Update the state root
        uint64 _block = ++blockNumber;
        roots[_block] = publicValues.newRoot;
        timestamps[_block] = publicValues.timestamp;

        // Commit the actions
        _handleActions(publicValues);

        emit Block(_block, publicValues.newRoot, publicValues.oldRoot);

        return (_block, publicValues.newRoot, publicValues.oldRoot);
    }

    /// @dev Handles committed actions, reverts if the actions are invalid
    function _handleActions(PublicValuesStruct memory _publicValues) internal {
        // Validate the actions
        uint64 _timestamp = uint64(block.timestamp);
        uint64 _actionDelay = maxActionDelay;
        Actions.validate(
            receipts,
            _publicValues.actions,
            finalizedReceipt,
            currentReceipt,
            _timestamp,
            _actionDelay
        );

        // Execute the actions
        ActionsInternal memory decoded = Actions.decode(_publicValues.actions);
        _depositActions(decoded.deposits);
        _withdrawActions(decoded.withdrawals);
        _addSignerActions(decoded.addSigners);
        _removeSignerActions(decoded.removeSigners);
        _slashActions(decoded.slashes);
        _rewardActions(decoded.rewards);
        _proverStateActions(decoded.proverStates);
        _feeUpdateActions(decoded.feeUpdates);

        // Update the last finalized receipt
        if (decoded.lastReceipt != 0) {
            finalizedReceipt = decoded.lastReceipt;
        }
    }

    /// @dev Handles deposit actions.
    function _depositActions(DepositInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            emit ReceiptCompleted(
                _actions[i].action.receipt, ActionType.Deposit, _actions[i].action.data
            );
        }
    }

    /// @dev Handles withdraw actions.
    function _withdrawActions(WithdrawInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only update if there is a corresponding receipt
            if (_actions[i].action.receipt != 0) {
                receipts[_actions[i].action.receipt].status = _actions[i].action.status;

                if (_actions[i].action.status == ReceiptStatus.Failed) {
                    emit ReceiptFailed(
                        _actions[i].action.receipt, ActionType.Withdraw, _actions[i].action.data
                    );
                }
            }

            // Handle the action status
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                if (whitelistedTokens[_actions[i].data.token]) {
                    // Process the withdrawal
                    _processWithdraw(
                        _actions[i].data.to, _actions[i].data.token, _actions[i].data.amount
                    );

                    emit ReceiptCompleted(
                        _actions[i].action.receipt, ActionType.Withdraw, _actions[i].action.data
                    );
                }
            }
        }
    }

    /// @dev Handles add signer actions.
    function _addSignerActions(AddSignerInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            if (_actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.AddSigner, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles remove signer actions.
    function _removeSignerActions(RemoveSignerInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            if (_actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.RemoveSigner, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles slash actions.
    function _slashActions(SlashInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                ISuccinctStaking(staking).requestSlash(
                    _actions[i].data.prover, _actions[i].data.amount
                );

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.Slash, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles reward actions.
    function _rewardActions(RewardInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Approve $PROVE transfer for the staking contract.
                ERC20(PROVE).approve(_actions[i].data.prover, _actions[i].data.amount);

                // Call reward function on staking contract.
                ISuccinctStaking(staking).reward(_actions[i].data.prover, _actions[i].data.amount);

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.Reward, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles prover state actions.
    function _proverStateActions(ProverStateInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Verify array lengths match.
                require(
                    _actions[i].data.provers.length == _actions[i].data.proveBalances.length
                        && _actions[i].data.provers.length == _actions[i].data.usdcBalances.length,
                    "Array length mismatch"
                );

                // Verify each prover's on-chain balance matches the asserted balance.
                for (uint256 j = 0; j < _actions[i].data.provers.length; j++) {
                    address prover = _actions[i].data.provers[j];
                    uint256 assertedProveBalance = _actions[i].data.proveBalances[j];

                    // Check $PROVE token balance.
                    uint256 actualProveBalance = ERC20(PROVE).balanceOf(prover);
                    require(actualProveBalance == assertedProveBalance, "PROVE balance mismatch");
                }

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.ProverState, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Processes a withdrawal by creating a claim for the amount.
    function _processWithdraw(address _to, address _token, uint256 _amount) internal {
        if (!whitelistedTokens[_token]) revert TokenNotWhitelisted();

        pendingWithdrawalClaims[_token] += _amount;
        withdrawalClaims[_to][_token] += _amount;
        totalDeposits[_token] -= _amount;
    }

    /// @dev Handles fee update actions.
    function _feeUpdateActions(FeeUpdateInternal[] memory _actions) internal {}

    /// @dev Hashes a pair of bytes32 values using SHA-256.
    function _hashPair(bytes32 _a, bytes32 _b) internal pure returns (bytes32) {
        return (_a < _b) ? sha256(abi.encodePacked(_a, _b)) : sha256(abi.encodePacked(_b, _a));
    }

    /// @dev Authorizes an ERC1967 proxy upgrade to a new implementation contract.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
