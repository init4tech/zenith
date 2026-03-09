// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {RollupOrders} from "../../src/orders/RollupOrders.sol";
import {HostOrders} from "../../src/orders/HostOrders.sol";
import {IOrders} from "../../src/orders/IOrders.sol";
import {TestERC20} from "../SignetStdTest.t.sol";

/// @notice Handler contract for Orders invariant testing
contract OrdersHandler is Test {
    RollupOrders public rollupOrders;
    HostOrders public hostOrders;

    TestERC20 public token;

    // Ghost variables for tracking ETH flows
    uint256 public totalEthInitiated;
    uint256 public totalEthSwept;
    uint256 public totalEthFilled;

    // Ghost variables for tracking token flows
    uint256 public totalTokenInitiated;
    uint256 public totalTokenSwept;
    uint256 public totalTokenFilled;

    // Track actors
    address[] public actors;
    address public currentActor;

    // Track order count
    uint256 public orderCount;

    constructor(RollupOrders _rollupOrders, HostOrders _hostOrders, TestERC20 _token) {
        rollupOrders = _rollupOrders;
        hostOrders = _hostOrders;
        token = _token;

        // Setup actors
        for (uint256 i = 1; i <= 5; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);

            // Fund actors
            vm.deal(actor, 1000 ether);
            token.mint(actor, 1000000e18);

            // Approve orders contracts
            vm.startPrank(actor);
            token.approve(address(rollupOrders), type(uint256).max);
            token.approve(address(hostOrders), type(uint256).max);
            vm.stopPrank();
        }
    }

    modifier useActor(uint256 actorIndex) {
        currentActor = actors[actorIndex % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Initiate an ETH order on rollup
    function initiateEthOrder(uint256 actorIndex, uint256 amount, address recipient, uint32 chainId)
        external
        useActor(actorIndex)
    {
        amount = bound(amount, 0, currentActor.balance);
        if (amount == 0) return;

        uint256 deadline = block.timestamp + 1 hours;

        IOrders.Input[] memory inputs = new IOrders.Input[](1);
        inputs[0] = IOrders.Input(address(0), amount);

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(0), amount, recipient, chainId);

        uint256 balanceBefore = address(rollupOrders).balance;
        rollupOrders.initiate{value: amount}(deadline, inputs, outputs);
        uint256 balanceAfter = address(rollupOrders).balance;

        totalEthInitiated += (balanceAfter - balanceBefore);
        orderCount++;
    }

    /// @notice Initiate a token order on rollup
    function initiateTokenOrder(uint256 actorIndex, uint256 amount, address recipient, uint32 chainId)
        external
        useActor(actorIndex)
    {
        amount = bound(amount, 0, token.balanceOf(currentActor));
        if (amount == 0) return;

        uint256 deadline = block.timestamp + 1 hours;

        IOrders.Input[] memory inputs = new IOrders.Input[](1);
        inputs[0] = IOrders.Input(address(token), amount);

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(token), amount, recipient, chainId);

        uint256 balanceBefore = token.balanceOf(address(rollupOrders));
        rollupOrders.initiate(deadline, inputs, outputs);
        uint256 balanceAfter = token.balanceOf(address(rollupOrders));

        totalTokenInitiated += (balanceAfter - balanceBefore);
        orderCount++;
    }

    /// @notice Sweep ETH from rollup orders
    function sweepEth(uint256 actorIndex, uint256 amount) external useActor(actorIndex) {
        amount = bound(amount, 0, address(rollupOrders).balance);
        if (amount == 0) return;

        uint256 balanceBefore = currentActor.balance;
        rollupOrders.sweep(currentActor, address(0), amount);
        uint256 balanceAfter = currentActor.balance;

        totalEthSwept += (balanceAfter - balanceBefore);
    }

    /// @notice Sweep tokens from rollup orders
    function sweepToken(uint256 actorIndex, uint256 amount) external useActor(actorIndex) {
        amount = bound(amount, 0, token.balanceOf(address(rollupOrders)));
        if (amount == 0) return;

        uint256 balanceBefore = token.balanceOf(currentActor);
        rollupOrders.sweep(currentActor, address(token), amount);
        uint256 balanceAfter = token.balanceOf(currentActor);

        totalTokenSwept += (balanceAfter - balanceBefore);
    }

    /// @notice Fill ETH outputs on host orders
    function fillEthOutput(uint256 actorIndex, uint256 amount, address recipient, uint32 chainId)
        external
        useActor(actorIndex)
    {
        amount = bound(amount, 0, currentActor.balance);
        if (amount == 0) return;
        if (recipient == address(0)) return;
        if (recipient == address(hostOrders)) return;
        if (recipient.code.length > 0) return; // Skip contracts to avoid revert on receive

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(0), amount, recipient, chainId);

        uint256 recipientBefore = recipient.balance;
        hostOrders.fill{value: amount}(outputs);
        uint256 recipientAfter = recipient.balance;

        totalEthFilled += (recipientAfter - recipientBefore);
    }

    /// @notice Fill token outputs on host orders
    function fillTokenOutput(uint256 actorIndex, uint256 amount, address recipient, uint32 chainId)
        external
        useActor(actorIndex)
    {
        amount = bound(amount, 0, token.balanceOf(currentActor));
        if (amount == 0) return;
        if (recipient == address(0)) return;
        if (recipient == address(hostOrders)) return;
        if (recipient == address(rollupOrders)) return;

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(token), amount, recipient, chainId);

        uint256 recipientBefore = token.balanceOf(recipient);
        hostOrders.fill(outputs);
        uint256 recipientAfter = token.balanceOf(recipient);

        totalTokenFilled += (recipientAfter - recipientBefore);
    }

    /// @notice Warp time forward
    function warpTime(uint256 delta) external {
        delta = bound(delta, 0, 7 days);
        vm.warp(block.timestamp + delta);
    }

    /// @notice Get rollup orders ETH balance
    function getRollupOrdersEthBalance() external view returns (uint256) {
        return address(rollupOrders).balance;
    }

    /// @notice Get rollup orders token balance
    function getRollupOrdersTokenBalance() external view returns (uint256) {
        return token.balanceOf(address(rollupOrders));
    }
}

