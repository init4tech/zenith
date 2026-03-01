// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Passage} from "../../src/passage/Passage.sol";
import {TestERC20} from "../SignetStdTest.t.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Handler contract for Passage invariant testing
contract PassageHandler is Test {
    Passage public passage;
    address public tokenAdmin;

    // Test tokens
    TestERC20 public token1;
    TestERC20 public token2;

    // Ghost variables for fund tracking
    uint256 public totalEthEntered;
    uint256 public totalEthWithdrawn;
    mapping(address => uint256) public totalTokenEntered;
    mapping(address => uint256) public totalTokenWithdrawn;

    // Track actors
    address[] public actors;
    address public currentActor;

    constructor(Passage _passage, address _tokenAdmin, TestERC20 _token1, TestERC20 _token2) {
        passage = _passage;
        tokenAdmin = _tokenAdmin;
        token1 = _token1;
        token2 = _token2;

        // Setup actors
        for (uint256 i = 1; i <= 5; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);

            // Fund actors
            vm.deal(actor, 1000 ether);
            token1.mint(actor, 1000000e18);
            token2.mint(actor, 1000000e18);

            // Approve passage
            vm.startPrank(actor);
            token1.approve(address(passage), type(uint256).max);
            token2.approve(address(passage), type(uint256).max);
            vm.stopPrank();
        }
    }

    modifier useActor(uint256 actorIndex) {
        currentActor = actors[actorIndex % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Enter ETH into the rollup
    function enterEth(uint256 actorIndex, uint256 amount, uint256 rollupChainId, address recipient)
        external
        useActor(actorIndex)
    {
        amount = bound(amount, 0, currentActor.balance);
        if (amount == 0) return;

        uint256 balanceBefore = address(passage).balance;
        passage.enter{value: amount}(rollupChainId, recipient);
        uint256 balanceAfter = address(passage).balance;

        // Track ghost variables
        totalEthEntered += (balanceAfter - balanceBefore);
    }

    /// @notice Enter ETH via direct transfer (receive/fallback)
    function enterEthDirect(uint256 actorIndex, uint256 amount) external useActor(actorIndex) {
        amount = bound(amount, 0, currentActor.balance);
        if (amount == 0) return;

        uint256 balanceBefore = address(passage).balance;
        (bool success,) = address(passage).call{value: amount}("");
        if (success) {
            uint256 balanceAfter = address(passage).balance;
            totalEthEntered += (balanceAfter - balanceBefore);
        }
    }

    /// @notice Enter tokens into the rollup
    function enterToken(uint256 actorIndex, uint256 amount, uint256 rollupChainId, address recipient, bool useToken1)
        external
        useActor(actorIndex)
    {
        TestERC20 token = useToken1 ? token1 : token2;
        amount = bound(amount, 0, token.balanceOf(currentActor));
        if (amount == 0) return;
        if (!passage.canEnter(address(token))) return;

        uint256 balanceBefore = token.balanceOf(address(passage));
        passage.enterToken(rollupChainId, recipient, address(token), amount);
        uint256 balanceAfter = token.balanceOf(address(passage));

        totalTokenEntered[address(token)] += (balanceAfter - balanceBefore);
    }

    /// @notice Admin withdraws ETH
    function withdrawEth(uint256 amount, address recipient) external {
        amount = bound(amount, 0, address(passage).balance);
        if (amount == 0) return;
        if (recipient == address(0)) return;

        vm.prank(tokenAdmin);
        passage.withdraw(address(0), recipient, amount);

        totalEthWithdrawn += amount;
    }

    /// @notice Admin withdraws tokens
    function withdrawToken(uint256 amount, address recipient, bool useToken1) external {
        TestERC20 token = useToken1 ? token1 : token2;
        amount = bound(amount, 0, token.balanceOf(address(passage)));
        if (amount == 0) return;
        if (recipient == address(0)) return;

        vm.prank(tokenAdmin);
        passage.withdraw(address(token), recipient, amount);

        totalTokenWithdrawn[address(token)] += amount;
    }

    /// @notice Admin configures token entry
    function configureEnter(bool useToken1, bool canEnter) external {
        TestERC20 token = useToken1 ? token1 : token2;
        vm.prank(tokenAdmin);
        passage.configureEnter(address(token), canEnter);
    }

    /// @notice Get passage ETH balance
    function getPassageEthBalance() external view returns (uint256) {
        return address(passage).balance;
    }

    /// @notice Get passage token balance
    function getPassageTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(passage));
    }
}

