pragma solidity ^0.8.20;

interface ILiquidLottery {

    enum Epoch { Pending, Open, Closed }

    struct Bucket {
      uint256 lowerBound;
      uint256 upperBound;
      uint256 totalDeposits;
    } 

    struct Pot {
      uint256 prize; 
      uint256 redeemed;
      mapping (address => bool) claim;
    }

    event Sync(uint256 indexed block, uint256 prize);

    event Lock(address indexed account, uint8 bucket, uint256 amount);

    event Claim(address indexed account, uint8 bucket, uint256 amount);

    event Unlock(address indexed account, uint8 bucket, uint256 amount);

    event Enter(address indexed account, uint256 collateral, uint256 tickets);

    event Exit(address indexed account, uint256 tickets, uint256 collateral);

    event Roll(uint256 indexed block, bytes32 entropy, uint8 bucket, uint256 prize);

}
