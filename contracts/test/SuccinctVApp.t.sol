// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {stdJson} from "../lib/forge-std/src/StdJson.sol";
import {FixtureLoader, Fixture, SP1ProofFixtureJson} from "./utils/FixtureLoader.sol";
import {WETH9} from "./utils/WETH9.sol";
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
    WETH9 public WETH;
    MockERC20 public PROVE;
    MockERC20 public USDC;
    SuccinctVApp public vapp;
    MockStaking public staking;

    address user1;
    address user2;
    address user3;

    function setUp() public {
        jsonFixture = loadFixture(vm, Fixture.Groth16);

        PublicValuesStruct memory _fixture =
            abi.decode(jsonFixture.publicValues, (PublicValuesStruct));
        fixture.old_root = _fixture.old_root;
        fixture.new_root = _fixture.new_root;
        for (uint256 i = 0; i < _fixture.actions.length; i++) {
            fixture.actions.push(_fixture.actions[i]);
        }

        verifier = address(new MockVerifier());

        // Setup tokens
        PROVE = new MockERC20("PROVE", "PROVE", 18);
        USDC = new MockERC20("USDC", "USDC", 6);

        staking = new MockStaking(address(PROVE));

        address vappImpl = address(new SuccinctVApp());
        vapp = SuccinctVApp(payable(address(new ERC1967Proxy(vappImpl, ""))));
        vapp.initialize(
            address(this),
            address(USDC),
            address(PROVE),
            address(staking),
            verifier,
            jsonFixture.vkey
        );

        // Whitelist USDC for testing
        vapp.addToken(address(USDC));

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

    receive() external payable {}

    function test_Initialize() public view {
        assertEq(vapp.owner(), address(this));
        assertEq(address(vapp.USDC()), address(USDC));
        assertEq(address(vapp.PROVE()), address(PROVE));
        assertEq(address(vapp.staking()), address(staking));
        assertEq(vapp.verifier(), verifier);
        assertEq(vapp.vappProgramVKey(), jsonFixture.vkey);
        assertEq(vapp.maxActionDelay(), 1 days);
        assertEq(vapp.blockNumber(), 0);
    }

    function test_RevertIf_InitializeInvalid() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        vapp.initialize(
            address(0),
            address(USDC),
            address(PROVE),
            address(staking),
            verifier,
            jsonFixture.vkey
        );
    }

    function test_UpdateStaking() public {
        address newStaking = address(1);

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.UpdatedStaking(newStaking);
        vapp.updateStaking(newStaking);

        assertEq(address(vapp.staking()), newStaking);
    }

    function test_RevertIf_UpdateStakingNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.updateStaking(address(1));
    }

    function test_UpdateVerifier() public {
        address newVerifier = address(1);

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.UpdatedVerifier(newVerifier);
        vapp.updateVerifier(newVerifier);

        assertEq(vapp.verifier(), newVerifier);
    }

    function test_RevertIf_UpdateVerifierNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.updateVerifier(address(1));
    }

    function test_UpdateActionDelay() public {
        uint64 newDelay = 2 days;

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.UpdatedMaxActionDelay(newDelay);
        vapp.updateActionDelay(newDelay);

        assertEq(vapp.maxActionDelay(), newDelay);
    }

    function test_RevertIf_UpdateActionDelayNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.updateActionDelay(2 days);
    }

    function test_UpdateFreezeDuration() public {
        uint64 newDuration = 3 days;

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.UpdatedFreezeDuration(newDuration);
        vapp.updateFreezeDuration(newDuration);

        assertEq(vapp.freezeDuration(), newDuration);
    }

    function test_RevertIf_UpdateFreezeDurationNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.updateFreezeDuration(3 days);
    }

    function test_AddToken() public {
        address token = address(99);

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.TokenWhitelist(token, true);
        vapp.addToken(token);

        assertTrue(vapp.whitelistedTokens(token));
    }

    function test_RevertIf_AddTokenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.addToken(address(99));
    }

    function test_RevertIf_AddTokenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.addToken(address(0));
    }

    function test_RevertIf_AddTokenAlreadyWhitelisted() public {
        address token = address(99);
        vapp.addToken(token);

        vm.expectRevert(abi.encodeWithSignature("TokenAlreadyWhitelisted()"));
        vapp.addToken(token);
    }

    function test_RemoveToken() public {
        address token = address(99);
        vapp.addToken(token);

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.TokenWhitelist(token, false);
        vapp.removeToken(token);

        assertFalse(vapp.whitelistedTokens(token));
    }

    function test_RevertIf_RemoveTokenNotOwner() public {
        address token = address(99);
        vapp.addToken(token);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.removeToken(token);
    }

    function test_RevertIf_RemoveTokenNotWhitelisted() public {
        address token = address(99);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        vapp.removeToken(token);
    }

    function test_SetMinAmount() public {
        address token = address(USDC);
        uint256 minAmount = 10e6; // 10 USDC

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.MinAmountUpdated(token, minAmount);
        vapp.setMinAmount(token, minAmount);

        assertEq(vapp.minAmounts(token), minAmount);

        // Update to a different value
        uint256 newMinAmount = 20e6; // 20 USDC

        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.MinAmountUpdated(token, newMinAmount);
        vapp.setMinAmount(token, newMinAmount);

        assertEq(vapp.minAmounts(token), newMinAmount);

        // Set to zero to disable minimum check
        vm.expectEmit(true, true, true, true);
        emit SuccinctVApp.MinAmountUpdated(token, 0);
        vapp.setMinAmount(token, 0);

        assertEq(vapp.minAmounts(token), 0);
    }

    function test_RevertIf_SetMinAmountZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.setMinAmount(address(0), 10e6);
    }

    function test_RevertIf_SetMinAmountNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        vapp.setMinAmount(address(USDC), 10e6);
    }

    function test_Fork() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: newRoot,
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, newRoot, bytes32(0));
        emit SuccinctVApp.Fork(newVkey, 1, newRoot, bytes32(0));

        (uint64 _block, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            vapp.fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);

        assertEq(vapp.vappProgramVKey(), newVkey);
        assertEq(vapp.blockNumber(), 1);
        assertEq(vapp.roots(1), newRoot);
        assertEq(_block, 1);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(0));
    }

    function test_RevertIf_ForkUnauthorized() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vapp.fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);
    }

    function test_ForkAfterUpdateState() public {
        // Update state
        mockCall(true);

        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });

        vapp.updateState(abi.encode(publicValues1), jsonFixture.proof);

        assertEq(vapp.blockNumber(), 1);
        assertEq(vapp.roots(1), bytes32(uint256(1)));
        assertEq(vapp.vappProgramVKey(), jsonFixture.vkey);

        // Fork
        bytes32 newVkey = bytes32(uint256(99));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(uint256(1)),
            new_root: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, newRoot, bytes32(uint256(1)));
        emit SuccinctVApp.Fork(newVkey, 2, newRoot, bytes32(uint256(1)));

        (uint64 blockNum, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            vapp.fork(newVkey, newRoot, abi.encode(publicValues2), jsonFixture.proof);

        assertEq(vapp.vappProgramVKey(), newVkey);
        assertEq(vapp.blockNumber(), 2);
        assertEq(vapp.roots(1), bytes32(uint256(1)));
        assertEq(vapp.roots(2), newRoot);
        assertEq(blockNum, 2);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(uint256(1)));
    }

    function test_Deposit() public {
        uint256 amount = 100e6;
        USDC.mint(address(this), amount);
        USDC.approve(address(vapp), amount);

        assertEq(USDC.balanceOf(address(this)), amount);
        assertEq(USDC.balanceOf(address(vapp)), 0);
        assertEq(vapp.currentReceipt(), 0);
        (, ReceiptStatus status,,) = vapp.receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.None));

        // Deposit
        bytes memory data = abi.encode(
            DepositAction({account: address(this), token: address(USDC), amount: amount})
        );
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.Deposit, data);
        vapp.deposit(address(this), address(USDC), amount);

        assertEq(USDC.balanceOf(address(this)), 0);
        assertEq(USDC.balanceOf(address(vapp)), amount);
        assertEq(vapp.currentReceipt(), 1);
        (, status,,) = vapp.receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Update state with deposit action
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
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
        emit ISuccinctVApp.Block(1, publicValues.new_root, publicValues.old_root);

        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = vapp.receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(vapp.finalizedReceipt(), 1);
    }

    function test_RevertIf_DepositZeroAddress() public {
        uint256 amount = 100e6;
        USDC.mint(user1, amount);

        vm.startPrank(user1);
        USDC.approve(address(vapp), amount);

        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.deposit(address(0), address(USDC), amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_DepositNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        nonWhitelistedToken.mint(user1, amount);

        vm.startPrank(user1);
        nonWhitelistedToken.approve(address(vapp), amount);

        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        vapp.deposit(user1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_DepositBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 USDC
        uint256 depositAmount = 5e6; // 5 USDC - below minimum

        // Set minimum amount
        vapp.setMinAmount(address(USDC), minAmount);

        // Try to deposit below minimum
        USDC.mint(user1, depositAmount);

        vm.startPrank(user1);
        USDC.approve(address(vapp), depositAmount);

        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        vapp.deposit(user1, address(USDC), depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_Withdraw() public {
        uint256 amount = 100e6; // 100 USDC (6 decimals)

        // Deposit
        USDC.mint(user1, amount);
        vm.startPrank(user1);
        USDC.approve(address(vapp), amount);
        uint64 depositReceipt = vapp.deposit(user1, address(USDC), amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: user1, token: address(USDC), amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
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
        emit ISuccinctVApp.Block(1, depositPublicValues.new_root, depositPublicValues.old_root);
        vapp.updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(user2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: user2, token: address(USDC), amount: amount, to: user2})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = vapp.withdraw(user2, address(USDC), amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            vapp.receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(uint256(1)),
            new_root: bytes32(uint256(2)),
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
        emit ISuccinctVApp.Block(2, withdrawPublicValues.new_root, withdrawPublicValues.old_root);
        vapp.updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claims created
        assertEq(vapp.withdrawalClaims(user2, address(USDC)), amount);
        assertEq(vapp.pendingWithdrawalClaims(address(USDC)), amount);

        // Verify finalizedReceipt updated
        assertEq(vapp.finalizedReceipt(), 2);

        // Claim withdrawal
        assertEq(USDC.balanceOf(user2), 0);
        vm.startPrank(user2);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(user2, address(USDC), user2, amount);
        uint256 claimedAmount = vapp.claimWithdrawal(user2, address(USDC));
        vm.stopPrank();

        assertEq(claimedAmount, amount);
        assertEq(USDC.balanceOf(user2), amount); // User2 now has the USDC
        assertEq(vapp.withdrawalClaims(user2, address(USDC)), 0); // Claim is cleared
        assertEq(vapp.pendingWithdrawalClaims(address(USDC)), 0); // No more pending claims

        // Reattempt claim
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        vapp.claimWithdrawal(user2, address(USDC));
        vm.stopPrank();
    }

    function test_WithdrawTo() public {
        uint256 amount = 100e6; // 100 USDC (6 decimals)

        // Deposit
        USDC.mint(user1, amount);
        vm.startPrank(user1);
        USDC.approve(address(vapp), amount);
        uint64 depositReceipt = vapp.deposit(user1, address(USDC), amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: user1, token: address(USDC), amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
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
        emit ISuccinctVApp.Block(1, depositPublicValues.new_root, depositPublicValues.old_root);
        vapp.updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw with a different recipient (user2 initiates withdrawal to user3)
        vm.startPrank(user2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: user2, token: address(USDC), amount: amount, to: user3})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = vapp.withdraw(user3, address(USDC), amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            vapp.receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(uint256(1)),
            new_root: bytes32(uint256(2)),
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
        emit ISuccinctVApp.Block(2, withdrawPublicValues.new_root, withdrawPublicValues.old_root);
        vapp.updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claim was created for user3, not user2
        assertEq(vapp.withdrawalClaims(user2, address(USDC)), 0);
        assertEq(vapp.withdrawalClaims(user3, address(USDC)), amount);
        assertEq(vapp.pendingWithdrawalClaims(address(USDC)), amount);

        // Verify finalizedReceipt updated
        assertEq(vapp.finalizedReceipt(), 2);

        // Claim withdrawal as user3
        assertEq(USDC.balanceOf(user3), 0);
        vm.startPrank(user3);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(user3, address(USDC), user3, amount);
        uint256 claimedAmount = vapp.claimWithdrawal(user3, address(USDC));
        vm.stopPrank();

        // Verify claim was successful, and user3 has the funds
        assertEq(claimedAmount, amount);
        assertEq(USDC.balanceOf(user3), amount); // User3 now has the USDC
        assertEq(USDC.balanceOf(user2), 0); // User2 has nothing
        assertEq(vapp.withdrawalClaims(user3, address(USDC)), 0); // Claim is cleared
        assertEq(vapp.pendingWithdrawalClaims(address(USDC)), 0); // No more pending claims

        // Attempt to claim again should fail
        vm.startPrank(user3);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        vapp.claimWithdrawal(user3, address(USDC));
        vm.stopPrank();

        // User2 shouldn't be able to claim either
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("NoWithdrawalToClaim()"));
        vapp.claimWithdrawal(user2, address(USDC));
        vm.stopPrank();
    }

    function test_RevertIf_WithdrawZeroAddress() public {
        uint256 amount = 100e6;

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.withdraw(address(0), address(USDC), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("TokenNotWhitelisted()"));
        vapp.withdraw(user1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_WithdrawBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 USDC
        uint256 withdrawAmount = 5e6; // 5 USDC - below minimum

        // Set minimum amount
        vapp.setMinAmount(address(USDC), minAmount);

        // Try to withdraw below minimum
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("MinAmount()"));
        vapp.withdraw(user1, address(USDC), withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_AddDelegatedSigner() public {
        // Setup user1 as a prover owner
        staking.setHasProver(user1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add first delegated signer
        vm.startPrank(user1);
        bytes memory addSignerData1 = abi.encode(AddSignerAction({owner: user1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.AddSigner, addSignerData1);
        uint64 addSignerReceipt1 = vapp.addDelegatedSigner(signer1);
        vm.stopPrank();

        assertEq(addSignerReceipt1, 1);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            vapp.receipts(addSignerReceipt1);
        assertEq(uint8(actionType), uint8(ActionType.AddSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, addSignerData1);

        // Process the first addSigner action through state update
        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
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
        emit ISuccinctVApp.Block(1, publicValues1.new_root, publicValues1.old_root);
        vapp.updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = vapp.receipts(addSignerReceipt1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));
        assertEq(vapp.finalizedReceipt(), 1);

        // Verify first delegated signer was added
        address[] memory signers = vapp.getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer1);
        assertTrue(vapp.usedSigners(signer1));

        // Add second delegated signer
        vm.startPrank(user1);
        bytes memory addSignerData2 = abi.encode(AddSignerAction({owner: user1, signer: signer2}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.AddSigner, addSignerData2);
        uint64 addSignerReceipt2 = vapp.addDelegatedSigner(signer2);
        vm.stopPrank();

        assertEq(addSignerReceipt2, 2);
        (actionType, status,,) = vapp.receipts(addSignerReceipt2);
        assertEq(uint8(actionType), uint8(ActionType.AddSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Process the second addSigner action through state update
        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(uint256(1)),
            new_root: bytes32(uint256(2)),
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
        emit ISuccinctVApp.Block(2, publicValues2.new_root, publicValues2.old_root);
        vapp.updateState(abi.encode(publicValues2), jsonFixture.proof);

        // Verify second receipt status updated
        (, status,,) = vapp.receipts(addSignerReceipt2);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(vapp.finalizedReceipt(), 2);

        // Verify both delegated signers are in the array
        signers = vapp.getDelegatedSigners(user1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(vapp.usedSigners(signer1));
        assertTrue(vapp.usedSigners(signer2));
    }

    function test_RevertIf_AddDelegatedSignerNotProverOwner() public {
        // user1 is not a prover owner
        address signer = makeAddr("signer");

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerZeroAddress() public {
        // Setup user1 as a prover owner
        staking.setHasProver(user1, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vapp.addDelegatedSigner(address(0));
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerIsProver() public {
        // Setup user1 as a prover owner and user2 as a prover
        staking.setHasProver(user1, true);
        staking.setIsProver(user2, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vapp.addDelegatedSigner(user2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerHasProver() public {
        // Setup user1 and user2 as prover owners
        staking.setHasProver(user1, true);
        staking.setHasProver(user2, true);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vapp.addDelegatedSigner(user2);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_RevertIf_AddDelegatedSignerAlreadyUsed() public {
        // Setup user1 and user2 as prover owners
        staking.setHasProver(user1, true);
        staking.setHasProver(user2, true);

        address signer = makeAddr("signer");

        // Add signer to user1
        vm.startPrank(user1);
        vapp.addDelegatedSigner(signer);
        vm.stopPrank();

        // Try to add the same signer to user2
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vapp.addDelegatedSigner(signer);
        vm.stopPrank();

        // Verify only one receipt was created
        assertEq(vapp.currentReceipt(), 1);
    }

    function test_RemoveDelegatedSigner() public {
        // Setup user1 as a prover owner and add two delegated signers (one at a time to avoid stack issues)
        staking.setHasProver(user1, true);
        address signer1 = makeAddr("signer1");
        address signer2 = makeAddr("signer2");

        // Add signers one by one to avoid stack too deep issues
        vm.startPrank(user1);
        uint64 addSignerReceipt1 = vapp.addDelegatedSigner(signer1);
        vm.stopPrank();

        // Process the first addSigner action
        bytes memory addSignerData1 = abi.encode(AddSignerAction({owner: user1, signer: signer1}));
        PublicValuesStruct memory addPublicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        addPublicValues1.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt1,
            data: addSignerData1
        });

        mockCall(true);
        vapp.updateState(abi.encode(addPublicValues1), jsonFixture.proof);

        // Add second signer
        vm.startPrank(user1);
        uint64 addSignerReceipt2 = vapp.addDelegatedSigner(signer2);
        vm.stopPrank();

        // Process the second addSigner action
        bytes memory addSignerData2 = abi.encode(AddSignerAction({owner: user1, signer: signer2}));
        PublicValuesStruct memory addPublicValues2 = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(uint256(1)),
            new_root: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        addPublicValues2.actions[0] = Action({
            action: ActionType.AddSigner,
            status: ReceiptStatus.Completed,
            receipt: addSignerReceipt2,
            data: addSignerData2
        });

        mockCall(true);
        vapp.updateState(abi.encode(addPublicValues2), jsonFixture.proof);

        // Verify both signers were added
        address[] memory signers = vapp.getDelegatedSigners(user1);
        assertEq(signers.length, 2);
        assertEq(signers[0], signer1);
        assertEq(signers[1], signer2);
        assertTrue(vapp.usedSigners(signer1));
        assertTrue(vapp.usedSigners(signer2));
        assertEq(vapp.finalizedReceipt(), 2);

        // Now, remove the first delegated signer
        vm.startPrank(user1);
        bytes memory removeSignerData =
            abi.encode(RemoveSignerAction({owner: user1, signer: signer1}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(3, ActionType.RemoveSigner, removeSignerData);
        uint64 removeSignerReceipt = vapp.removeDelegatedSigner(signer1);
        vm.stopPrank();

        // Check receipt details
        (ActionType actionType, ReceiptStatus status,,) = vapp.receipts(removeSignerReceipt);
        assertEq(uint8(actionType), uint8(ActionType.RemoveSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Verify first signer was removed after the removal operation
        signers = vapp.getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer2); // signer2 should remain

        // Check usage flags
        bool isSigner1Used = vapp.usedSigners(signer1);
        bool isSigner2Used = vapp.usedSigners(signer2);
        assertFalse(isSigner1Used);
        assertTrue(isSigner2Used);

        // Process the removeSigner action through state update
        PublicValuesStruct memory removePublicValues = PublicValuesStruct({
            actions: new Action[](1),
            old_root: bytes32(uint256(2)),
            new_root: bytes32(uint256(3)),
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
        emit ISuccinctVApp.Block(3, removePublicValues.new_root, removePublicValues.old_root);
        vapp.updateState(abi.encode(removePublicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = vapp.receipts(removeSignerReceipt);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(vapp.finalizedReceipt(), 3);
    }

    function test_RevertIf_RemoveDelegatedSignerNotOwner() public {
        // Setup user1 as a prover owner and add a delegated signer
        staking.setHasProver(user1, true);
        staking.setHasProver(user2, true);
        address signer = makeAddr("signer");

        vm.prank(user1);
        vapp.addDelegatedSigner(signer);

        // User2 tries to remove user1's signer
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vapp.removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify signer is still in user1's delegated signers
        address[] memory signers = vapp.getDelegatedSigners(user1);
        assertEq(signers.length, 1);
        assertEq(signers[0], signer);
        assertTrue(vapp.usedSigners(signer));
    }

    function test_RevertIf_RemoveDelegatedSignerNotRegistered() public {
        // Setup user1 as a prover owner
        staking.setHasProver(user1, true);
        address signer = makeAddr("signer");

        // Try to remove a signer that was never added
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSigner()"));
        vapp.removeDelegatedSigner(signer);
        vm.stopPrank();

        // Verify no receipt was created
        assertEq(vapp.currentReceipt(), 0);
    }

    function test_EmergencyWithdrawal() public {
        mockCall(true);

        // Failover so that we can use the hardcoded usdc in the merkle root
        address testUsdc = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        if (testUsdc != address(USDC)) {
            vm.etch(testUsdc, address(USDC).code);
            vapp.addToken(testUsdc);
        }
        MockERC20(testUsdc).mint(address(this), 100);
        MockERC20(testUsdc).approve(address(vapp), 100);
        vapp.deposit(address(this), address(testUsdc), 100);

        // The merkle tree
        bytes32 root = 0xc53421d840beb11a0382b8d5bbf524da79ddb96b11792c3812276a05300e276e;
        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x97166dee2bb3b38545a732e4fc42a7d745eaeb55be08c08b7dfad28961af339b;
        proof[1] = 0xd530f51fd96943359dc951ce6d19212cc540a321562a0bcd7e1747700dce0ec9;
        proof[2] = 0x5517ae9ffdaac5507c9bc6990aa6637b3ce06ebfbdb08f4208c73dc2fe2d20a9;
        proof[3] = 0x35b34cde80bb3bd84dbd6d84ccfa8b739908f2c632802af348512215e8eb7dd6;

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: root,
            timestamp: uint64(block.timestamp)
        });
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);

        vm.warp(block.timestamp + vapp.freezeDuration() + 1);

        // Leaf debug
        address user = 0x4F06869E36F2De69d97e636E52B45F07A91b4fa6;
        bytes32 leaf = sha256(abi.encodePacked(user, uint256(100)));
        console.logBytes32(leaf);

        // Withdraw
        vm.startPrank(user);
        vapp.emergencyWithdraw(address(testUsdc), 100, proof);

        // Claim withdrawal
        assertEq(ERC20(testUsdc).balanceOf(user), 0);
        vapp.claimWithdrawal(user, address(testUsdc));
        assertEq(ERC20(testUsdc).balanceOf(user), 100);
        vm.stopPrank();
    }

    function test_UpdateStateValid() public {
        mockCall(true);

        assertEq(vapp.blockNumber(), 0);
        assertEq(vapp.roots(0), bytes32(0));
        assertEq(vapp.roots(1), bytes32(0));
        assertEq(vapp.root(), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.new_root, fixture.old_root);
        vapp.updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(vapp.blockNumber(), 1);
        assertEq(vapp.roots(0), bytes32(0));
        assertEq(vapp.roots(1), fixture.new_root);
        assertEq(vapp.root(), fixture.new_root);
    }

    function test_UpdateStateTwice() public {
        mockCall(true);

        vapp.updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(vapp.blockNumber(), 1);
        assertEq(vapp.roots(0), bytes32(0));
        assertEq(vapp.roots(1), fixture.new_root);
        assertEq(vapp.roots(2), bytes32(0));
        assertEq(vapp.root(), fixture.new_root);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: fixture.new_root,
            new_root: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues.new_root, publicValues.old_root);
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);

        assertEq(vapp.blockNumber(), 2);
        assertEq(vapp.roots(0), bytes32(0));
        assertEq(vapp.roots(1), fixture.new_root);
        assertEq(vapp.roots(2), publicValues.new_root);
        assertEq(vapp.root(), publicValues.new_root);
    }

    function test_RevertIf_UpdateStateInvalid() public {
        bytes memory fakeProof = new bytes(jsonFixture.proof.length);

        mockCall(false);
        vm.expectRevert();
        vapp.updateState(jsonFixture.publicValues, fakeProof);
    }

    function test_RevertIf_UpdateStateInvalidRoot() public {
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: bytes32(0),
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);
        vm.expectRevert(ISuccinctVApp.InvalidRoot.selector);
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateInvalidOldRoot() public {
        mockCall(true);
        vapp.updateState(jsonFixture.publicValues, jsonFixture.proof);
        assertEq(vapp.blockNumber(), 1);
        assertEq(vapp.root(), fixture.new_root);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(uint256(999)),
            new_root: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectRevert(ISuccinctVApp.InvalidOldRoot.selector);
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateInvalidTimestampFuture() public {
        mockCall(true);

        // Create public values with a future timestamp
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp + 1 days) // Timestamp in the future
        });

        vm.expectRevert(ISuccinctVApp.InvalidTimestamp.selector);
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertIf_UpdateStateTimestampInPast() public {
        mockCall(true);

        // First update with current timestamp
        uint64 initialTime = uint64(block.timestamp);
        PublicValuesStruct memory initialPublicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(0),
            new_root: bytes32(uint256(1)),
            timestamp: initialTime
        });

        vapp.updateState(abi.encode(initialPublicValues), jsonFixture.proof);
        assertEq(vapp.blockNumber(), 1);

        // Capture the timestamp that was recorded
        uint64 recordedTimestamp = vapp.timestamps(1);

        // Create public values with a timestamp earlier than the previous block
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            old_root: bytes32(uint256(1)),
            new_root: bytes32(uint256(2)),
            timestamp: recordedTimestamp - 1 // Timestamp earlier than previous block
        });

        vm.expectRevert(ISuccinctVApp.TimestampInPast.selector);
        vapp.updateState(abi.encode(publicValues), jsonFixture.proof);
    }
}
