// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@interfaces/IERC20Base.sol";
import "@root/TaxableERC20.sol";

import "@root/LiquidLottery.sol" ;

contract LiquidLotteryTest is Test {

    IERC20Base _ticket;
    IERC20Base _collateral;
    LiquidLottery public _lottery;

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

    function setUp() public {
        _lottery = new LiquidLottery(
            AAVE_POOL_PROVIDER,
            WITNET_ORACLE_ADDRESS,
            AAVE_DATA_PROVIDER,
            CONTROLLER_ADDRESS,
            TOKEN_USDC_ADDRESS,
            COORDINATOR_ADDRESS,
            "Test ticket",
            "TICKET",
            10 ** 6,
            500,
            0.5 ether, 
            1000,
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
        uint256 premium = _lottery.currentPremium() - 10000;

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

            _lottery.claim(benefactorShare, 2);

            uint256 remainder = _lottery.rewards(BENEFACTOR_ADDRESS, 2);

            _lottery.claim(remainder, 2);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------BENEFACTOR------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _lottery.claim(counterpartyShare, 2);

            remainder = _lottery.rewards(COUNTERPARTY_ADDRESS, 2);
            
            _lottery.claim(remainder, 2);

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

            // Verify premium 
            assertGt(_collateral.balanceOf(COUNTERPARTY_ADDRESS), totalBalance);

            vm.stopPrank();
        /* --------------------------------- */

    }

    function testTaxesAndRebates() public {
        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 10000 * 10 ** 6);
            _lottery.mint(10000 * 10 ** 6);

            uint taxAmount = 250 ether;
            uint transferAmount = 5000 ether - taxAmount;

            _ticket.transfer(COUNTERPARTY_ADDRESS, 5000 ether);

            assertEq(_ticket.balanceOf(COUNTERPARTY_ADDRESS), transferAmount);

            vm.stopPrank();
        /* --------------------------------- */ 

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);

            _lottery.issueRebate(CONTROLLER_ADDRESS, 250 ether);

            assertEq(_ticket.balanceOf(CONTROLLER_ADDRESS), 250 ether);

            vm.stopPrank();
        /* --------------------------------- */ 

    }

    function testLeverage() public {
       /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);
            _ticket.approve(address(_lottery), 1000 ether);
            _lottery.stake(1000 ether, 2);

            vm.stopPrank();
        /* --------------------------------- */ 

        /* -------------BENEFACTOR------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            _collateral.approve(address(_lottery), 3333 * 10 ** 6);
            _lottery.mint(3333 * 10 ** 6);
            _ticket.approve(address(_lottery), 3333 ether);
            _lottery.stake(3333 ether, 1);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 6 days + 12 hours + 1 minutes);

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);

            _lottery.draw(0xf8e26f279ea45fd39902669f33626cbc6ddd1fd2ec78e38979912ded9f332c76);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 12 hours);
   
        /* -------------COUNTERPARTY------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);
            
            _lottery.unstake(3333 ether, 1);
            _ticket.approve(address(_lottery), 3333 ether);
            _lottery.stake(3333 ether, 2);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            uint256 preRewards = _lottery.rewards(BENEFACTOR_ADDRESS, 2);
            uint256 preCredit = _lottery.credit(BENEFACTOR_ADDRESS, 2, address(0x0));

            _lottery.leverage(BENEFACTOR_ADDRESS, preCredit, 2);
            _lottery.rewards(BENEFACTOR_ADDRESS, 2);

            uint256 postCredit = _lottery.credit(BENEFACTOR_ADDRESS, 2, address(0x0));
            uint256 postRewards = _lottery.rewards(BENEFACTOR_ADDRESS, 2);
            uint256 collateralBalance = 9000 * 10 ** 6 + preCredit;

            assertEq(_collateral.balanceOf(BENEFACTOR_ADDRESS), collateralBalance);
            assertEq(preCredit, preRewards / 2);
            assertEq(postRewards, 0);
            assertEq(postCredit, 0);

            vm.stopPrank();
        /* --------------------------------- */

        vm.warp(block.timestamp + 6 days + 12 hours + 1 minutes);

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);

            _lottery.draw(0xf8e26f279ea45fd39902669f33626cbc6ddd1fd2ec78e38979912ded9f332c76);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 12 hours);
       
        /* ----------BENEFACTOR--------------- */
            vm.startPrank(BENEFACTOR_ADDRESS);
                
            uint256 preDebit = _lottery.rewards(BENEFACTOR_ADDRESS, 2);
            uint256 preInterest = _lottery.interestDue(BENEFACTOR_ADDRESS, 2);
            uint256 preDebt = _lottery.debt(BENEFACTOR_ADDRESS, 2);

            uint256 debit = preInterest + preDebit;

            _collateral.approve(address(_lottery), debit);
            _lottery.repay(debit, 2);

            uint256 postDebit = _lottery.rewards(BENEFACTOR_ADDRESS, 2);
            uint256 postInterest = _lottery.interestDue(BENEFACTOR_ADDRESS, 2);
            uint256 postDebt = _lottery.debt(BENEFACTOR_ADDRESS, 2);

            uint256 outstandingDebt = preDebt - preInterest - (preDebit * 2);

            assertEq(postInterest, 0);
            assertEq(postDebt, outstandingDebt);
            assertEq(postDebit, 0);

            vm.stopPrank();
        /* --------------------------------- */ 
    }

    function testDelegation() public {

       /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            _collateral.approve(address(_lottery), 1000 * 10 ** 6);
            _lottery.mint(1000 * 10 ** 6);
            _ticket.approve(address(_lottery), 1000 ether);
            _lottery.stake(1000 ether, 2);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 6 days + 12 hours + 1 minutes);

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);

            _lottery.draw(0xf8e26f279ea45fd39902669f33626cbc6ddd1fd2ec78e38979912ded9f332c76);

            vm.stopPrank();
        /* --------------------------------- */ 


        vm.warp(block.timestamp + 14 days);

        /* -------------CONTROLLER------------ */
            vm.startPrank(CONTROLLER_ADDRESS);

            _lottery.draw(0xf8e26f279ea45fd39902669f33626cbc6ddd1fd2ec78e38979912ded9f332c76);

            vm.stopPrank();
        /* --------------------------------- */ 

        vm.warp(block.timestamp + 12 hours);
   
        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            uint256 benefactorRewards = _lottery.rewards(BENEFACTOR_ADDRESS, 2);
            uint256 benefactorCredit = _lottery.credit(BENEFACTOR_ADDRESS, 2, address(0x0));

            _lottery.delegate(COUNTERPARTY_ADDRESS, 2, 14 days);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------COUNTERPARTY------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            uint256 preBalance = _collateral.balanceOf(COUNTERPARTY_ADDRESS);
            uint256 preCredit = _lottery.credit(COUNTERPARTY_ADDRESS, 2, BENEFACTOR_ADDRESS);

            _lottery.leverage(BENEFACTOR_ADDRESS, preCredit / 2, 2);

            uint256 postBalance = _collateral.balanceOf(COUNTERPARTY_ADDRESS);
            uint256 postCredit = _lottery.credit(COUNTERPARTY_ADDRESS, 2, BENEFACTOR_ADDRESS);
            uint256 postRewards = _lottery.rewards(BENEFACTOR_ADDRESS, 2);

            uint256 diff = postCredit - preCredit / 2;  // 465
            uint256 basisPoints = (diff * 10000) / preCredit;  
            uint256 expectedCredit = preCredit / 2 + ((preCredit * basisPoints) / 10000);

            assertEq(postBalance, 10000 * 10 ** 6 + preCredit / 2);
            // Percision loss makes post > actual
            assertGt(postCredit, expectedCredit);

            vm.stopPrank();
        /* --------------------------------- */

        /* -------------BENEFACTOR------------ */
            vm.startPrank(BENEFACTOR_ADDRESS);

            vm.expectRevert();
            _lottery.leverage(BENEFACTOR_ADDRESS, 1, 2);

            vm.stopPrank();
        /* --------------------------------- */

        vm.warp(block.timestamp + 14 days + 1 minutes);

        /* -------------COUNTERPARTY------------ */
            vm.startPrank(COUNTERPARTY_ADDRESS);

            vm.expectRevert();
            _lottery.leverage(BENEFACTOR_ADDRESS, 1, 2);

            vm.stopPrank();
        /* --------------------------------- */

    }

}
