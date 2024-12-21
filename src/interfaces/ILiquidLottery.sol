pragma solidity ^0.8.20;

interface ILiquidLottery {

    enum Epoch { Pending, Open, Closed }

    struct Bucket {
      uint256 lowerBound;
      uint256 upperBound;
      uint256 totalOdds;
    } 

    struct Stake {
      uint8 bucket;
      uint256 odds; 
      uint256 deposit;
    }

}
