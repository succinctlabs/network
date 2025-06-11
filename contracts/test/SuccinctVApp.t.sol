// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {stdJson} from "../lib/forge-std/src/StdJson.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt,
    TransactionVariant,
    Deposit,
    Withdraw,
    CreateProver
} from "../src/libraries/PublicValues.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {ISP1Verifier} from "../lib/sp1-contracts/contracts/src/ISP1Verifier.sol";
import {FixtureLoader, Fixture, SP1ProofFixtureJson} from "./utils/FixtureLoader.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract SuccinctVAppTest is Test, FixtureLoader {
    using stdJson for string;

    // Constants
    uint256 constant FEE_UNIT = 10000;
    uint64 constant MAX_ACTION_DELAY = 1 days;
    uint256 constant PROTOCOL_FEE_BIPS = 30; // 0.3%
    uint256 constant STAKER_FEE_BIPS = 1000; // 10%

    // Fixtures
    SP1ProofFixtureJson public jsonFixture;
    StepPublicValues public fixture;

    // EOAs
    address OWNER;
    address AUCTIONEER;
    address ALICE;
    address BOB;
    address REQUESTER_1;
    uint256 REQUESTER_1_PK;
    address REQUESTER_2;
    uint256 REQUESTER_2_PK;
    address REQUESTER_3;
    uint256 REQUESTER_3_PK;

    // Contracts
    address public VERIFIER;
    address public FEE_VAULT;
    address public PROVE;
    address public I_PROVE;
    address public VAPP;
    address public STAKING;

    // Program and state root
    bytes32 public VKEY;
    bytes32 public GENESIS_STATE_ROOT;
    uint64 public GENESIS_TIMESTAMP;

    function setUp() public {
        // Load fixtures
        fixture.oldRoot = bytes32(uint256(5346634509));
        fixture.newRoot = bytes32(uint256(3402673290));
        fixture.timestamp = uint64(1);
        jsonFixture.publicValues = abi.encode(fixture);

        // Set program and state root
        VKEY = jsonFixture.vkey;
        GENESIS_STATE_ROOT = fixture.oldRoot;
        GENESIS_TIMESTAMP = uint64(0);

        // Create owner

        // TODO: Fix these
        // OWNER = makeAddr("OWNER");
        // AUCTIONEER = makeAddr("AUCTIONEER");

        OWNER = address(this);
        AUCTIONEER = address(this);
        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");

        // Create requesters
        (REQUESTER_1, REQUESTER_1_PK) = makeAddrAndKey("REQUESTER_1");
        (REQUESTER_2, REQUESTER_2_PK) = makeAddrAndKey("REQUESTER_2");
        (REQUESTER_3, REQUESTER_3_PK) = makeAddrAndKey("REQUESTER_3");

        // Deploy verifier
        VERIFIER = address(new MockVerifier());

        // Deploy fee vault (just an EOA for testing)
        FEE_VAULT = makeAddr("FEE_VAULT");

        // Deploy tokens
        PROVE = address(new MockERC20("Succinct", "PROVE", 18));
        I_PROVE = address(new MockERC20("Succinct", "iPROVE", 18));

        // Deploy staking
        STAKING = address(new MockStaking(PROVE, I_PROVE));

        // Deploy VApp
        address vappImpl = address(new SuccinctVApp());
        VAPP = address(new ERC1967Proxy(vappImpl, ""));
        SuccinctVApp(VAPP).initialize(
            OWNER,
            PROVE,
            I_PROVE,
            AUCTIONEER,
            STAKING,
            VERIFIER,
            VKEY,
            GENESIS_STATE_ROOT,
            GENESIS_TIMESTAMP
        );
        MockStaking(STAKING).setVApp(VAPP);
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

    function _signPermit(uint256 _pk, address _owner, uint256 _amount, uint256 _deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        // Get the current nonce for the owner
        uint256 nonce = IERC20Permit(PROVE).nonces(_owner);

        // Construct the permit digest
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, _owner, VAPP, _amount, nonce, _deadline));
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", IERC20Permit(PROVE).DOMAIN_SEPARATOR(), structHash)
        );

        // Sign the digest
        return vm.sign(_pk, digest);
    }
}

contract SuccinctVAppSetupTests is SuccinctVAppTest {
    function test_SetUp() public view {
        assertEq(SuccinctVApp(VAPP).owner(), OWNER);
        assertEq(SuccinctVApp(VAPP).prove(), PROVE);
        assertEq(SuccinctVApp(VAPP).iProve(), I_PROVE);
        assertEq(SuccinctVApp(VAPP).auctioneer(), AUCTIONEER);
        assertEq(SuccinctVApp(VAPP).staking(), STAKING);
        assertEq(SuccinctVApp(VAPP).verifier(), VERIFIER);
        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), VKEY);
        assertEq(SuccinctVApp(VAPP).root(), GENESIS_STATE_ROOT);
        assertEq(SuccinctVApp(VAPP).timestamp(), GENESIS_TIMESTAMP);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
    }

    function test_RevertInitialized_WhenInvalidInitialization() public {
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        SuccinctVApp(VAPP).initialize(
            OWNER,
            PROVE,
            I_PROVE,
            AUCTIONEER,
            STAKING,
            VERIFIER,
            VKEY,
            GENESIS_STATE_ROOT,
            GENESIS_TIMESTAMP
        );
    }
}
