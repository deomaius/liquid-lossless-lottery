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

    address constant PRANK_ADDRESS = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address constant BENEFACTOR_ADDRESS = 0x385ec61686050E78ED440Cd74d6Aa1Eb1fe767F9;
    address constant COUNTERPARTY_ADDRESS = 0x8223498C52747Af8d9808970a950afbc5D02758C;
    address constant COORDINATOR_ADDRESS = 0x2C51b758cda56c31EF4E77533226aFA2dE3829D2;
    address constant CONTROLLER_ADDRESS = 0xd780400322dbEE448a3C52290b8fb4Bc0aE3Cfa5;

    address constant AAVE_DATA_PROVIDER = 0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d;
    address constant AAVE_POOL_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant TOKEN_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant TOKEN_AUSDC_ADDRESS = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant WITNET_PROXY_ADDRESS = 0x77703aE126B971c9946d562F41Dd47071dA00777;
    address constant WITNET_ORACLE_ADDRESS = 0xC0FFEE98AD1434aCbDB894BbB752e138c1006fAB;

    function setUp() public {
        _lottery = new LiquidLottery(
            AAVE_POOL_PROVIDER,
            WITNET_ORACLE_ADDRESS,
            AAVE_DATA_PROVIDER,
            CONTROLLER_ADDRESS,
            TOKEN_USDC_ADDRESS,
            COORDINATOR_ADDRESS,
            "Test Ticket",
            "TICKET",
            10 ** 6,
            200000, 
            10000,
            12
        );
        _collateral = IERC20Base(TOKEN_USDC_ADDRESS);
        _ticket = IERC20Base(_lottery._ticket());

        vm.deal(COORDINATOR_ADDRESS, 1 ether);
        vm.deal(COUNTERPARTY_ADDRESS, 1 ether);
        vm.deal(BENEFACTOR_ADDRESS, 1 ether);
        vm.deal(CONTROLLER_ADDRESS, 1 ether);

        /* -------------PRANKSTER------------ */
            vm.startPrank(PRANK_ADDRESS);

            _collateral.transfer(BENEFACTOR_ADDRESS, 10000 * 10 ** 6);
            _collateral.transfer(COUNTERPARTY_ADDRESS, 10000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */

        vm.roll(block.number + 10); 
    }

    function testMint() public {
        /* -------------BENEFACTOR------------ */
            vm.startPrank(PRANK_ADDRESS);

            _lottery.currentEpoch();

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */ 
    }

    function testBurn() public {}

    function testDraw() public {}

    function testStake() public {}

    function testClaim() public {}

    function testTaxes() public {}

    function testRebates() public {}

    function testLeverageSelfRepayment() public {}

    function testLeverageManualRepayment() public {}

    function testDelegation() public {}

}
