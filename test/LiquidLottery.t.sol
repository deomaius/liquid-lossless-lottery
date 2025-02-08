// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@interfaces/IERC20Base.sol";
import "@root/LiquidLottery.sol";
import "@root/TaxableERC20.sol";

import "./mock/MockLottery.sol";

contract LiquidLotteryTest is Test {

    IERC20Base _ticket;
    IERC20Base _collateral;
    MockLottery public _lottery;

    address constant PRANK_ADDRESS = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address constant BENEFACTOR_ADDRESS = 0x385ec61686050E78ED440Cd74d6Aa1Eb1fe767F9;
    address constant COUNTERPARTY_ADDRESS = 0x8223498C52747Af8d9808970a950afbc5D02758C;
    address constant COORDINATOR_ADDRESS = 0x2C51b758cda56c31EF4E77533226aFA2dE3829D2;
    address constant CONTROLLER_ADDRESS = 0xd780400322dbEE448a3C52290b8fb4Bc0aE3Cfa5;

    address constant AAVE_DATA_PROVIDER = 0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3; 
    address constant AAVE_POOL_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant TOKEN_USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant TOKEN_AUSDC_ADDRESS = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address constant WITNET_PROXY_ADDRESS = 0x77703aE126B971c9946d562F41Dd47071dA00777;
    address constant WITNET_ORACLE_ADDRESS = 0xC0FFEE98AD1434aCbDB894BbB752e138c1006fAB;

    // @TODO:Math 

    function setUp() public {
        _lottery = new MockLottery(
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
            4
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
    }

    function testMint() public {
        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);

            assertEq(_ticket.balanceOf(BENEFACTOR_ADDRESS), 1000 ether);
            assertEq(_collateral.balanceOf(BENEFACTOR_ADDRESS), 9000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------BENEFACTOR------------ */
           vm.startPrank(COUNTERPARTY_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);

            assertEq(_ticket.balanceOf(COUNTERPARTY_ADDRESS), 1000 ether);
            assertEq(_collateral.balanceOf(BENEFACTOR_ADDRESS), 9000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */

    }

    function testBurn() public {
        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */ 
 
        /* -------------COUNTERPARTY------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 4 days + 1 minutes);

        /* -------------COUNTERPARTY------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _ticket.approve(address(_lottery), 1000 ether);
            _lottery.burn(1000 ether);

            assertEq(_collateral.balanceOf(COUNTERPARTY_ADDRESS), 10000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */ 

        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _ticket.approve(address(_lottery), 1000 ether);
            _lottery.burn(1000 ether);

            assertEq(_collateral.balanceOf(BENEFACTOR_ADDRESS), 10000 * 10 ** 6);

            vm.stopPrank();
        /* --------------------------------- */ 
    }

    function testStakeDrawAndClaim() public {
        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 2000 * 10 ** 6);
            _lottery.mint(2000 * 10 ** 6);
            _ticket.approve(address(_lottery), 2000 ether);
            _lottery.stake(1000 ether, 0);
            _lottery.stake(1000 ether, 2);

            vm.stopPrank();
        /* --------------------------------- */ 

        /* -------------BENEFACTOR------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _collateral.approve(address(_lottery), 9999 * 10 ** 6);
            _lottery.mint(9999 * 10 ** 6);
            _ticket.approve(address(_lottery), 9999 ether);
            _lottery.stake(3333 ether, 1);
            _lottery.stake(3333 ether, 2);
            _lottery.stake(3333 ether, 3);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 6 days + 12 hours + 1 minutes);

        // Factor for percison loss  
        uint256 premium = _lottery.currentPremium() - 5000;

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);
            vm.recordLogs();

            _lottery.draw(0xf8e26f279ea45fd39902669f33626cbc6ddd1fd2ec78e38979912ded9f332c76);

            Vm.Log[] memory entries = vm.getRecordedLogs();

            assertEq(entries[0].topics[2], bytes32(uint256(2)));

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 12 hours);
   
        uint256 coordinatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000;   // 20%
        uint256 prizeShare = premium - coordinatorShare - ticketShare; // 70%

        uint256 counterpartyShare = (prizeShare * 3333 * 1e6) / 4333;
        uint256 benefactorShare = (prizeShare * 1000 * 1e6) / 4333;

        counterpartyShare = counterpartyShare / 1e6;
        benefactorShare = benefactorShare / 1e6;

        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            console.log(msg.sender);

            _lottery.claim(benefactorShare, 2);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------BENEFACTOR------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _lottery.claim(counterpartyShare, 2);

            vm.stopPrank();
        /* --------------------------------- */

        vm.warp(block.timestamp + 4 days);

        /* -------------BENEFACTOR------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _lottery.unstake(3333 ether, 2);
            _ticket.approve(address(_lottery), 3333 ether);
            _lottery.burn(3333 ether);

            uint256 newBalance = 10000 * 10 ** 6 + counterpartyShare;
            uint256 outstandingBalance = 6666 * 10 ** 6;
            uint256 totalBalance = newBalance - outstandingBalance;

            // Verify that the premium was added to the ticket balance 
            assertGt(_collateral.balanceOf(COUNTERPARTY_ADDRESS), totalBalance);

            vm.stopPrank();
        /* --------------------------------- */

    }

    function testTaxes() public {}

    function testRebates() public {}

    function testLeverageSelfRepayment() public {}

    function testLeverageManualRepayment() public {}

    function testDelegation() public {}

}
