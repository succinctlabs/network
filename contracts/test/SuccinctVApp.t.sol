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

    // Fixtures
    SP1ProofFixtureJson public jsonFixture;
    PublicValuesStruct public fixture;

    // EOAs
    address REQUESTER_1;
    address REQUESTER_2;
    address REQUESTER_3;

    // Contracts
    address public VERIFIER;
    address public PROVE;
    address public VAPP;
    address public STAKING;

    function setUp() public {
        // Load fixtures
        jsonFixture = loadFixture(vm, Fixture.Groth16);

        PublicValuesStruct memory _fixture =
            abi.decode(jsonFixture.publicValues, (PublicValuesStruct));
        fixture.oldRoot = _fixture.oldRoot;
        fixture.newRoot = _fixture.newRoot;
        for (uint256 i = 0; i < _fixture.actions.length; i++) {
            fixture.actions.push(_fixture.actions[i]);
        }

        // Create requesters
        REQUESTER_1 = makeAddr("requester1");
        REQUESTER_2 = makeAddr("requester2");
        REQUESTER_3 = makeAddr("requester3");

        // Deploy verifier
        VERIFIER = address(new MockVerifier());

        // Deploy tokens
        PROVE = address(new MockERC20("Succinct", "PROVE", 18));

        // Deploy staking
        STAKING = address(new MockStaking(PROVE));

        // Deploy vapp
        address vappImpl = address(new SuccinctVApp());
        VAPP = address(new ERC1967Proxy(vappImpl, ""));
        SuccinctVApp(VAPP).initialize(address(this), PROVE, STAKING, VERIFIER, jsonFixture.vkey);

        // Whitelist $PROVE
        SuccinctVApp(VAPP).addToken(PROVE);
    }

    function mockCall(bool verified) public {
        if (verified) {
            vm.mockCall(
                VERIFIER, abi.encodeWithSelector(ISP1Verifier.verifyProof.selector), abi.encode()
            );
        } else {
            vm.mockCallRevert(
                VERIFIER,
                abi.encodeWithSelector(ISP1Verifier.verifyProof.selector),
                "Verification failed"
            );
        }
    }

    function test_SetUp() public view {
        assertEq(SuccinctVApp(VAPP).owner(), address(this));
        assertEq(SuccinctVApp(VAPP).PROVE(), PROVE);
        assertEq(SuccinctVApp(VAPP).STAKING(), STAKING);
        assertEq(SuccinctVApp(VAPP).verifier(), VERIFIER);
        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), jsonFixture.vkey);
        assertEq(SuccinctVApp(VAPP).maxActionDelay(), 1 days);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
    }

    function test_RevertIf_InitializeInvalid() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        SuccinctVApp(VAPP).initialize(address(0), PROVE, STAKING, VERIFIER, jsonFixture.vkey);
    }

    function test_UpdateStaking() public {
        address newStaking = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedStaking(newStaking);
        SuccinctVApp(VAPP).updateStaking(newStaking);

        assertEq(SuccinctVApp(VAPP).STAKING(), newStaking);
    }

    function test_RevertIf_UpdateStakingNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateStaking(address(1));
    }

    function test_UpdateVerifier() public {
        address newVerifier = address(1);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedVerifier(newVerifier);
        SuccinctVApp(VAPP).updateVerifier(newVerifier);

        assertEq(SuccinctVApp(VAPP).verifier(), newVerifier);
    }

    function test_RevertIf_UpdateVerifierNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateVerifier(address(1));
    }

    function test_UpdateActionDelay() public {
        uint64 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedMaxActionDelay(newDelay);
        SuccinctVApp(VAPP).updateActionDelay(newDelay);

        assertEq(SuccinctVApp(VAPP).maxActionDelay(), newDelay);
    }

    function test_RevertIf_UpdateActionDelayNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateActionDelay(2 days);
    }

    function test_UpdateFreezeDuration() public {
        uint64 newDuration = 3 days;

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.UpdatedFreezeDuration(newDuration);
        SuccinctVApp(VAPP).updateFreezeDuration(newDuration);

        assertEq(SuccinctVApp(VAPP).freezeDuration(), newDuration);
    }

    function test_RevertIf_UpdateFreezeDurationNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).updateFreezeDuration(3 days);
    }

    function test_AddToken() public {
        address token = address(99);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, true);
        SuccinctVApp(VAPP).addToken(token);

        assertTrue(SuccinctVApp(VAPP).whitelistedTokens(token));
    }

    function test_RevertIf_AddTokenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).addToken(address(99));
    }

    function test_RevertIf_AddTokenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).addToken(address(0));
    }

    function test_RevertIf_AddTokenAlreadyWhitelisted() public {
        address token = address(99);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyWhitelisted()"));
        SuccinctVApp(VAPP).addToken(token);
    }

    function test_RemoveToken() public {
        address token = address(99);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TokenWhitelist(token, false);
        SuccinctVApp(VAPP).removeToken(token);

        assertFalse(SuccinctVApp(VAPP).whitelistedTokens(token));
    }

    function test_RevertIf_RemoveTokenNotOwner() public {
        address token = address(99);
        SuccinctVApp(VAPP).addToken(token);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).removeToken(token);
    }

    function test_RevertIf_RemoveTokenNotWhitelisted() public {
        address token = address(99);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(VAPP).removeToken(token);
    }

    function test_SetMinAmount() public {
        address token = PROVE;
        uint256 minAmount = 10e6; // 10 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, minAmount);
        SuccinctVApp(VAPP).setMinAmount(token, minAmount);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), minAmount);

        // Update to a different value
        uint256 newMinAmount = 20e6; // 20 PROVE

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, newMinAmount);
        SuccinctVApp(VAPP).setMinAmount(token, newMinAmount);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), newMinAmount);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.MinAmountUpdated(token, 0);
        SuccinctVApp(VAPP).setMinAmount(token, 0);

        assertEq(SuccinctVApp(VAPP).minAmounts(token), 0);
    }

    function test_RevertIf_SetMinAmountZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).setMinAmount(address(0), 10e6);
    }

    function test_RevertIf_SetMinAmountNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).setMinAmount(PROVE, 10e6);
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
            SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), newRoot);
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

        vm.prank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);
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

        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), jsonFixture.vkey);

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
            SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues2), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).roots(2), newRoot);
        assertEq(blockNum, 2);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(uint256(1)));
    }

    function test_Deposit() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(address(this), amount);
        MockERC20(PROVE).approve(address(VAPP), amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), amount);
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), 0);
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
        (, ReceiptStatus status,,) = SuccinctVApp(VAPP).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.None));

        // Deposit
        bytes memory data =
            abi.encode(DepositAction({account: address(this), token: PROVE, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.Deposit, data);
        SuccinctVApp(VAPP).deposit(address(this), PROVE, amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), 0);
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), amount);
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 1);
        (, status,,) = SuccinctVApp(VAPP).receipts(1);
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

        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
    }

    function test_RevertIf_DepositZeroAddress() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);

        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).deposit(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_DepositNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        nonWhitelistedToken.mint(REQUESTER_1, amount);

        vm.startPrank(REQUESTER_1);
        nonWhitelistedToken.approve(address(VAPP), amount);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(VAPP).deposit(REQUESTER_1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_DepositBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 depositAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).setMinAmount(PROVE, minAmount);

        // Try to deposit below minimum
        MockERC20(PROVE).mint(REQUESTER_1, depositAmount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), depositAmount);

        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_Withdraw() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: REQUESTER_1, token: PROVE, amount: amount}));
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
        SuccinctVApp(VAPP).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: REQUESTER_2, token: PROVE, amount: amount, to: REQUESTER_2})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(VAPP).withdraw(REQUESTER_2, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(withdrawReceipt);
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
        SuccinctVApp(VAPP).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claims created
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), amount);
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Claim withdrawal
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), 0);
        vm.startPrank(REQUESTER_2);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(REQUESTER_2, PROVE, REQUESTER_2, amount);
        uint256 claimedAmount = SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();

        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), amount); // User2 now has the PROVE
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Reattempt claim
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();
    }

    function test_WithdrawTo() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: REQUESTER_1, token: PROVE, amount: amount}));
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
        SuccinctVApp(VAPP).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw with a different recipient (user2 initiates withdrawal to user3)
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: REQUESTER_2, token: PROVE, amount: amount, to: REQUESTER_3})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(VAPP).withdraw(REQUESTER_3, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(withdrawReceipt);
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
        SuccinctVApp(VAPP).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claim was created for user3, not user2
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), 0);
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_3, PROVE), amount);
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Claim withdrawal as user3
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_3), 0);
        vm.startPrank(REQUESTER_3);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(REQUESTER_3, PROVE, REQUESTER_3, amount);
        uint256 claimedAmount = SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_3, PROVE);
        vm.stopPrank();

        // Verify claim was successful, and user3 has the funds
        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_3), amount); // User3 now has the PROVE
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), 0); // User2 has nothing
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_3, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Attempt to claim again should fail
        vm.startPrank(REQUESTER_3);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_3, PROVE);
        vm.stopPrank();

        // User2 shouldn't be able to claim either
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawZeroAddress() public {
        uint256 amount = 100e6;

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).withdraw(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        SuccinctVApp(VAPP).withdraw(REQUESTER_1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 withdrawAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).setMinAmount(PROVE, minAmount);

        // Try to withdraw below minimum
        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        SuccinctVApp(VAPP).withdraw(REQUESTER_1, PROVE, withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_AddDelegatedSigner() public {
        // Setup user1 as a prover owner
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add first delegated signer
        vm.startPrank(REQUESTER_1);
        bytes memory addSignerData1 =
            abi.encode(AddSignerAction({owner: REQUESTER_1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.AddSigner, addSignerData1);
        uint64 addSignerReceipt1 = SuccinctVApp(VAPP).addDelegatedSigner(signer1);
        vm.stopPrank();

        assertEq(addSignerReceipt1, 1);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(addSignerReceipt1);
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
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(addSignerReceipt1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);

        // Verify first delegated signer was added
        address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer1);
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));

        // Add second delegated signer
        vm.startPrank(REQUESTER_1);
        bytes memory addSignerData2 =
            abi.encode(AddSignerAction({owner: REQUESTER_1, signer: signer2}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.AddSigner, addSignerData2);
        uint64 addSignerReceipt2 = SuccinctVApp(VAPP).addDelegatedSigner(signer2);
        vm.stopPrank();

        assertEq(addSignerReceipt2, 2);
        (actionType, status,,) = SuccinctVApp(VAPP).receipts(addSignerReceipt2);
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
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues2), jsonFixture.proof);

        // Verify second receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(addSignerReceipt2);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Verify both delegated signers are in the array
        signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer2));
    }

    function test_RevertIf_AddDelegatedSignerNotProverOwner() public {
        // user1 is not a prover owner
        address signer = makeAddr("signer");

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerZeroAddress() public {
        // Setup user1 as a prover owner
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        SuccinctVApp(VAPP).addDelegatedSigner(address(0));
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerIsProver() public {
        // Setup user1 as a prover owner and user2 as a prover
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        MockStaking(STAKING).setIsProver(REQUESTER_2, true);

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(VAPP).addDelegatedSigner(REQUESTER_2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerHasProver() public {
        // Setup user1 and user2 as prover owners
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        MockStaking(STAKING).setHasProver(REQUESTER_2, true);

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(VAPP).addDelegatedSigner(REQUESTER_2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerAlreadyUsed() public {
        // Setup user1 and user2 as prover owners
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        MockStaking(STAKING).setHasProver(REQUESTER_2, true);

        address signer = makeAddr("signer");

        // Add signer to user1
        vm.startPrank(REQUESTER_1);
        SuccinctVApp(VAPP).addDelegatedSigner(signer);
        vm.stopPrank();

        // Try to add the same signer to user2
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(VAPP).addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify only one receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 1);
    }

    function test_RemoveDelegatedSigner() public {
        // Setup user1 as a prover owner and add two delegated signers (one at a time to avoid stack issues)
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add signers one by one to avoid stack too deep issues
        vm.startPrank(REQUESTER_1);
        uint64 addSignerReceipt1 = SuccinctVApp(VAPP).addDelegatedSigner(signer1);
        vm.stopPrank();

        // Process the first addSigner action
        bytes memory addSignerData1 =
            abi.encode(AddSignerAction({owner: REQUESTER_1, signer: signer1}));
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
        SuccinctVApp(VAPP).updateState(abi.encode(addPublicValues1), jsonFixture.proof);

        // Add second signer
        vm.startPrank(REQUESTER_1);
        uint64 addSignerReceipt2 = SuccinctVApp(VAPP).addDelegatedSigner(signer2);
        vm.stopPrank();

        // Process the second addSigner action
        bytes memory addSignerData2 =
            abi.encode(AddSignerAction({owner: REQUESTER_1, signer: signer2}));
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
        SuccinctVApp(VAPP).updateState(abi.encode(addPublicValues2), jsonFixture.proof);

        // Verify both signers were added
        address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer2));
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Now, remove the first delegated signer
        vm.startPrank(REQUESTER_1);
        bytes memory removeSignerData =
            abi.encode(RemoveSignerAction({owner: REQUESTER_1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(3, ActionType.RemoveSigner, removeSignerData);
        uint64 removeSignerReceipt = SuccinctVApp(VAPP).removeDelegatedSigner(signer1);
        vm.stopPrank();

        // Check receipt details
        (ActionType actionType, ReceiptStatus status,,) =
            SuccinctVApp(VAPP).receipts(removeSignerReceipt);
        assertEq(uint8(actionType), uint8(ActionType.RemoveSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Verify first signer was removed after the removal operation
        signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer2); // signer2 should remain

        // Check usage flags
        bool isSigner1Used = SuccinctVApp(VAPP).usedSigners(signer1);
        bool isSigner2Used = SuccinctVApp(VAPP).usedSigners(signer2);
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
        SuccinctVApp(VAPP).updateState(abi.encode(removePublicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(removeSignerReceipt);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 3);
    }

    function test_RevertIf_RemoveDelegatedSignerNotOwner() public {
        // Setup user1 as a prover owner and add a delegated signer
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        MockStaking(STAKING).setHasProver(REQUESTER_2, true);
        address signer = makeAddr("signer");

        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).addDelegatedSigner(signer);

        // User2 tries to remove user1's signer
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(VAPP).removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify signer is still in user1's delegated signers
        address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer);
        assertTrue(SuccinctVApp(VAPP).usedSigners(signer));
    }

    function test_RevertIf_RemoveDelegatedSignerNotRegistered() public {
        // Setup user1 as a prover owner
        MockStaking(STAKING).setHasProver(REQUESTER_1, true);
        address signer = makeAddr("signer");

        // Try to remove a signer that was never added
        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        SuccinctVApp(VAPP).removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_EmergencyWithdrawal() public {
        mockCall(true);

        // Failover so that we can use the hardcoded usdc in the merkle root
        address testUsdc = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        if (testUsdc != PROVE) {
            vm.etch(testUsdc, PROVE.code);
            SuccinctVApp(VAPP).addToken(testUsdc);
        }
        MockERC20(testUsdc).mint(address(this), 100);
        MockERC20(testUsdc).approve(address(VAPP), 100);
        SuccinctVApp(VAPP).deposit(address(this), address(testUsdc), 100);

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
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        vm.warp(block.timestamp + SuccinctVApp(VAPP).freezeDuration() + 1);

        // Leaf debug
        address user = 0x4F06869E36F2De69d97e636E52B45F07A91b4fa6;
        bytes32 leaf = sha256(abi.encodePacked(user, uint256(100)));
        console.logBytes32(leaf);

        // Withdraw
        vm.startPrank(user);
        SuccinctVApp(VAPP).emergencyWithdraw(address(testUsdc), 100, proof);

        // Claim withdrawal
        assertEq(ERC20(testUsdc).balanceOf(user), 0);
        SuccinctVApp(VAPP).claimWithdrawal(user, address(testUsdc));
        assertEq(ERC20(testUsdc).balanceOf(user), 100);
        vm.stopPrank();
    }

    function test_UpdateStateValid() public {
        mockCall(true);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.newRoot, fixture.oldRoot);
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);
    }

    function test_UpdateStateTwice() public {
        mockCall(true);

        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: fixture.newRoot,
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues.newRoot, publicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
    }

    function test_RevertIf_UpdateStateInvalid() public {
        bytes memory fakeProof = new bytes(jsonFixture.proof.length);

        mockCall(false);
        vm.expectRevert();
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, fakeProof);
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
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateInvalidOldRoot() public {
        mockCall(true);
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(999)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectRevert(ISuccinctVApp.InvalidOldRoot.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
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
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
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

        SuccinctVApp(VAPP).updateState(abi.encode(initialPublicValues), jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);

        // Capture the timestamp that was recorded
        uint64 recordedTimestamp = SuccinctVApp(VAPP).timestamps(1);

        // Create public values with a timestamp earlier than the previous block
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: recordedTimestamp - 1 // Timestamp earlier than previous block
        });

        vm.expectRevert(ISuccinctVApp.TimestampInPast.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }
}
