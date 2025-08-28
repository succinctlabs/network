// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {
//     IERC20,
//     SafeERC20
// } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
// import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
// import {Pausable} from "../lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
// import {MerkleProof} from
//     "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
// import {ISuccinctRewards} from "./interfaces/ISuccinctRewards.sol";

// /// @title SuccinctRewards
// /// @author Succinct Foundation
// /// @notice Allows anyone to claim a token if they exist in a merkle root.
// contract SuccinctRewards is Ownable, Pausable, ISuccinctRewards {
//     using SafeERC20 for IERC20;

//     /// @inheritdoc ISuccinctRewards
//     address public immutable override token;

//     /// @inheritdoc ISuccinctRewards
//     bytes32 public immutable override merkleRoot;

//     /// @inheritdoc ISuccinctRewards
//     uint256 public immutable endTime;

//     /// @dev This is a packed array of booleans.
//     mapping(uint256 => uint256) private claimedBitMap;

//     /// @dev The token and merkle root can only be set once in the constructor.
//     constructor(address _token, bytes32 _merkleRoot, uint256 _endTime, address _owner)
//         Ownable(_owner)
//     {
//         if (_endTime <= block.timestamp) revert EndTimeInPast();
//         token = _token;
//         merkleRoot = _merkleRoot;
//         endTime = _endTime;
//         _pause();
//     }

//     /// @inheritdoc ISuccinctRewards
//     function isClaimed(uint256 index) public view override returns (bool) {
//         uint256 claimedWordIndex = index / 256;
//         uint256 claimedBitIndex = index % 256;
//         uint256 claimedWord = claimedBitMap[claimedWordIndex];
//         uint256 mask = (1 << claimedBitIndex);
//         return claimedWord & mask == mask;
//     }

//     /// @dev Marks an index as claimed.
//     function _setClaimed(uint256 index) private {
//         uint256 claimedWordIndex = index / 256;
//         uint256 claimedBitIndex = index % 256;
//         claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
//     }

//     /// @inheritdoc ISuccinctRewards
//     function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof)
//         public
//         virtual
//         override
//         whenNotPaused
//     {
//         // Ensure the claim window is not finished.
//         if (block.timestamp > endTime) revert ClaimWindowFinished();

//         // Ensure the index has not been marked as claimed.
//         if (isClaimed(index)) revert AlreadyClaimed();

//         // Verify the merkle proof.
//         bytes32 node = keccak256(abi.encodePacked(index, account, amount));
//         if (!MerkleProof.verify(merkleProof, merkleRoot, node)) revert InvalidProof();

//         // Mark the index as claimed and transfer the token.
//         _setClaimed(index);
//         IERC20(token).safeTransfer(account, amount);

//         // Emit the event.
//         emit Claimed(index, account, amount);
//     }

//     /// @inheritdoc ISuccinctRewards
//     function withdraw(address recipient) external onlyOwner {
//         if (block.timestamp < endTime) revert NoWithdrawDuringClaim();
//         IERC20(token).safeTransfer(recipient, IERC20(token).balanceOf(address(this)));
//     }

//     /// @inheritdoc ISuccinctRewards
//     function pause() external whenNotPaused onlyOwner {
//         _pause();
//     }

//     /// @inheritdoc ISuccinctRewards
//     function unpause() external whenPaused onlyOwner {
//         _unpause();
//     }
// }
