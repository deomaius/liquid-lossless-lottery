// test/LiquidLotteryInvariants.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import { LiquidLottery } from "@root/LiquidLottery.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";
import { TaxableERC20 } from "@root/TaxableERC20.sol";
import { IERC20Base } from "@interfaces/IERC20Base.sol";
import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { IAavePoolProvider } from "@interfaces/IAavePoolProvider.sol";
import { IAaveDataProvider } from "@interfaces/IAaveDataProvider.sol";
import { IAaveLendingPool } from "@interfaces/IAaveLendingPool.sol";

contract Handler is Test {
    LiquidLottery public lottery;
    IERC20Base public collateral;
    IERC20Base public ticket;

    constructor(LiquidLottery _lottery, IERC20Base _collateral, IERC20Base _ticket) {
        lottery = _lottery;
        collateral = _collateral;
        ticket = _ticket;
    }

    function mint(uint256 amount) public {
        amount = bound(amount, 1e6, 100e6); // 1 to 100 USDC
        vm.assume(lottery.currentEpoch() == ILiquidLottery.Epoch.Open);
        collateral.approve(address(lottery), amount);
        lottery.mint(amount);
    }

    function burn(uint256 amount) public {
        amount = bound(amount, 1e18, ticket.balanceOf(address(this)));
        vm.assume(lottery.currentEpoch() == ILiquidLottery.Epoch.Pending);
        lottery.burn(amount);
    }

    function stake(uint256 amount, uint8 index) public {
        amount = bound(amount, 1e18, ticket.balanceOf(address(this)));
        index = uint8(bound(index, 0, lottery._slots() - 1));
        vm.assume(lottery.currentEpoch() != ILiquidLottery.Epoch.Closed);
        vm.assume(lottery.rewards(address(this), index) == 0);
        ticket.approve(address(lottery), amount);
        lottery.stake(amount, index);
    }

    function unstake(uint256 amount, uint8 index) public {
        index = uint8(bound(index, 0, lottery._slots() - 1));
        ILiquidLottery.Stake memory stake = lottery.getStake(address(this), index);
        uint256 balance = stake.deposit - stake.outstanding;
        amount = bound(amount, 1e18, balance);
        vm.assume(lottery.currentEpoch() != ILiquidLottery.Epoch.Closed);
        vm.assume(lottery.rewards(address(this), index) == 0);
        lottery.unstake(amount, index);
    }

    function draw() public {
        vm.assume(lottery.currentEpoch() == ILiquidLottery.Epoch.Closed);
        vm.assume(lottery.isOracleReady());
        lottery.draw();
    }

    function sync() public {
        vm.assume(lottery.currentEpoch() == ILiquidLottery.Epoch.Closed);
        vm.assume(lottery._lastBlockSync() == 0);
        lottery.sync{value: 1 ether}(); // Assume some ETH for Witnet
    }

    function leverage(address from, uint256 amount, uint8 index) public {
        index = uint8(bound(index, 0, lottery._slots() - 1));
        amount = bound(amount, 1e6, lottery.rewards(from, index));
        vm.assume(lottery.currentEpoch() != ILiquidLottery.Epoch.Closed);
        vm.assume(lottery.delegatedTo(from, index) == address(this));
        lottery.leverage(from, amount, index);
    }

    function repay(uint256 amount, uint8 index) public {
        index = uint8(bound(index, 0, lottery._slots() - 1));
        ILiquidLottery.Note memory note = lottery.getCreditNote(address(this), index);
        amount = bound(amount, 1e6, note.debt);
        vm.assume(lottery.currentEpoch() != ILiquidLottery.Epoch.Closed);
        collateral.approve(address(lottery), amount);
        lottery.repay(amount, index);
    }
}