/// @notice Invariant tests for Orders contracts
/// @dev Focus on fund safety during order initiation, sweeping, and filling
contract OrdersInvariantTest is StdInvariant, Test {
    RollupOrders public rollupOrders;
    HostOrders public hostOrders;
    OrdersHandler public handler;

    TestERC20 public token;

    // Permit2 mock address
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        // Deploy test token
        token = new TestERC20("TestToken", "TKN", 18);

        // Deploy orders contracts
        rollupOrders = new RollupOrders(PERMIT2);
        hostOrders = new HostOrders(PERMIT2);

        // Deploy handler
        handler = new OrdersHandler(rollupOrders, hostOrders, token);

        // Target only the handler
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(rollupOrders));
        excludeSender(address(hostOrders));
        excludeSender(address(handler));
    }

    /// @notice INVARIANT: RollupOrders ETH balance equals initiated minus swept
    /// @dev Critical fund safety - ETH in orders contract is accounted for
    function invariant_rollupOrdersEthBalance() public view {
        uint256 actualBalance = address(rollupOrders).balance;
        uint256 expectedBalance = handler.totalEthInitiated() - handler.totalEthSwept();

        assertEq(actualBalance, expectedBalance, "RollupOrders ETH balance mismatch");
    }

    /// @notice INVARIANT: RollupOrders token balance equals initiated minus swept
    /// @dev Critical fund safety for tokens
    function invariant_rollupOrdersTokenBalance() public view {
        uint256 actualBalance = token.balanceOf(address(rollupOrders));
        uint256 expectedBalance = handler.totalTokenInitiated() - handler.totalTokenSwept();

        assertEq(actualBalance, expectedBalance, "RollupOrders token balance mismatch");
    }

    /// @notice INVARIANT: Sweep cannot exceed balance
    /// @dev Fund safety - cannot sweep more than exists
    function invariant_sweepBounded() public view {
        assertGe(handler.totalEthInitiated(), handler.totalEthSwept(), "More ETH swept than initiated");
        assertGe(handler.totalTokenInitiated(), handler.totalTokenSwept(), "More tokens swept than initiated");
    }

    /// @notice INVARIANT: HostOrders holds no funds (passes through)
    /// @dev Fill sends directly to recipients
    function invariant_hostOrdersNoFunds() public view {
        assertEq(address(hostOrders).balance, 0, "HostOrders should not hold ETH");
        assertEq(token.balanceOf(address(hostOrders)), 0, "HostOrders should not hold tokens");
    }

    /// @notice INVARIANT: Orders can always be initiated (liveness)
    /// @dev System should be able to make progress
    function invariant_canInitiateOrder() public {
        address tester = address(0x7E57);
        vm.deal(tester, 1 ether);

        IOrders.Input[] memory inputs = new IOrders.Input[](1);
        inputs[0] = IOrders.Input(address(0), 0.1 ether);

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(0), 0.1 ether, tester, 1);

        uint256 balanceBefore = address(rollupOrders).balance;

        vm.prank(tester);
        rollupOrders.initiate{value: 0.1 ether}(block.timestamp + 1 hours, inputs, outputs);

        uint256 balanceAfter = address(rollupOrders).balance;
        assertEq(balanceAfter, balanceBefore + 0.1 ether, "Order initiation failed");
    }

    /// @notice INVARIANT: Fills can always deliver to recipients (liveness)
    function invariant_canFillOrder() public {
        address tester = address(0x7E572);
        address recipient = address(0xBEC1);
        vm.deal(tester, 1 ether);

        IOrders.Output[] memory outputs = new IOrders.Output[](1);
        outputs[0] = IOrders.Output(address(0), 0.1 ether, recipient, 1);

        uint256 recipientBefore = recipient.balance;

        vm.prank(tester);
        hostOrders.fill{value: 0.1 ether}(outputs);

        uint256 recipientAfter = recipient.balance;
        assertEq(recipientAfter, recipientBefore + 0.1 ether, "Fill failed to deliver");
    }

    /// @notice INVARIANT: Order count tracking
    function invariant_orderCountNonNegative() public view {
        assertGe(handler.orderCount(), 0, "Order count is negative");
    }
}
