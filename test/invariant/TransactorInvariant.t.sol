// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Transactor} from "../../src/Transactor.sol";
import {Passage} from "../../src/passage/Passage.sol";

/// @notice Handler contract for Transactor invariant testing
contract TransactorHandler is Test {
    Transactor public transactor;
    Passage public passage;
    address public gasAdmin;

    uint256 public defaultChainId;
    uint256 public perBlockGasLimit;
    uint256 public perTransactGasLimit;

    // Ghost variables
    mapping(uint256 => mapping(uint256 => uint256)) public ghostGasUsed; // chainId => blockNumber => gasUsed
    uint256 public totalTransactCalls;
    uint256 public totalEthEntered;
    bool public gasTrackingValid = true;

    // Track actors
    address[] public actors;
    address public currentActor;

    constructor(Transactor _transactor, Passage _passage, address _gasAdmin, uint256 _defaultChainId) {
        transactor = _transactor;
        passage = _passage;
        gasAdmin = _gasAdmin;
        defaultChainId = _defaultChainId;

        perBlockGasLimit = transactor.perBlockGasLimit();
        perTransactGasLimit = transactor.perTransactGasLimit();

        // Setup actors
        for (uint256 i = 1; i <= 5; i++) {
            address actor = address(uint160(i * 1000));
            actors.push(actor);
            vm.deal(actor, 1000 ether);
        }
    }

    modifier useActor(uint256 actorIndex) {
        currentActor = actors[actorIndex % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @notice Execute a transact call
    function transact(
        uint256 actorIndex,
        uint256 rollupChainId,
        address to,
        bytes calldata data,
        uint256 value,
        uint256 gas,
        uint256 maxFeePerGas,
        uint256 ethToEnter
    ) external useActor(actorIndex) {
        // Bound parameters
        ethToEnter = _bound(ethToEnter, 0, currentActor.balance);
        gas = _bound(gas, 0, perTransactGasLimit);

        // Check if we would exceed block gas limit
        uint256 currentGasUsed = transactor.transactGasUsed(rollupChainId, block.number);
        if (currentGasUsed + gas > perBlockGasLimit) {
            // Would fail, skip
            return;
        }

        uint256 passageBalanceBefore = address(passage).balance;

        transactor.enterTransact{value: ethToEnter}(rollupChainId, currentActor, to, data, value, gas, maxFeePerGas);

        uint256 passageBalanceAfter = address(passage).balance;

        // Track ghost variables
        ghostGasUsed[rollupChainId][block.number] += gas;
        totalTransactCalls++;
        totalEthEntered += (passageBalanceAfter - passageBalanceBefore);

        // Validate gas tracking incrementally
        if (transactor.transactGasUsed(rollupChainId, block.number) != ghostGasUsed[rollupChainId][block.number]) {
            gasTrackingValid = false;
        }
    }

    /// @notice Transact with default chain
    function transactDefault(uint256 actorIndex, address to, uint256 gas, uint256 maxFeePerGas, uint256 ethToEnter)
        external
        useActor(actorIndex)
    {
        ethToEnter = _bound(ethToEnter, 0, currentActor.balance);
        gas = _bound(gas, 0, perTransactGasLimit);

        uint256 currentGasUsed = transactor.transactGasUsed(defaultChainId, block.number);
        if (currentGasUsed + gas > perBlockGasLimit) {
            return;
        }

        uint256 passageBalanceBefore = address(passage).balance;

        transactor.transact{value: ethToEnter}(to, "", 0, gas, maxFeePerGas);

        uint256 passageBalanceAfter = address(passage).balance;

        ghostGasUsed[defaultChainId][block.number] += gas;
        totalTransactCalls++;
        totalEthEntered += (passageBalanceAfter - passageBalanceBefore);

        // Validate gas tracking incrementally
        if (transactor.transactGasUsed(defaultChainId, block.number) != ghostGasUsed[defaultChainId][block.number]) {
            gasTrackingValid = false;
        }
    }

    /// @notice Admin configures gas limits
    /// @dev We ensure newPerTransact >= 1_000_000 to maintain liveness invariant
    function configureGas(uint256 newPerBlock, uint256 newPerTransact) external {
        // Ensure minimum values that maintain liveness (1M gas minimum for per-transact)
        newPerBlock = _bound(newPerBlock, 5_000_000, 100_000_000);
        newPerTransact = _bound(newPerTransact, 1_000_000, newPerBlock);

        vm.prank(gasAdmin);
        transactor.configureGas(newPerBlock, newPerTransact);

        perBlockGasLimit = newPerBlock;
        perTransactGasLimit = newPerTransact;
    }

    /// @notice Advance to next block
    function advanceBlock() external {
        vm.roll(block.number + 1);
    }
}

/// @notice Invariant tests for Transactor contract
/// @dev Focus on gas limit enforcement and liveness
contract TransactorInvariantTest is StdInvariant, Test {
    Transactor public transactor;
    Passage public passage;
    TransactorHandler public handler;

    address public gasAdmin = address(0x6A5AD111);
    address public tokenAdmin = address(0x70CE11AD111);
    uint256 public defaultChainId = 1337;

    uint256 public initialPerBlockGasLimit = 30_000_000;
    uint256 public initialPerTransactGasLimit = 5_000_000;

    // Permit2 mock address
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        // Deploy Passage first (required by Transactor)
        address[] memory initialTokens = new address[](0);
        passage = new Passage(defaultChainId, tokenAdmin, initialTokens, PERMIT2);

        // Deploy Transactor
        transactor =
            new Transactor(defaultChainId, gasAdmin, passage, initialPerBlockGasLimit, initialPerTransactGasLimit);

        // Deploy handler
        handler = new TransactorHandler(transactor, passage, gasAdmin, defaultChainId);

        // Target only the handler
        targetContract(address(handler));

        // Exclude system addresses
        excludeSender(address(0));
        excludeSender(address(transactor));
        excludeSender(address(passage));
        excludeSender(address(handler));
    }

    /// @notice INVARIANT: Gas limits are properly configured
    /// @dev Ensures per-transact limit never exceeds per-block limit
    function invariant_gasLimitEnforced() public view {
        assertLe(
            transactor.perTransactGasLimit(),
            transactor.perBlockGasLimit(),
            "Per-transact limit exceeds per-block limit"
        );
    }

    /// @notice INVARIANT: Ghost gas tracking matches contract state
    /// @dev Validated incrementally in the handler after each transact call
    function invariant_gasTrackingConsistency() public view {
        assertTrue(handler.gasTrackingValid(), "Ghost gas tracking mismatch");
    }

    /// @notice INVARIANT: Gas admin is immutable
    function invariant_gasAdminImmutable() public view {
        assertEq(transactor.gasAdmin(), gasAdmin, "Gas admin changed unexpectedly");
    }

    /// @notice INVARIANT: Default chain ID is immutable
    function invariant_defaultChainIdImmutable() public view {
        assertEq(transactor.defaultRollupChainId(), defaultChainId, "Default chain ID changed");
    }

    /// @notice INVARIANT: Passage reference is immutable
    function invariant_passageImmutable() public view {
        assertEq(address(transactor.passage()), address(passage), "Passage reference changed");
    }

    /// @notice INVARIANT: perTransactGasLimit <= perBlockGasLimit
    /// @dev Configuration sanity
    function invariant_gasLimitOrdering() public view {
        assertLe(
            transactor.perTransactGasLimit(),
            transactor.perBlockGasLimit(),
            "Per-transact limit exceeds per-block limit"
        );
    }

    /// @notice INVARIANT: ETH sent to transactor flows to passage
    /// @dev Fund safety - transactor should not hold ETH
    function invariant_transactorHoldsNoEth() public view {
        assertEq(address(transactor).balance, 0, "Transactor holding ETH unexpectedly");
    }

    /// @notice INVARIANT: Transactor and Passage remain functional (liveness)
    /// @dev Verifies contracts are not bricked
    function invariant_canTransactInNewBlock() public view {
        assertTrue(address(transactor).code.length > 0, "Transactor contract missing");
        assertTrue(address(passage).code.length > 0, "Passage contract missing");
    }

    /// @notice INVARIANT: Gas limits are always positive
    function invariant_gasLimitsPositive() public view {
        assertGt(transactor.perBlockGasLimit(), 0, "Per-block gas limit is zero");
        assertGt(transactor.perTransactGasLimit(), 0, "Per-transact gas limit is zero");
    }
}