contract LiquidLotteryInvariants is Test {
    LiquidLottery public lottery;
    Handler public handler;
    IERC20Base public collateral;
    IERC20Base public ticket;
    IERC20Base public voucher;

    // Mainnet addresses (Ethereum mainnet examples)
    address constant AAVE_POOL_PROVIDER = 0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5; // Aave V2 Pool Provider
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;          // USDC token
    address constant AAVE_DATA_PROVIDER = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d; // Aave V2 Data Provider
    address constant WITNET_ORACLE = 0x5a7Ed3b370C9f0eD3eC274271055885c7D4b2ac6;    // Witnet Randomness (example)

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        // Deploy the lottery contract
        lottery = new LiquidLottery(
            AAVE_POOL_PROVIDER,
            WITNET_ORACLE,
            AAVE_DATA_PROVIDER,
            address(this), // Controller (this test contract)
            USDC,          // Collateral (USDC)
            address(this), // Coordinator (this test contract)
            "LotteryTicket",
            "LTK",
            1e6,           // 1 USDC per ticket
            500,           // 5% tax (in bps)
            8e17,          // 80% LTV
            2000,          // 20% APY (in bps)
            5              // 5 bucket slots
        );

        collateral = IERC20Base(USDC);
        ticket = lottery._ticket();
        voucher = lottery._voucher();

        // Set up handler and give it collateral/tickets
        handler = new Handler(lottery, collateral, ticket);
        deal(address(collateral), address(handler), 1000e6); // 1000 USDC
        deal(address(ticket), address(handler), 1000e18);   // 1000 tickets
        vm.startPrank(address(handler));
        collateral.approve(address(lottery), type(uint256).max);
        ticket.approve(address(lottery), type(uint256).max);
        vm.stopPrank();

        // Target the handler for fuzzing
        targetContract(address(handler));
    }

    // Invariant 1: Reserves should never go negative
    function invariant_reserves_non_negative() public {
        assertTrue(lottery._reserves() >= 0, "Reserves went negative");
    }

    // Invariant 2: Total ticket supply matches collateral backing
    function invariant_ticket_supply_matches_reserves() public {
        uint256 ticketSupply = ticket.totalSupply();
        uint256 reservesScaled = lottery.scale(lottery._reserves(), lottery._decimalC(), lottery._decimalT());
        uint256 collateralPerShare = lottery.collateralPerShare();
        uint256 expectedTickets = reservesScaled * 1e18 / collateralPerShare;

        // Allow some rounding error due to scaling
        assertApproxEqAbs(ticketSupply, expectedTickets, 1e12, "Ticket supply mismatch with reserves");
    }

    // Invariant 3: Bucket totalDeposits never exceed ticket supply
    function invariant_bucket_deposits_bounded() public {
        uint256 totalBucketDeposits = 0;
        for (uint8 i = 0; i < lottery._slots(); i++) {
            ILiquidLottery.Bucket memory bucket = lottery.getBucket(i);
            totalBucketDeposits += bucket.totalDeposits;
        }
        assertTrue(totalBucketDeposits <= ticket.totalSupply(), "Bucket deposits exceed ticket supply");
    }

    // Invariant 4: Current premium is non-negative
    function invariant_premium_non_negative() public {
        assertTrue(lottery.currentPremium() >= 0, "Premium went negative");
    }

    // Invariant 5: Epoch cycle timing is consistent
    function invariant_epoch_cycle_consistent() public {
        uint256 elapsed = block.timestamp - lottery._start();
        uint256 cycleTime = lottery.CYCLE();
        ILiquidLottery.Epoch current = lottery.currentEpoch();

        uint256 timeInCycle = elapsed % cycleTime;
        if (timeInCycle < lottery.OPEN_EPOCH()) {
            assertEq(uint8(current), uint8(ILiquidLottery.Epoch.Open), "Epoch should be Open");
        } else if (timeInCycle < lottery.OPEN_EPOCH() + lottery.PENDING_EPOCH()) {
            assertEq(uint8(current), uint8(ILiquidLottery.Epoch.Pending), "Epoch should be Pending");
        } else {
            assertEq(uint8(current), uint8(ILiquidLottery.Epoch.Closed), "Epoch should be Closed");
        }
    }

    // Invariant 6: Stake deposit >= outstanding
    function invariant_stake_deposit_gte_outstanding() public {
        for (uint8 i = 0; i < lottery._slots(); i++) {
            ILiquidLottery.Stake memory stake = lottery.getStake(address(handler), i);
            assertTrue(stake.deposit >= stake.outstanding, "Stake deposit less than outstanding");
        }
    }

    // Invariant 7: Credit liabilities match sum of note debts
    function invariant_credit_liabilities_consistent() public {
        uint256 liabilities = lottery.getCreditLiabilities(address(handler));
        uint256 totalDebt = 0;
        for (uint8 i = 0; i < lottery._slots(); i++) {
            ILiquidLottery.Note memory note = lottery.getCreditNote(address(handler), i);
            totalDebt += note.debt;
        }
        assertEq(liabilities, totalDebt, "Credit liabilities mismatch with note debts");
    }

    // Invariant 8: Bucket rewardCheckpoint never decreases
    function invariant_reward_checkpoint_monotonic() public {
        for (uint8 i = 0; i < lottery._slots(); i++) {
            ILiquidLottery.Bucket memory bucket = lottery.getBucket(i);
            assertTrue(bucket.rewardCheckpoint >= 0, "Reward checkpoint went negative");
        }
    }
}
