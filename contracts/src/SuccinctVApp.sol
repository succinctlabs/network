// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";
import {Initializable} from "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MerkleProof} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISuccinctVApp} from "./interfaces/ISuccinctVApp.sol";
import {IWeth} from "./interfaces/IWeth.sol";
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

/// @title SuccinctVApp
/// @author Succinct Labs
/// @notice Settlement layer for the vApp, processes deposits and withdrawals resulting from state transitions.
contract SuccinctVApp is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, ISuccinctVApp {
    using SafeERC20 for ERC20;

    /// @notice The maximum fee value (100% in basis points)
    uint256 public constant FEE_UNIT = 10000;

    /// @notice The address of the WETH token
    IWeth public WETH;

    /// @notice The address of the USDC token
    ERC20 public USDC;

    /// @notice The address of the PROVE token
    ERC20 public PROVE;

    /// @notice The address of the succinct staking contract
    ISuccinctStaking public staking;

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
        address _weth,
        address _usdc,
        address _prove,
        address _staking,
        address _verifier,
        bytes32 _vappProgramVKey
    ) external initializer {
        if (_owner == address(0) || _usdc == address(0) || _prove == address(0)) {
            revert InvalidAddress();
        }

        __ReentrancyGuard_init();
        __Ownable_init(_owner);

        WETH = IWeth(_weth);
        USDC = ERC20(_usdc);
        PROVE = ERC20(_prove);
        staking = ISuccinctStaking(_staking);
        verifier = _verifier;
        vappProgramVKey = _vappProgramVKey;
        maxActionDelay = 1 days;
        freezeDuration = 1 days;

        emit UpdatedStaking(_staking);
        emit UpdatedVerifier(verifier);
        emit Fork(vappProgramVKey, 0, bytes32(0), bytes32(0));
        emit UpdatedMaxActionDelay(maxActionDelay);
        emit UpdatedFreezeDuration(freezeDuration);
    }

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
    event Fork(bytes32 indexed vkey, uint64 indexed block, bytes32 indexed new_root, bytes32 old_root);

    /// @notice Updates the succinct staking contract address
    /// @dev Only callable by the owner
    /// @param _staking The new staking contract address
    function updateStaking(address _staking) external onlyOwner {
        staking = ISuccinctStaking(_staking);

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
        if (_token == address(0)) revert InvalidAddress();
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
        if (_token == address(0)) revert InvalidAddress();

        minAmounts[_token] = _amount;

        emit MinAmountUpdated(_token, _amount);
    }

    /// @notice Updates the vapp program verification key, forks the state root
    /// @dev Only callable by the owner, executes a state update
    /// @param _vkey The new vkey
    /// @param new_old_root The old root committed by the new program
    /// @param _publicValues The encoded public values
    /// @param _proofBytes The encoded proof
    function fork(bytes32 _vkey, bytes32 new_old_root, bytes calldata _publicValues, bytes calldata _proofBytes)
        external
        onlyOwner
        returns (uint64, bytes32, bytes32)
    {
        // Update the vkey
        vappProgramVKey = _vkey;

        // Update the root and produce a new block
        bytes32 old_root = bytes32(0);
        uint64 _block = blockNumber;
        if (_block != 0) {
            old_root = roots[_block];
        }
        roots[++_block] = new_old_root;

        emit Block(_block, new_old_root, old_root);
        emit Fork(vappProgramVKey, _block, new_old_root, old_root);

        return updateState(_publicValues, _proofBytes);
    }

    /// @notice Receive function to handle incoming ETH (used for WETH unwrapping)
    receive() external payable {
        require(msg.sender == address(WETH), "Only WETH");
    }

    /*//////////////////////////////////////////////////////////////
                                  USER
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit
    /// @dev Scales the deposit amount by the UNIT factor
    /// @param account The account to deposit to
    /// @param token The token to deposit
    /// @param amount The amount to deposit
    function deposit(address account, address token, uint256 amount) external nonReentrant returns (uint64 receipt) {
        if (account == address(0)) revert InvalidAddress();
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        // Check minimum amount if set (skip check if minimum is 0)
        uint256 minAmount = minAmounts[token];
        if (minAmount > 0 && amount < minAmount) {
            revert MinAmount();
        }

        bytes memory data = abi.encode(DepositAction({account: account, token: token, amount: amount}));
        receipt = _createReceipt(ActionType.Deposit, data);

        totalDeposits[token] += amount;

        ERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice Withdraw from the sender's account to a recipient address
    /// @dev Submit a withdraw request on the contract, can fail if balance is insufficient
    /// @param to The recipient address to receive the withdrawn funds
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function withdraw(address to, address token, uint256 amount) external nonReentrant returns (uint64 receipt) {
        if (to == address(0)) revert InvalidAddress();
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        // Check minimum amount if set (skip check if minimum is 0)
        uint256 minAmount = minAmounts[token];
        if (minAmount > 0 && amount < minAmount) {
            revert MinAmount();
        }

        bytes memory data = abi.encode(WithdrawAction({account: msg.sender, token: token, amount: amount, to: to}));
        receipt = _createReceipt(ActionType.Withdraw, data);
    }

    /// @notice Claim a withdrawal
    /// @dev Anyone can claim a withdrawal for an account
    /// @param to The address to claim the withdrawal for
    /// @param token The token to claim
    /// @param unwrap Whether to unwrap WETH to ETH (only applicable if token is WETH)
    function claimWithdrawal(address to, address token, bool unwrap) external nonReentrant returns (uint256 amount) {
        amount = withdrawalClaims[to][token];
        if (amount == 0) revert NoWithdrawalToClaim();

        // Transfer the withdrawal
        pendingWithdrawalClaims[token] -= amount;
        withdrawalClaims[to][token] = 0;

        if (unwrap && token == address(WETH)) {
            // For WETH, unwrap to ETH if requested
            ERC20(token).safeTransfer(address(this), amount);
            WETH.withdraw(amount);
            (bool success,) = to.call{value: amount}("");
            if (!success) revert ETHTransferFailed();
        } else {
            // For all other tokens, transfer normally
            ERC20(token).safeTransfer(to, amount);
        }

        emit WithdrawalClaimed(to, token, msg.sender, amount);
    }

    /// @notice Add a delegated signer for an owner
    /// @dev Only callable by the prover owner
    /// @param signer The delegated signer to add
    function addDelegatedSigner(address signer) external returns (uint64 receipt) {
        if (!staking.hasProver(msg.sender)) revert InvalidAddress();
        if (signer == address(0)) revert InvalidAddress();
        if (staking.isProver(signer)) revert InvalidSigner();
        if (staking.hasProver(signer)) revert InvalidSigner();
        if (usedSigners[signer]) revert InvalidSigner();

        bytes memory data = abi.encode(AddSignerAction({owner: msg.sender, signer: signer}));
        receipt = _createReceipt(ActionType.AddSigner, data);

        delegatedSigners[msg.sender].push(signer);
        usedSigners[signer] = true;
    }

    /// @notice Remove a delegated signer for an owner
    /// @dev Only callable by the prover owner
    /// @param signer The delegated signer to remove
    function removeDelegatedSigner(address signer) external returns (uint64 receipt) {
        uint256 index = hasDelegatedSigner(msg.sender, signer);
        if (index == type(uint256).max) revert InvalidSigner();
        if (!usedSigners[signer]) revert InvalidSigner();

        bytes memory data = abi.encode(RemoveSignerAction({owner: msg.sender, signer: signer}));
        receipt = _createReceipt(ActionType.RemoveSigner, data);

        delegatedSigners[msg.sender][index] = delegatedSigners[msg.sender][delegatedSigners[msg.sender].length - 1];
        delegatedSigners[msg.sender].pop();
        usedSigners[signer] = false;
    }

    /// @notice Creates a receipt for an action
    /// @dev Internal function to simplify receipt creation
    /// @param actionType The type of action
    /// @param data The encoded action data
    /// @return receipt The receipt ID
    function _createReceipt(ActionType actionType, bytes memory data) internal returns (uint64 receipt) {
        receipt = ++currentReceipt;
        receipts[receipt] =
            Receipt({action: actionType, status: ReceiptStatus.Pending, timestamp: uint64(block.timestamp), data: data});

        emit ReceiptPending(receipt, actionType, data);
    }

    /// @notice Returns the index of a delegated signer for an owner
    /// @param owner The owner to check
    /// @param signer The signer to check
    /// @return index The index of the signer, returns type(uint256).max if not found
    function hasDelegatedSigner(address owner, address signer) public view returns (uint256) {
        address[] memory signers = delegatedSigners[owner];
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == signer) {
                return i;
            }
        }

        return type(uint256).max;
    }

    /// @notice Get the delegated signers for an owner
    /// @param owner The owner to get the delegated signers for
    /// @return The delegated signers
    function getDelegatedSigners(address owner) external view returns (address[] memory) {
        return delegatedSigners[owner];
    }

    /*//////////////////////////////////////////////////////////////
                               EMERGENCY
    //////////////////////////////////////////////////////////////*/

    /// @notice Emergency withdraw
    /// @dev Anyone can call this function to withdraw their balance after the freeze duration has passed
    /// @param token The token to withdraw
    /// @param balance The balance to withdraw
    /// @param proof The proof of the balance
    function emergencyWithdraw(address token, uint256 balance, bytes32[] calldata proof) external nonReentrant {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();
        if (proof.length == 0) revert InvalidProof();
        if (block.timestamp < timestamp() + freezeDuration) revert NotFrozen();

        bytes32 leaf = sha256(abi.encodePacked(msg.sender, token, balance));
        bytes32 _root = root();
        bool isValid = MerkleProof.verifyCalldata(proof, _root, leaf, _hashPair);
        if (!isValid) revert ProofFailed();

        _processWithdraw(msg.sender, token, balance);

        emit EmergencyWithdrawal(msg.sender, token, balance, _root);
    }

    /// @notice Hashes a pair of bytes32 values
    /// @param a The first value
    /// @param b The second value
    /// @return The hashed value
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return (a < b) ? sha256(abi.encodePacked(a, b)) : sha256(abi.encodePacked(b, a));
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

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
        if (publicValues.new_root == bytes32(0)) revert InvalidRoot();

        // Verify the old root
        if (blockNumber != 0 && roots[blockNumber] != publicValues.old_root) {
            revert InvalidOldRoot();
        }

        // Assert that the timestamp is not in the future and is increasing
        if (publicValues.timestamp > block.timestamp) revert InvalidTimestamp();
        if (blockNumber != 0 && timestamps[blockNumber] > publicValues.timestamp) revert TimestampInPast();

        // Update the state root
        uint64 _block = ++blockNumber;
        roots[_block] = publicValues.new_root;
        timestamps[_block] = publicValues.timestamp;

        // Commit the actions
        _actions(publicValues);

        emit Block(_block, publicValues.new_root, publicValues.old_root);

        return (_block, publicValues.new_root, publicValues.old_root);
    }

    /// @dev Handles committed actions, reverts if the actions are invalid
    /// @param publicValues The encoded public values
    function _actions(PublicValuesStruct memory publicValues) internal {
        // Validate the actions
        uint64 _timestamp = uint64(block.timestamp);
        uint64 _actionDelay = maxActionDelay;
        Actions.validate(receipts, publicValues.actions, finalizedReceipt, currentReceipt, _timestamp, _actionDelay);

        // Execute the actions
        ActionsInternal memory decoded = Actions.decode(publicValues.actions);
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

    /// @dev Handles deposit actions
    /// @param actions The deposit actions to execute
    function _depositActions(DepositInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            receipts[actions[i].action.receipt].status = actions[i].action.status;

            emit ReceiptCompleted(actions[i].action.receipt, ActionType.Deposit, actions[i].action.data);
        }
    }

    /// @dev Handles withdraw actions
    /// @param actions The withdraw actions to execute
    function _withdrawActions(WithdrawInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            // Only update if there is a corresponding receipt
            if (actions[i].action.receipt != 0) {
                receipts[actions[i].action.receipt].status = actions[i].action.status;

                if (actions[i].action.status == ReceiptStatus.Failed) {
                    emit ReceiptFailed(actions[i].action.receipt, ActionType.Withdraw, actions[i].action.data);
                }
            }

            // Handle the action status
            if (actions[i].action.status == ReceiptStatus.Completed) {
                if (whitelistedTokens[actions[i].data.token]) {
                    // Process the withdrawal
                    _processWithdraw(actions[i].data.to, actions[i].data.token, actions[i].data.amount);

                    emit ReceiptCompleted(actions[i].action.receipt, ActionType.Withdraw, actions[i].action.data);
                }
            }
        }
    }

    /// @dev Handles add signer actions
    /// @param actions The add signer actions to execute
    function _addSignerActions(AddSignerInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            receipts[actions[i].action.receipt].status = actions[i].action.status;

            if (actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(actions[i].action.receipt, ActionType.AddSigner, actions[i].action.data);
            }
        }
    }

    /// @dev Handles remove signer actions
    /// @param actions The remove signer actions to execute
    function _removeSignerActions(RemoveSignerInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            receipts[actions[i].action.receipt].status = actions[i].action.status;

            if (actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(actions[i].action.receipt, ActionType.RemoveSigner, actions[i].action.data);
            }
        }
    }

    /// @dev Handles slash actions
    /// @param actions The slash actions to execute
    function _slashActions(SlashInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            if (actions[i].action.status == ReceiptStatus.Completed) {
                staking.requestSlash(actions[i].data.prover, actions[i].data.amount);

                emit ReceiptCompleted(actions[i].action.receipt, ActionType.Slash, actions[i].action.data);
            }
        }
    }

    /// @dev Handles reward actions
    /// @param actions The reward actions to execute
    function _rewardActions(RewardInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            if (actions[i].action.status == ReceiptStatus.Completed) {
                // Approve USDC transfer for the staking contract
                USDC.approve(actions[i].data.prover, actions[i].data.amount);

                // Call reward function on staking contract
                staking.reward(actions[i].data.prover, actions[i].data.amount);

                emit ReceiptCompleted(actions[i].action.receipt, ActionType.Reward, actions[i].action.data);
            }
        }
    }

    /// @dev Processes a withdrawal by creating a claim for the amount
    /// @param to The address to withdraw to
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function _processWithdraw(address to, address token, uint256 amount) internal {
        if (!whitelistedTokens[token]) revert TokenNotWhitelisted();

        pendingWithdrawalClaims[token] += amount;
        withdrawalClaims[to][token] += amount;
        totalDeposits[token] -= amount;
    }

    /// @dev Handles prover state actions
    /// @param actions The prover state actions to execute
    function _proverStateActions(ProverStateInternal[] memory actions) internal {
        for (uint64 i = 0; i < actions.length; i++) {
            if (actions[i].action.status == ReceiptStatus.Completed) {
                // Verify array lengths match
                require(
                    actions[i].data.provers.length == actions[i].data.proveBalances.length
                        && actions[i].data.provers.length == actions[i].data.usdcBalances.length,
                    "Array length mismatch"
                );

                // Verify each prover's on-chain balance matches the asserted balance
                for (uint256 j = 0; j < actions[i].data.provers.length; j++) {
                    address prover = actions[i].data.provers[j];
                    uint256 assertedProveBalance = actions[i].data.proveBalances[j];
                    uint256 assertedUsdcBalance = actions[i].data.usdcBalances[j];

                    // Check PROVE token balance
                    uint256 actualProveBalance = PROVE.balanceOf(prover);
                    require(actualProveBalance == assertedProveBalance, "PROVE balance mismatch");

                    // Check USDC token balance
                    uint256 actualUsdcBalance = USDC.balanceOf(prover);
                    require(actualUsdcBalance == assertedUsdcBalance, "USDC balance mismatch");
                }

                emit ReceiptCompleted(actions[i].action.receipt, ActionType.ProverState, actions[i].action.data);
            }
        }
    }

    /// @dev Handles fee update actions
    /// @param actions The fee update actions to execute
    function _feeUpdateActions(FeeUpdateInternal[] memory actions) internal {}

    /// @notice Returns the state root for the current block
    function root() public view returns (bytes32) {
        return roots[blockNumber];
    }

    /// @notice Returns the timestamp for the current block
    function timestamp() public view returns (uint64) {
        return timestamps[blockNumber];
    }
}
