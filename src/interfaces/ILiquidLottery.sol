pragma solidity ^0.8.20;

interface ILiquidLottery {

    enum Epoch { Pending, Open, Closed }

    struct Stake {
      uint256 deposit; 
      uint256 checkpoint;
    } 

    struct Bucket {
      uint256 totalRewards;
      uint256 totalDeposits;
      uint256 rewardCheckpoint;
    } 

    event Funnel(uint256 amount);

    event Sync(uint256 indexed block, uint256 prize);

    event Lock(address indexed account, uint8 bucket, uint256 amount);

    event Claim(address indexed account, uint8 bucket, uint256 amount);

    event Unlock(address indexed account, uint8 bucket, uint256 amount);

    event Enter(address indexed account, uint256 collateral, uint256 tickets);

    event Exit(address indexed account, uint256 tickets, uint256 collateral);

    event Roll(uint256 indexed block, bytes32 entropy, uint8 bucket, uint256 prize);

}
