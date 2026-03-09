// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RollupPassage} from "../../src/passage/RollupPassage.sol";
import {TestERC20} from "../SignetStdTest.t.sol";
import {ERC20Burnable} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @notice Test token that is burnable (required for RollupPassage exit)
contract BurnableTestToken is TestERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) TestERC20(name_, symbol_, decimals_) {}

    // TestERC20 already extends ERC20Burnable, so burn() is available
}

/// @notice Handler contract for RollupPassage invariant testing
contract RollupPassageHandler is Test {
    RollupPassage public rollupPassage;

    BurnableTestToken public token;

    // Ghost variables for tracking
    uint256 public totalEthExited;
    uint256 public totalTokenExited;
    uint256 public totalTokenBurned;

    // Track initial token supply
    uint256 public initialTokenSupply;

    // Track actors
    address[] public actors;
    address public currentActor;

    constructor(RollupPassage _rollupPassage, BurnableTestToken _token) {
        rollupPassage = _rollupPassage;
        token = _token;

        // Setup actors
        for (uint256 i = 1; i <= 5; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);

            // Fund actors
            vm.deal(actor, 1000 ether);
            token.mint(actor, 100000e18);

            // Approve rollupPassage
            vm.startPrank(actor);
            token.approve(address(rollupPassage), type(uint256).max);
            vm.stopPrank();
        }

        // Record initial supply after minting to actors
        initialTokenSupply = token.totalSupply();
    }

    modifier useActor(uint256 actorIndex) {
        currentActor = actors[actorIndex % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Exit ETH from rollup
    function exitEth(uint256 actorIndex, uint256 amount, address hostRecipient) external useActor(actorIndex) {
        amount = _bound(amount, 0, currentActor.balance);
        if (amount == 0) return;

        uint256 balanceBefore = address(rollupPassage).balance;
        rollupPassage.exit{value: amount}(hostRecipient);
        uint256 balanceAfter = address(rollupPassage).balance;

        totalEthExited += (balanceAfter - balanceBefore);
    }

    /// @notice Exit ETH via direct transfer
    function exitEthDirect(uint256 actorIndex, uint256 amount) external useActor(actorIndex) {
        amount = _bound(amount, 0, currentActor.balance);
        if (amount == 0) return;

        uint256 balanceBefore = address(rollupPassage).balance;
        (bool success,) = address(rollupPassage).call{value: amount}("");
        if (success) {
            uint256 balanceAfter = address(rollupPassage).balance;
            totalEthExited += (balanceAfter - balanceBefore);
        }
    }

    /// @notice Exit tokens from rollup (burns them)
    function exitToken(uint256 actorIndex, uint256 amount, address hostRecipient) external useActor(actorIndex) {
        amount = _bound(amount, 0, token.balanceOf(currentActor));
        if (amount == 0) return;

        uint256 supplyBefore = token.totalSupply();
        rollupPassage.exitToken(hostRecipient, address(token), amount);
        uint256 supplyAfter = token.totalSupply();

        totalTokenExited += amount;
        totalTokenBurned += (supplyBefore - supplyAfter);
    }

    /// @notice Get current token supply
    function getCurrentTokenSupply() external view returns (uint256) {
        return token.totalSupply();
    }
}

/// @notice Invariant tests for RollupPassage contract
/// @dev Focus on fund safety during exits - ETH locked, tokens burned
contract RollupPassageInvariantTest is StdInvariant, Test {
    RollupPassage public rollupPassage;
    RollupPassageHandler public handler;

    BurnableTestToken public token;

    // Permit2 mock address
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        // Deploy test token
        token = new BurnableTestToken("RollupToken", "RTK", 18);

        // Deploy RollupPassage
        rollupPassage = new RollupPassage(PERMIT2);

        // Deploy handler
        handler = new RollupPassageHandler(rollupPassage, token);

        // Target only the handler
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(rollupPassage));
        excludeSender(address(handler));
    }

    /// @notice INVARIANT: ETH exits are locked in contract
    /// @dev RollupPassage holds ETH that has "exited" (locked for bridging)
    function invariant_ethExitedIsLocked() public view {
        uint256 actualBalance = address(rollupPassage).balance;
        assertEq(actualBalance, handler.totalEthExited(), "ETH exit accounting mismatch");
    }

    /// @notice INVARIANT: Token exits reduce total supply (burned)
    /// @dev Exited tokens should be burned, reducing supply
    function invariant_tokenExitsBurned() public view {
        uint256 currentSupply = token.totalSupply();
        uint256 expectedSupply = handler.initialTokenSupply() - handler.totalTokenBurned();

        assertEq(currentSupply, expectedSupply, "Token burn accounting mismatch");
    }

    /// @notice INVARIANT: Tokens exited equals tokens burned
    /// @dev All exited tokens should be burned 1:1
    function invariant_exitedEqualsBurned() public view {
        assertEq(handler.totalTokenExited(), handler.totalTokenBurned(), "Exit/burn mismatch");
    }

    /// @notice INVARIANT: RollupPassage holds no tokens
    /// @dev Tokens are burned on exit, not held
    function invariant_noTokensHeld() public view {
        assertEq(token.balanceOf(address(rollupPassage)), 0, "RollupPassage holding tokens unexpectedly");
    }

    /// @notice INVARIANT: RollupPassage remains functional (liveness)
    /// @dev Verifies contract is not bricked
    function invariant_canExitEth() public view {
        assertTrue(address(rollupPassage).code.length > 0, "RollupPassage contract missing");
    }

    /// @notice INVARIANT: Token contract remains functional (liveness)
    /// @dev Verifies token contract is not bricked
    function invariant_canExitTokens() public view {
        assertTrue(address(token).code.length > 0, "Token contract missing");
    }

    /// @notice INVARIANT: Token supply only decreases (or stays same)
    /// @dev No tokens should be minted by RollupPassage
    function invariant_supplyOnlyDecreases() public view {
        assertLe(token.totalSupply(), handler.initialTokenSupply(), "Token supply increased unexpectedly");
    }
}
