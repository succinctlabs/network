// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdJson} from "../lib/forge-std/src/StdJson.sol";
import {FixtureLoader, Fixture, SP1ProofFixtureJson} from "./utils/FixtureLoader.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Actions} from "../src/libraries/Actions.sol";
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
    RewardAction
} from "../src/libraries/PublicValues.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {ISP1Verifier} from "../src/interfaces/ISP1Verifier.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SuccinctVAppTest is Test, FixtureLoader {
    using stdJson for string;

    SP1ProofFixtureJson public jsonFixture;
    PublicValuesStruct public fixture;

    address public verifier;
    address public PROVE;
    address public vapp;
    address public staking;

    address user1;
    address user2;
    address user3;

    function setUp() public {
        jsonFixture = loadFixture(vm, Fixture.Groth16);

        PublicValuesStruct memory _fixture =
            abi.decode(jsonFixture.publicValues, (PublicValuesStruct));
        fixture.oldRoot = _fixture.oldRoot;
        fixture.newRoot = _fixture.newRoot;
        for (uint256 i = 0; i < _fixture.actions.length; i++) {
            fixture.actions.push(_fixture.actions[i]);
        }

        verifier = address(new MockVerifier());

        // Deploy tokens
        PROVE = address(new MockERC20("Succinct", "PROVE", 18));

        // Deploy staking
        staking = address(new MockStaking(PROVE));

        // Deploy vapp
        address vappImpl = address(new SuccinctVApp());
        vapp = address(new ERC1967Proxy(vappImpl, ""));
        SuccinctVApp(vapp).initialize(address(this), PROVE, staking, verifier, jsonFixture.vkey);

        // Whitelist $PROVE for testing
        SuccinctVApp(vapp).addToken(PROVE);

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
    }

    function mockCall(bool verified) public {
        if (verified) {
            vm.mockCall(
                verifier, abi.encodeWithSelector(ISP1Verifier.verifyProof.selector), abi.encode()
            );
        } else {
            vm.mockCallRevert(
                verifier,
                abi.encodeWithSelector(ISP1Verifier.verifyProof.selector),
                "Verification failed"
            );
        }
    }

    function test_SetUp() public view {
        assertEq(SuccinctVApp(vapp).owner(), address(this));
        assertEq(SuccinctVApp(vapp).PROVE(), PROVE);
        assertEq(SuccinctVApp(vapp).staking(), staking);
        assertEq(SuccinctVApp(vapp).verifier(), verifier);
        assertEq(SuccinctVApp(vapp).vappProgramVKey(), jsonFixture.vkey);
        assertEq(SuccinctVApp(vapp).maxActionDelay(), 1 days);
        assertEq(SuccinctVApp(vapp).blockNumber(), 0);
    }

    function test_RevertIf_InitializeInvalid() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        SuccinctVApp(vapp).initialize(address(0), PROVE, staking, verifier, jsonFixture.vkey);
    }

    function test_UpdateStaking() public {
        address newStaking = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedStaking(newStaking);
        SuccinctVApp(vapp).updateStaking(newStaking);

        assertEq(SuccinctVApp(vapp).staking(), newStaking);
    }

    function test_RevertIf_UpdateStakingNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).updateStaking(address(1));
    }

    function test_UpdateVerifier() public {
        address newVerifier = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedVerifier(newVerifier);
        SuccinctVApp(vapp).updateVerifier(newVerifier);

        assertEq(SuccinctVApp(vapp).verifier(), newVerifier);
    }

    function test_RevertIf_UpdateVerifierNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).updateVerifier(address(1));
    }

    function test_UpdateActionDelay() public {
        uint64 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedMaxActionDelay(newDelay);
        SuccinctVApp(vapp).updateActionDelay(newDelay);

        assertEq(SuccinctVApp(vapp).maxActionDelay(), newDelay);
    }

    function test_RevertIf_UpdateActionDelayNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).updateActionDelay(2 days);
    }

    function test_UpdateFreezeDuration() public {
        uint64 newDuration = 3 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedFreezeDuration(newDuration);
        SuccinctVApp(vapp).updateFreezeDuration(newDuration);

        assertEq(SuccinctVApp(vapp).freezeDuration(), newDuration);
    }

    function test_RevertIf_UpdateFreezeDurationNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).updateFreezeDuration(3 days);
    }

    function test_AddToken() public {
        address token = address(99);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, true);
        SuccinctVApp(vapp).addToken(token);

        assertTrue(SuccinctVApp(vapp).whitelistedTokens(token));
    }

    function test_RevertIf_AddTokenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).addToken(address(99));
    }

    function test_RevertIf_AddTokenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).addToken(address(0));
    }

    function test_RevertIf_AddTokenAlreadyWhitelisted() public {
        address token = address(99);
        SuccinctVApp(vapp).addToken(token);

        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyWhitelisted()"));
        SuccinctVApp(vapp).addToken(token);
    }

    function test_RemoveToken() public {
        address token = address(99);
        SuccinctVApp(vapp).addToken(token);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, false);
        SuccinctVApp(vapp).removeToken(token);

        assertFalse(SuccinctVApp(vapp).whitelistedTokens(token));
    }

    function test_RevertIf_RemoveTokenNotOwner() public {
        address token = address(99);
        SuccinctVApp(vapp).addToken(token);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).removeToken(token);
    }

    function test_RevertIf_RemoveTokenNotWhitelisted() public {
        address token = address(99);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(vapp).removeToken(token);
    }

    function test_SetMinAmount() public {
        address token = PROVE;
        uint256 minAmount = 10e6; // 10 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, minAmount);
        SuccinctVApp(vapp).setMinAmount(token, minAmount);

        assertEq(SuccinctVApp(vapp).minAmounts(token), minAmount);

        // Update to a different value
        uint256 newMinAmount = 20e6; // 20 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, newMinAmount);
        SuccinctVApp(vapp).setMinAmount(token, newMinAmount);

        assertEq(SuccinctVApp(vapp).minAmounts(token), newMinAmount);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, 0);
        SuccinctVApp(vapp).setMinAmount(token, 0);

        assertEq(SuccinctVApp(vapp).minAmounts(token), 0);
    }

    function test_RevertIf_SetMinAmountZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).setMinAmount(address(0), 10e6);
    }

    function test_RevertIf_SetMinAmountNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        SuccinctVApp(vapp).setMinAmount(PROVE, 10e6);
    }

    function test_Fork() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, newRoot, bytes32(0));
        emit ISuccinctVApp.Fork(newVkey, 1, newRoot, bytes32(0));

        (uint64 _block, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            SuccinctVApp(vapp).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(vapp).blockNumber(), 1);
        assertEq(SuccinctVApp(vapp).roots(1), newRoot);
        assertEq(_block, 1);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(0));
    }

    function test_RevertIf_ForkUnauthorized() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        SuccinctVApp(vapp).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);
    }

    function test_ForkAfterUpdateState() public {
        // Update state
        mockCall(true);

        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });

        SuccinctVApp(vapp).updateState(abi.encode(publicValues1), jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).blockNumber(), 1);
        assertEq(SuccinctVApp(vapp).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(vapp).vappProgramVKey(), jsonFixture.vkey);

        // Fork
        bytes32 newVkey = bytes32(uint256(99));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, newRoot, bytes32(uint256(1)));
        emit ISuccinctVApp.Fork(newVkey, 2, newRoot, bytes32(uint256(1)));

        (uint64 blockNum, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            SuccinctVApp(vapp).fork(newVkey, newRoot, abi.encode(publicValues2), jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(vapp).blockNumber(), 2);
        assertEq(SuccinctVApp(vapp).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(vapp).roots(2), newRoot);
        assertEq(blockNum, 2);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(uint256(1)));
    }

    function test_Deposit() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(address(this), amount);
        MockERC20(PROVE).approve(address(vapp), amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), amount);
        assertEq(MockERC20(PROVE).balanceOf(address(vapp)), 0);
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
        (, ReceiptStatus status,,) = SuccinctVApp(vapp).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.None));

        // Deposit
        bytes memory data =
            abi.encode(DepositAction({account: address(this), token: PROVE, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.Deposit, data);
        SuccinctVApp(vapp).deposit(address(this), PROVE, amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), 0);
        assertEq(MockERC20(PROVE).balanceOf(address(vapp)), amount);
        assertEq(SuccinctVApp(vapp).currentReceipt(), 1);
        (, status,,) = SuccinctVApp(vapp).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Update state with deposit action
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: 1,
            data: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(1, ActionType.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.newRoot, publicValues.oldRoot);

        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(vapp).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 1);
    }

    function test_RevertIf_DepositZeroAddress() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(user1, amount);

        vm.startPrank(user1);
        MockERC20(PROVE).approve(address(vapp), amount);

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).deposit(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_DepositNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        nonWhitelistedToken.mint(user1, amount);

        vm.startPrank(user1);
        nonWhitelistedToken.approve(address(vapp), amount);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(vapp).deposit(user1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_DepositBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 depositAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(vapp).setMinAmount(PROVE, minAmount);

        // Try to deposit below minimum
        MockERC20(PROVE).mint(user1, depositAmount);

        vm.startPrank(user1);
        MockERC20(PROVE).approve(address(vapp), depositAmount);

        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        SuccinctVApp(vapp).deposit(user1, PROVE, depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_Withdraw() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(user1, amount);
        vm.startPrank(user1);
        MockERC20(PROVE).approve(address(vapp), amount);
        uint64 depositReceipt = SuccinctVApp(vapp).deposit(user1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: user1, token: PROVE, amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        depositPublicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: depositReceipt,
            data: depositData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(depositReceipt, ActionType.Deposit, depositData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(user2);
        bytes memory withdrawData =
            abi.encode(WithdrawAction({account: user2, token: PROVE, amount: amount, to: user2}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(vapp).withdraw(user2, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(vapp).receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        withdrawPublicValues.actions[0] = Action({
            action: ActionType.Withdraw,
            status: ReceiptStatus.Completed,
            receipt: withdrawReceipt,
            data: withdrawData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(withdrawReceipt, ActionType.Withdraw, withdrawData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, withdrawPublicValues.newRoot, withdrawPublicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claims created
        assertEq(SuccinctVApp(vapp).withdrawalClaims(user2, PROVE), amount);
        assertEq(SuccinctVApp(vapp).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 2);

        // Claim withdrawal
        assertEq(MockERC20(PROVE).balanceOf(user2), 0);
        vm.startPrank(user2);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(user2, PROVE, user2, amount);
        uint256 claimedAmount = SuccinctVApp(vapp).claimWithdrawal(user2, PROVE);
        vm.stopPrank();

        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(user2), amount); // User2 now has the PROVE
        assertEq(SuccinctVApp(vapp).withdrawalClaims(user2, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(vapp).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Reattempt claim
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(vapp).claimWithdrawal(user2, PROVE);
        vm.stopPrank();
    }

    function test_WithdrawTo() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(user1, amount);
        vm.startPrank(user1);
        MockERC20(PROVE).approve(address(vapp), amount);
        uint64 depositReceipt = SuccinctVApp(vapp).deposit(user1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: user1, token: PROVE, amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        depositPublicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: depositReceipt,
            data: depositData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(depositReceipt, ActionType.Deposit, depositData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw with a different recipient (user2 initiates withdrawal to user3)
        vm.startPrank(user2);
        bytes memory withdrawData =
            abi.encode(WithdrawAction({account: user2, token: PROVE, amount: amount, to: user3}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(vapp).withdraw(user3, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(vapp).receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        withdrawPublicValues.actions[0] = Action({
            action: ActionType.Withdraw,
            status: ReceiptStatus.Completed,
            receipt: withdrawReceipt,
            data: withdrawData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(withdrawReceipt, ActionType.Withdraw, withdrawData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, withdrawPublicValues.newRoot, withdrawPublicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claim was created for user3, not user2
        assertEq(SuccinctVApp(vapp).withdrawalClaims(user2, PROVE), 0);
        assertEq(SuccinctVApp(vapp).withdrawalClaims(user3, PROVE), amount);
        assertEq(SuccinctVApp(vapp).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 2);

        // Claim withdrawal as user3
        assertEq(MockERC20(PROVE).balanceOf(user3), 0);
        vm.startPrank(user3);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(user3, PROVE, user3, amount);
        uint256 claimedAmount = SuccinctVApp(vapp).claimWithdrawal(user3, PROVE);
        vm.stopPrank();

        // Verify claim was successful, and user3 has the funds
        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(user3), amount); // User3 now has the PROVE
        assertEq(MockERC20(PROVE).balanceOf(user2), 0); // User2 has nothing
        assertEq(SuccinctVApp(vapp).withdrawalClaims(user3, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(vapp).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Attempt to claim again should fail
        vm.startPrank(user3);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(vapp).claimWithdrawal(user3, PROVE);
        vm.stopPrank();

        // User2 shouldn't be able to claim either
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(vapp).claimWithdrawal(user2, PROVE);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawZeroAddress() public {
        uint256 amount = 100e6;

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).withdraw(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(vapp).withdraw(user1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 withdrawAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(vapp).setMinAmount(PROVE, minAmount);

        // Try to withdraw below minimum
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        SuccinctVApp(vapp).withdraw(user1, PROVE, withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_AddDelegatedSigner() public {
        // Setup user1 as a prover owner
        MockStaking(staking).setHasProver(user1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add first delegated signer
        vm.startPrank(user1);
        bytes memory addSignerData1 = abi.encode(AddSignerAction({owner: user1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.AddSigner, addSignerData1);
        uint64 addSignerReceipt1 = SuccinctVApp(vapp).addDelegatedSigner(signer1);
        vm.stopPrank();

        assertEq(addSignerReceipt1, 1);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(vapp).receipts(addSignerReceipt1);
        assertEq(uint8(actionType), uint8(ActionType.AddSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, addSignerData1);

        // Process the first addSigner action through state update
        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues1.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt1,
            data: addSignerData1
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues1.newRoot, publicValues1.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(vapp).receipts(addSignerReceipt1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 1);

        // Verify first delegated signer was added
        address[] memory signers = SuccinctVApp(vapp).getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer1);
        assertTrue(SuccinctVApp(vapp).usedSigners(signer1));

        // Add second delegated signer
        vm.startPrank(user1);
        bytes memory addSignerData2 = abi.encode(AddSignerAction({owner: user1, signer: signer2}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.AddSigner, addSignerData2);
        uint64 addSignerReceipt2 = SuccinctVApp(vapp).addDelegatedSigner(signer2);
        vm.stopPrank();

        assertEq(addSignerReceipt2, 2);
        (actionType, status,,) = SuccinctVApp(vapp).receipts(addSignerReceipt2);
        assertEq(uint8(actionType), uint8(ActionType.AddSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Process the second addSigner action through state update
        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        publicValues2.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt2,
            data: addSignerData2
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues2.newRoot, publicValues2.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues2), jsonFixture.proof);

        // Verify second receipt status updated
        (, status,,) = SuccinctVApp(vapp).receipts(addSignerReceipt2);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 2);

        // Verify both delegated signers are in the array
        signers = SuccinctVApp(vapp).getDelegatedSigners(user1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(SuccinctVApp(vapp).usedSigners(signer1));
        assertTrue(SuccinctVApp(vapp).usedSigners(signer2));
    }

    function test_RevertIf_AddDelegatedSignerNotProverOwner() public {
        // user1 is not a prover owner
        address signer = makeAddr("signer");

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerZeroAddress() public {
        // Setup user1 as a prover owner
        MockStaking(staking).setHasProver(user1, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(vapp).addDelegatedSigner(address(0));
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerIsProver() public {
        // Setup user1 as a prover owner and user2 as a prover
        MockStaking(staking).setHasProver(user1, true);
        MockStaking(staking).setIsProver(user2, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(vapp).addDelegatedSigner(user2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerHasProver() public {
        // Setup user1 and user2 as prover owners
        MockStaking(staking).setHasProver(user1, true);
        MockStaking(staking).setHasProver(user2, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(vapp).addDelegatedSigner(user2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerAlreadyUsed() public {
        // Setup user1 and user2 as prover owners
        MockStaking(staking).setHasProver(user1, true);
        MockStaking(staking).setHasProver(user2, true);

        address signer = makeAddr("signer");

        // Add signer to user1
        vm.startPrank(user1);
        SuccinctVApp(vapp).addDelegatedSigner(signer);
        vm.stopPrank();

        // Try to add the same signer to user2
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(vapp).addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify only one receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 1);
    }

    function test_RemoveDelegatedSigner() public {
        // Setup user1 as a prover owner and add two delegated signers (one at a time to avoid stack issues)
        MockStaking(staking).setHasProver(user1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add signers one by one to avoid stack too deep issues
        vm.startPrank(user1);
        uint64 addSignerReceipt1 = SuccinctVApp(vapp).addDelegatedSigner(signer1);
        vm.stopPrank();

        // Process the first addSigner action
        bytes memory addSignerData1 = abi.encode(AddSignerAction({owner: user1, signer: signer1}));
        PublicValuesStruct memory addPublicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        addPublicValues1.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt1,
            data: addSignerData1
        });

        mockCall(true);
        SuccinctVApp(vapp).updateState(abi.encode(addPublicValues1), jsonFixture.proof);

        // Add second signer
        vm.startPrank(user1);
        uint64 addSignerReceipt2 = SuccinctVApp(vapp).addDelegatedSigner(signer2);
        vm.stopPrank();

        // Process the second addSigner action
        bytes memory addSignerData2 = abi.encode(AddSignerAction({owner: user1, signer: signer2}));
        PublicValuesStruct memory addPublicValues2 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        addPublicValues2.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt2,
            data: addSignerData2
        });

        mockCall(true);
        SuccinctVApp(vapp).updateState(abi.encode(addPublicValues2), jsonFixture.proof);

        // Verify both signers were added
        address[] memory signers = SuccinctVApp(vapp).getDelegatedSigners(user1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(SuccinctVApp(vapp).usedSigners(signer1));
        assertTrue(SuccinctVApp(vapp).usedSigners(signer2));
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 2);

        // Now, remove the first delegated signer
        vm.startPrank(user1);
        bytes memory removeSignerData =
            abi.encode(RemoveSignerAction({owner: user1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(3, ActionType.RemoveSigner, removeSignerData);
        uint64 removeSignerReceipt = SuccinctVApp(vapp).removeDelegatedSigner(signer1);
        vm.stopPrank();

        // Check receipt details
        (ActionType actionType, ReceiptStatus status,,) =
            SuccinctVApp(vapp).receipts(removeSignerReceipt);
        assertEq(uint8(actionType), uint8(ActionType.RemoveSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Verify first signer was removed after the removal operation
        signers = SuccinctVApp(vapp).getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer2); // signer2 should remain

        // Check usage flags
        bool isSigner1Used = SuccinctVApp(vapp).usedSigners(signer1);
        bool isSigner2Used = SuccinctVApp(vapp).usedSigners(signer2);
        assertFalse(isSigner1Used);
        assertTrue(isSigner2Used);

        // Process the removeSigner action through state update
        PublicValuesStruct memory removePublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(2)),
            newRoot: bytes32(uint256(3)),
            timestamp: uint64(block.timestamp)
        });
        removePublicValues.actions[0] = Action({
            action: ActionType.RemoveSigner,
            status: ReceiptStatus.Completed,
            receipt: removeSignerReceipt,
            data: removeSignerData
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(3, removePublicValues.newRoot, removePublicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(removePublicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(vapp).receipts(removeSignerReceipt);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(vapp).finalizedReceipt(), 3);
    }

    function test_RevertIf_RemoveDelegatedSignerNotOwner() public {
        // Setup user1 as a prover owner and add a delegated signer
        MockStaking(staking).setHasProver(user1, true);
        MockStaking(staking).setHasProver(user2, true);
        address signer = makeAddr("signer");

        vm.prank(user1);
        SuccinctVApp(vapp).addDelegatedSigner(signer);

        // User2 tries to remove user1's signer
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(vapp).removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify signer is still in user1's delegated signers
        address[] memory signers = SuccinctVApp(vapp).getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer);
        assertTrue(SuccinctVApp(vapp).usedSigners(signer));
    }

    function test_RevertIf_RemoveDelegatedSignerNotRegistered() public {
        // Setup user1 as a prover owner
        MockStaking(staking).setHasProver(user1, true);
        address signer = makeAddr("signer");

        // Try to remove a signer that was never added
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(vapp).removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(vapp).currentReceipt(), 0);
    }

    function test_EmergencyWithdrawal() public {
        mockCall(true);

        // Failover so that we can use the hardcoded usdc in the merkle root
        address testUsdc = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        if (testUsdc != PROVE) {
            vm.etch(testUsdc, PROVE.code);
            SuccinctVApp(vapp).addToken(testUsdc);
        }
        MockERC20(testUsdc).mint(address(this), 100);
        MockERC20(testUsdc).approve(address(vapp), 100);
        SuccinctVApp(vapp).deposit(address(this), address(testUsdc), 100);

        // The merkle tree
        bytes32 root = 0xc53421d840beb11a0382b8d5bbf524da79ddb96b11792c3812276a05300e276e;
        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x97166dee2bb3b38545a732e4fc42a7d745eaeb55be08c08b7dfad28961af339b;
        proof[1] = 0xd530f51fd96943359dc951ce6d19212cc540a321562a0bcd7e1747700dce0ec9;
        proof[2] = 0x5517ae9ffdaac5507c9bc6990aa6637b3ce06ebfbdb08f4208c73dc2fe2d20a9;
        proof[3] = 0x35b34cde80bb3bd84dbd6d84ccfa8b739908f2c632802af348512215e8eb7dd6;

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: root,
            timestamp: uint64(block.timestamp)
        });
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);

        vm.warp(block.timestamp + SuccinctVApp(vapp).freezeDuration() + 1);

        // Leaf debug
        address user = 0x4F06869E36F2De69d97e636E52B45F07A91b4fa6;
        bytes32 leaf = sha256(abi.encodePacked(user, uint256(100)));
        console.logBytes32(leaf);

        // Withdraw
        vm.startPrank(user);
        SuccinctVApp(vapp).emergencyWithdraw(address(testUsdc), 100, proof);

        // Claim withdrawal
        assertEq(ERC20(testUsdc).balanceOf(user), 0);
        SuccinctVApp(vapp).claimWithdrawal(user, address(testUsdc));
        assertEq(ERC20(testUsdc).balanceOf(user), 100);
        vm.stopPrank();
    }

    function test_UpdateStateValid() public {
        mockCall(true);

        assertEq(SuccinctVApp(vapp).blockNumber(), 0);
        assertEq(SuccinctVApp(vapp).roots(0), bytes32(0));
        assertEq(SuccinctVApp(vapp).roots(1), bytes32(0));
        assertEq(SuccinctVApp(vapp).root(), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.newRoot, fixture.oldRoot);
        SuccinctVApp(vapp).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).blockNumber(), 1);
        assertEq(SuccinctVApp(vapp).roots(0), bytes32(0));
        assertEq(SuccinctVApp(vapp).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(vapp).root(), fixture.newRoot);
    }

    function test_UpdateStateTwice() public {
        mockCall(true);

        SuccinctVApp(vapp).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).blockNumber(), 1);
        assertEq(SuccinctVApp(vapp).roots(0), bytes32(0));
        assertEq(SuccinctVApp(vapp).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(vapp).roots(2), bytes32(0));
        assertEq(SuccinctVApp(vapp).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: fixture.newRoot,
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues.newRoot, publicValues.oldRoot);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(vapp).blockNumber(), 2);
        assertEq(SuccinctVApp(vapp).roots(0), bytes32(0));
        assertEq(SuccinctVApp(vapp).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(vapp).roots(2), publicValues.newRoot);
        assertEq(SuccinctVApp(vapp).root(), publicValues.newRoot);
    }

    function test_RevertIf_UpdateStateInvalid() public {
        bytes memory fakeProof = new bytes(jsonFixture.proof.length);

        mockCall(false);
        vm.expectRevert();
        SuccinctVApp(vapp).updateState(jsonFixture.publicValues, fakeProof);
    }

    function test_RevertIf_UpdateStateInvalidRoot() public {
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(0),
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);
        vm.expectRevert(ISuccinctVApp.InvalidRoot.selector);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateInvalidOldRoot() public {
        mockCall(true);
        SuccinctVApp(vapp).updateState(jsonFixture.publicValues, jsonFixture.proof);
        assertEq(SuccinctVApp(vapp).blockNumber(), 1);
        assertEq(SuccinctVApp(vapp).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(999)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectRevert(ISuccinctVApp.InvalidOldRoot.selector);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateInvalidTimestampFuture() public {
        mockCall(true);

        // Create public values with a future timestamp
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp + 1 days) // Timestamp in the future
        });

        vm.expectRevert(ISuccinctVApp.InvalidTimestamp.selector);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateTimestampInPast() public {
        mockCall(true);

        // First update with current timestamp
        uint64 initialTime = uint64(block.timestamp);
        PublicValuesStruct memory initialPublicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: initialTime
        });

        SuccinctVApp(vapp).updateState(abi.encode(initialPublicValues), jsonFixture.proof);
        assertEq(SuccinctVApp(vapp).blockNumber(), 1);

        // Capture the timestamp that was recorded
        uint64 recordedTimestamp = SuccinctVApp(vapp).timestamps(1);

        // Create public values with a timestamp earlier than the previous block
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: recordedTimestamp - 1 // Timestamp earlier than previous block
        });

        vm.expectRevert(ISuccinctVApp.TimestampInPast.selector);
        SuccinctVApp(vapp).updateState(abi.encode(publicValues), jsonFixture.proof);
    }
}