/// @notice Invariant tests for Passage contract
/// @dev Focus on fund safety - ensuring no tokens are lost or improperly accessed
contract PassageInvariantTest is StdInvariant, Test {
    Passage public passage;
    PassageHandler public handler;

    address public tokenAdmin = address(0xAD111);
    uint256 public defaultChainId = 1337;

    TestERC20 public token1;
    TestERC20 public token2;

    // Permit2 mock address
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        // Deploy test tokens
        token1 = new TestERC20("Token1", "TK1", 18);
        token2 = new TestERC20("Token2", "TK2", 18);

        // Setup initial enter tokens
        address[] memory initialTokens = new address[](2);
        initialTokens[0] = address(token1);
        initialTokens[1] = address(token2);

        // Deploy Passage
        passage = new Passage(defaultChainId, tokenAdmin, initialTokens, PERMIT2);

        // Deploy handler
        handler = new PassageHandler(passage, tokenAdmin, token1, token2);

        // Target only the handler
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(passage));
        excludeSender(address(handler));
    }

    /// @notice INVARIANT: ETH balance equals entered minus withdrawn
    /// @dev Critical fund safety invariant - ensures no ETH is created or destroyed
    function invariant_ethBalanceAccounting() public view {
        uint256 actualBalance = address(passage).balance;
        uint256 expectedBalance = handler.totalEthEntered() - handler.totalEthWithdrawn();

        assertEq(actualBalance, expectedBalance, "ETH balance mismatch - funds may be lost or created");
    }

    /// @notice INVARIANT: Token balance equals entered minus withdrawn
    /// @dev Critical fund safety invariant for each token
    function invariant_tokenBalanceAccounting() public view {
        // Check token1
        uint256 actualBalance1 = token1.balanceOf(address(passage));
        uint256 expectedBalance1 =
            handler.totalTokenEntered(address(token1)) - handler.totalTokenWithdrawn(address(token1));
        assertEq(actualBalance1, expectedBalance1, "Token1 balance mismatch - funds may be lost or created");

        // Check token2
        uint256 actualBalance2 = token2.balanceOf(address(passage));
        uint256 expectedBalance2 =
            handler.totalTokenEntered(address(token2)) - handler.totalTokenWithdrawn(address(token2));
        assertEq(actualBalance2, expectedBalance2, "Token2 balance mismatch - funds may be lost or created");
    }

    /// @notice INVARIANT: Token admin is immutable
    /// @dev Access control invariant
    function invariant_tokenAdminImmutable() public view {
        assertEq(passage.tokenAdmin(), tokenAdmin, "Token admin changed unexpectedly");
    }

    /// @notice INVARIANT: Default rollup chain ID is immutable
    function invariant_defaultChainIdImmutable() public view {
        assertEq(passage.defaultRollupChainId(), defaultChainId, "Default chain ID changed unexpectedly");
    }

    /// @notice INVARIANT: Passage can always receive ETH (liveness)
    /// @dev Ensures the system can always make progress
    function invariant_canReceiveEth() public {
        address tester = address(0x7E57);
        vm.deal(tester, 1 ether);

        uint256 balanceBefore = address(passage).balance;

        vm.prank(tester);
        passage.enter{value: 1 ether}(defaultChainId, tester);

        uint256 balanceAfter = address(passage).balance;
        assertEq(balanceAfter, balanceBefore + 1 ether, "Failed to receive ETH");
    }

    /// @notice INVARIANT: Withdrawal cannot exceed balance
    /// @dev Fund safety - prevents over-withdrawal
    function invariant_withdrawalBounded() public view {
        // If ghost variables are consistent, withdrawals are bounded
        assertGe(handler.totalEthEntered(), handler.totalEthWithdrawn(), "More ETH withdrawn than entered");
        assertGe(
            handler.totalTokenEntered(address(token1)),
            handler.totalTokenWithdrawn(address(token1)),
            "More token1 withdrawn than entered"
        );
        assertGe(
            handler.totalTokenEntered(address(token2)),
            handler.totalTokenWithdrawn(address(token2)),
            "More token2 withdrawn than entered"
        );
    }
}
