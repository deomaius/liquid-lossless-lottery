// test/LiquidLotteryFuzzFork.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {LiquidLottery} from "@root/LiquidLottery.sol";
import {TaxableERC20} from "@root/TaxableERC20.sol";
import {ILiquidLottery} from "@interfaces/ILiquidLottery.sol";
import {IERC20Base} from "@interfaces/IERC20Base.sol";
import {IAaveLendingPool} from "@interfaces/IAaveLendingPool.sol";

contract LiquidLotteryFuzzFork is Test {
    LiquidLottery public lottery;
    IERC20Base public collateral;
    TaxableERC20 public ticket;

    address constant AAVE_POOL_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant WITNET_ORACLE_ADDRESS = 0xC0FFEE98AD1434aCbDB894BbB752e138c1006fAB;
    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3;
    address constant TOKEN_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant COORDINATOR_ADDRESS = 0x2C51b758cda56c31EF4E77533226aFA2dE3829D2;
    address constant CONTROLLER_ADDRESS = 0xd780400322dbEE448a3C52290b8fb4Bc0aE3Cfa5;

    address constant USER = address(0x1234);
    uint256 constant LARGE_USDC_AMOUNT = type(uint56).max; // 72 billion usdc

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        lottery = new LiquidLottery(
            AAVE_POOL_PROVIDER,
            WITNET_ORACLE_ADDRESS,
            AAVE_DATA_PROVIDER,
            CONTROLLER_ADDRESS,
            TOKEN_USDC_ADDRESS,
            COORDINATOR_ADDRESS,
            "LotteryTicket",
            "LTK",
            1e6,
            500,
            8e17,
            2000,
            5
        );

        collateral = IERC20Base(TOKEN_USDC_ADDRESS);
        ticket = TaxableERC20(address(lottery._ticket()));

        deal(address(collateral), USER, LARGE_USDC_AMOUNT);
        vm.prank(USER);
        collateral.approve(address(lottery), type(uint128).max);
    }

    function warpToEpoch(ILiquidLottery.Epoch targetEpoch) internal {
        uint256 elapsed = block.timestamp - lottery._start();
        uint256 cycleTime = lottery.CYCLE();
        uint256 timeInCycle = elapsed % cycleTime;

        if (targetEpoch == ILiquidLottery.Epoch.Open) {
            if (timeInCycle >= lottery.OPEN_EPOCH()) {
                vm.warp(block.timestamp + (cycleTime - timeInCycle));
            }
        } else if (targetEpoch == ILiquidLottery.Epoch.Pending) {
            if (timeInCycle < lottery.OPEN_EPOCH()) {
                vm.warp(block.timestamp + (lottery.OPEN_EPOCH() - timeInCycle));
            } else if (timeInCycle >= lottery.OPEN_EPOCH() + lottery.PENDING_EPOCH()) {
                vm.warp(block.timestamp + (cycleTime - timeInCycle) + lottery.OPEN_EPOCH());
            }
        }
    }

    // 2**56 breaks aave (72 billion)
    function testFuzz_mint(uint48 amount) public {
        warpToEpoch(ILiquidLottery.Epoch.Open);
        assertTrue(lottery.currentEpoch() == ILiquidLottery.Epoch.Open, "Not in Open epoch");

        // Expect empty state at start
        assertEq(ticket.balanceOf(USER), 0, "User should start with no tickets");
        assertEq(lottery._reserves(), 0, "Reserves should start at 0");
        assertEq(ticket.totalSupply(), 0, "Total supply should start at 0");
        assertEq(lottery._voucher().balanceOf(address(lottery)), 0, "Voucher balance should start at 0");

        // Calculate expected values independently
        uint256 collateralScaled = lottery.scale(amount, lottery._decimalC(), lottery._decimalT());
        uint256 rate = lottery.scale(lottery.collateralPerShare(), lottery._decimalC(), lottery._decimalT());
        uint256 expectedTickets = collateralScaled * 1e18 / rate;

        vm.prank(USER);

        // Should revert if given 0 amount (aave reverts)
        if (amount == 0) {
            vm.expectRevert();
            lottery.mint(amount);
            return;
        }

        // Call mint with amount > 0 && < uint48.max
        vm.expectEmit(true, true, false, true);
        emit ILiquidLottery.Enter(USER, amount, expectedTickets);
        lottery.mint(amount);

        assertEq(ticket.balanceOf(USER), expectedTickets, "Incorrect ticket balance");
        // NOTE Aave rounds certain amounts down by 1 wei
        assertApproxEqAbs(lottery._voucher().balanceOf(address(lottery)), amount, 1, "Incorrect voucher balance");
        assertEq(lottery._reserves(), amount, "Incorrect reserves");
        assertEq(ticket.totalSupply(), expectedTickets, "Incorrect total supply");
    }

    // TODO: there seems to be a rounding issue
    function testFuzz_burn(uint48 amount) public {
        // Start in Open epoch to mint tickets
        warpToEpoch(ILiquidLottery.Epoch.Open);

        vm.prank(USER);

        // Make sure 0 amount is handled correctly
        if (amount == 0) {
            lottery.mint(10e6);

            warpToEpoch(ILiquidLottery.Epoch.Pending);

            uint256 collateralBalanceBefore = collateral.balanceOf(USER);
            uint256 ticketBalanceBefore = ticket.balanceOf(USER);
            uint256 voucherBalanceBefore = lottery._voucher().balanceOf(address(lottery));

            vm.expectRevert();
            lottery.burn(amount); // No revert expected in LiquidLottery

            assertEq(ticket.balanceOf(USER), ticketBalanceBefore, "Ticket balance changed with zero burn");
            assertEq(lottery._reserves(), 10e6, "Reserves changed with zero burn");
            assertEq(
                lottery._voucher().balanceOf(address(lottery)),
                voucherBalanceBefore,
                "Voucher balance changed with zero burn"
            );
            assertEq(collateral.balanceOf(USER), collateralBalanceBefore, "Collateral balance changed with zero burn");
            return;
        }

        // Mint initial tickets (e.g., 1 million USDC worth)
        lottery.mint(amount);

        // Warp to Pending epoch for burn
        warpToEpoch(ILiquidLottery.Epoch.Pending);

        // Capture initial state after minting
        uint256 userTicketBalanceBefore = ticket.balanceOf(USER);
        uint256 reservesBefore = lottery._reserves();
        uint256 totalSupplyBefore = ticket.totalSupply();
        uint256 voucherBalanceBefore = lottery._voucher().balanceOf(address(lottery));
        uint256 userCollateralBefore = collateral.balanceOf(USER);

        // Calculate expected values
        uint256 rate = lottery.scale(lottery.collateralPerShare(), lottery._decimalC(), lottery._decimalT());
        uint256 expectedDeposit =
            lottery.scale(userTicketBalanceBefore * rate / 1e18, lottery._decimalT(), lottery._decimalC());

        // Call burn function
        vm.prank(USER);
        vm.expectEmit(true, true, false, true);
        emit ILiquidLottery.Exit(USER, expectedDeposit, userTicketBalanceBefore);
        lottery.burn(userTicketBalanceBefore);

        // Make sure state is correct
        assertEq(ticket.balanceOf(USER), 0, "Incorrect ticket balance");
        assertApproxEqAbs(
            lottery._voucher().balanceOf(address(lottery)),
            voucherBalanceBefore - expectedDeposit,
            1,
            "Incorrect voucher balance"
        );
        assertEq(lottery._reserves(), reservesBefore - expectedDeposit, "Incorrect reserves");
        assertEq(ticket.totalSupply(), totalSupplyBefore - userTicketBalanceBefore, "Incorrect total supply");
        assertEq(
            collateral.balanceOf(USER), userCollateralBefore + expectedDeposit, "Incorrect user collateral balance"
        );
    }
}
