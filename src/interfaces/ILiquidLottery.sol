pragma solidity ^0.8.20;

interface ILiquidLottery {

    enum Epoch { Pending, Open, Closed }


    struct Note { 
      uint256 debt;                     // @param Outstanding payments 
      uint256 timestamp;                // @param Position creation / basis 
      uint256 collateral;               // @param Ticket denominated collateral value
    }

    struct Credit {
      uint256 liabilities;              // @param Total outstanding payments 
      mapping (int8 => Note) notes;     // @param Note position mapping    
    }

    struct Stake {
      uint256 deposit;                  // @param Ticket denominated stake value  
      uint256 checkpoint;               // @param Bucket reward checkpoint value
      uint256 outstanding;              // @param Locked ticket denominated value
    } 

    struct Bucket {
      uint256 totalRewards;             // @param Unclaimed bucket rewards  
      uint256 totalDeposits;            // @param Total bucket ticket denominated stake value
      uint256 rewardCheckpoint;         // @param Checkpoint value of totalRewards
    } 

    event Funnel(uint256 amount);

    event Sync(uint256 indexed block, uint256 prize);

    event Lock(address indexed account, uint8 bucket, uint256 amount);

    event Claim(address indexed account, uint8 bucket, uint256 amount);

    event Unlock(address indexed account, uint8 bucket, uint256 amount);

    event Repayment(address indexed account, uin8 bucket, uint256 debit);

    event Enter(address indexed account, uint256 collateral, uint256 tickets);

    event Exit(address indexed account, uint256 tickets, uint256 collateral);

    event Leverage(address indexed account, uint256 collateral, uint256 principal);

    event Roll(uint256 indexed block, bytes32 entropy, uint8 bucket, uint256 prize);

}
