// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProver} from "../interfaces/IProver.sol";
import {ISuccinctStaking} from "../interfaces/ISuccinctStaking.sol";
import {IGovernor} from "../../lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
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
/// @dev This contract accepts $iPROVE and mints $PROVER-N:
///      - Each prover has their own deployment of this contract
///        - underlying, reward, and staking are all the same across all provers
///        - id and owner are unique to each prover
///      - Stakers choose which prover to delegate to
///      - It can gain rewards from SuccinctStaking.reward()
///      - It can lose underlying by SuccinctStaking.slash()
///      - It is non-transferable outside of stake/unstake
contract SuccinctProver is ERC4626, IProver {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    error Unauthorized();

    /// @inheritdoc IProver
    address public immutable override prove;

    /// @inheritdoc IProver
    address public immutable override staking;

    /// @inheritdoc IProver
    address public immutable override governor;

    /// @inheritdoc IProver
    address public immutable override owner;

    /// @inheritdoc IProver
    uint256 public immutable override id;

    /// @inheritdoc IProver
    uint256 public immutable override stakerFeeBips;

    /// @dev Modifier to ensure that the caller is the prover owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @dev Initializes this vault with $iPROVE as the underlying, with additional parameters.
    constructor(
        address _prove,
        address _iProve,
        address _staking,
        address _governor,
        address _owner,
        uint256 _id,
        uint256 _stakerFeeBips
    )
        ERC20(string.concat(NAME_PREFIX, _id.toString()), string.concat(SYMBOL_PREFIX, _id.toString()))
        ERC4626(IERC20(_iProve))
    {
        prove = _prove;
        staking = _staking;
        governor = _governor;
        owner = _owner;
        id = _id;
        stakerFeeBips = _stakerFeeBips;

        // Self-delegate so that this prover can participate in governance.
        ERC20Votes(_iProve).delegate(address(this));
    }

    /// @inheritdoc IProver
    function transferProveToStaking(address _from, uint256 _amount) external {
        if (msg.sender != staking) {
            revert NotStaking();
        }

        IERC20(prove).safeTransferFrom(_from, staking, _amount);
    }

    /// @dev Override to prevent transfers of $PROVER-N tokens except for stake/unstake
    /// @notice Allows the prover owner to create governance proposals.
    /// @param targets The addresses of the contracts to call
    /// @param values The amounts of ETH to send
    /// @param calldatas The calldata for each call
    /// @param description The proposal description
    /// @return The proposal ID
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external onlyOwner returns (uint256) {
        return IGovernor(governor).propose(targets, values, calldatas, description);
    }

    /// @notice Allows the prover owner to cast votes on governance proposals.
    /// @param proposalId The ID of the proposal
    /// @param support The vote type (0 = Against, 1 = For, 2 = Abstain)
    /// @return The voting weight used
    function castVote(uint256 proposalId, uint8 support) external onlyOwner returns (uint256) {
        return IGovernor(governor).castVote(proposalId, support);
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
