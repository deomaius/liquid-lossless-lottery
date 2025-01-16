pragma solidity ^0.8.20;

interface ILiquidLottery {

    enum Epoch { Pending, Open, Closed }

    struct Stake {
      uint256 deposit;                              // @param Ticket denominated stake value  
      uint256 checkpoint;                           // @param Bucket reward checkpoint value
      uint256 outstanding;                          // @param Locked ticket denominated value
    } 

    struct Bucket {
      uint256 totalRewards;                         // @param Unclaimed bucket rewards  
      uint256 totalDeposits;                        // @param Total ticket denominated stake value
      uint256 rewardCheckpoint;                     // @param Checkpoint value of totalRewards
    } 

    struct Note { 
      uint256 debt;                                 // @param Outstanding payments  
      uint256 interest;                             // @param Position interest 
      uint256 principal;                            // @param Nominal collateral denominated value 
      uint256 timestamp;                            // @param Position creation / basis 
      uint256 collateral;                           // @param Position ticket denominated stake 
    }

    struct Delegate {
      uint256 expiry;                               // @param Delegation expiry timestamp
      address delegate;                             // @param Delegation target address
    }

    struct Credit {
      uint256 liabilities;                          // @param Total outstanding payments 
      mapping (uint8 => Note) notes;                 // @param Note position mapping 
      mapping (uint8 => Delegate) delegations;       // @param Delegations mapping
    } 

    event Failsafe(bool state);

    event Funnel(uint256 amount);

    event Config(uint256 ltv, uint256 apy);

    event Config(address indexed controller);

    event Sync(uint256 indexed block, uint256 prize);
    
    event Delegate(address indexed from, address indexed to, uint256 expiry);

    event Enter(address indexed account, uint256 collateral, uint256 tickets);

    event Exit(address indexed account, uint256 tickets, uint256 collateral);

    event Lock(address indexed account, uint8 indexed bucket, uint256 amount);

    event Claim(address indexed account, uint8 indexed bucket, uint256 amount);

    event Unlock(address indexed account, uint8 indexed bucket, uint256 amount);

    event Repayment(address indexed account, uint8 indexed bucket, uint256 debit);

    event Roll(uint256 indexed block, bytes32 entropy, uint8 indexed bucket, uint256 prize);

    event Leverage(address indexed account, address indexed delegate, uint256 collateral, uint256 principal);

}
