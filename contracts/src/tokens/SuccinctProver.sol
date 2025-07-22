// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
import {IGovernor} from "../../lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20Votes} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC4626} from
    "../../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "../../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

string constant NAME_PREFIX = "SuccinctProver-";
string constant SYMBOL_PREFIX = "PROVER-";

/// @title SuccinctProver
/// @author Succinct Labs
/// @notice The per-prover receipt token for delegating stake to a prover.
/// @dev This contract accepts $iPROVE and mints $PROVER-N. It is non-transferable
///      outside of staking operations.
contract SuccinctProver is ERC4626, IProver {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /// @inheritdoc IProver
    address public immutable override staking;

    /// @inheritdoc IProver
    address public immutable override governor;

    /// @inheritdoc IProver
    address public immutable override prove;

    /// @inheritdoc IProver
    address public immutable override owner;

    /// @inheritdoc IProver
    uint256 public immutable override id;

    /// @inheritdoc IProver
    uint256 public immutable override stakerFeeBips;

    /// @dev Modifier to ensure that the caller is the prover owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotProverOwner();
        _;
    }

    /// @dev Initializes this vault with $iPROVE as the underlying, with additional parameters.
    constructor(
        address _governor,
        address _prove,
        address _iProve,
        address _owner,
        uint256 _id,
        uint256 _stakerFeeBips
    )
        ERC20(string.concat(NAME_PREFIX, _id.toString()), string.concat(SYMBOL_PREFIX, _id.toString()))
        ERC4626(IERC20(_iProve))
    {
        if (
            _governor == address(0) || _prove == address(0) || _iProve == address(0)
                || _owner == address(0)
        ) {
            revert ZeroAddress();
        }

        staking = msg.sender;
        governor = _governor;
        prove = _prove;
        owner = _owner;
        id = _id;
        stakerFeeBips = _stakerFeeBips;

        // Self-delegate so that this prover can participate in governance.
        ERC20Votes(_iProve).delegate(address(this));
    }

    /// @inheritdoc IProver
    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external override onlyOwner returns (uint256) {
        return IGovernor(governor).propose(_targets, _values, _calldatas, _description);
    }

    /// @inheritdoc IProver
    function cancel(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) external override onlyOwner returns (uint256) {
        return IGovernor(governor).cancel(_targets, _values, _calldatas, _descriptionHash);
    }

    /// @inheritdoc IProver
    function castVote(uint256 _proposalId, uint8 _support)
        external
        override
        onlyOwner
        returns (uint256)
    {
        return IGovernor(governor).castVote(_proposalId, _support);
    }

    /// @inheritdoc IProver
    function transferProveToStaking(address _from, uint256 _amount) external override {
        if (msg.sender != staking) {
            revert NotStaking();
        }

        IERC20(prove).safeTransferFrom(_from, staking, _amount);
    }

    /// @dev Override to prevent transfers of $PROVER-N tokens except for stake/unstake.
    function _update(address _from, address _to, uint256 _value) internal override(ERC20) {
        if (msg.sender != staking) {
            revert NonTransferable();
        }

        super._update(_from, _to, _value);
    }

    /// @dev Override to allow the staking contract to spend $PROVER-N.
    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal override {
        if (_spender == staking) {
            return;
        }

        super._spendAllowance(_owner, _spender, _amount);
    }
}
