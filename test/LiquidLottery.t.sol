// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@interfaces/IERC20Base.sol";
import "@root/LiquidLottery.sol";
import "@root/TaxableERC20.sol";

contract LiquidLotteryTest is Test {

    IERC20Base _ticket;
    IERC20Base _collateral;
    LiquidLottery public _lottery;

    address constant AAVE_POOL_PROVIDER;
    address constant TOKEN_USDC_ADDRESS;
    address constant TOKEN_AUSDC_ADDRESS;
    address constant WITNET_ORACLE_ADDRESS;

    function setUp() public {
      new _lottery = LiquidLottery();
    }

    function testMint() public {}

    function testBurn() public {}

    function testDraw() public {}

    function testStake() public {}

    function testClaim() public {}

    function testTaxes() public {}

    function testRebates() public {}

    function testLeverageSelfRepayment public {}

    function testLeverageManualRepayment public {}

    function testDelegation public {}

}
