pragma solidity ^0.8.13;

import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";

contract LiquidLottery is ILiquidLottery {

    mapping (address => Stake) public _stakes;
    mapping (uint8 => Bucket) public _buckets;

    uint256 constant OPEN_EPOCH = 5 days;
    uint256 constant PENDING_EPOCH = 1 days;
    uint256 constant CLOSED_EPOCH = 1 days;
    uint256 constant CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    address public _oracle; 
    address public _operator;
    address public _collateral;

    uint256 public reserves;

    constructor(
        address oracle,
        address operator,
        address collateral,
    ) {
        _oracle = oracle;
        _operator = operator;
        _collateral = collateral;
    }

    function currentEpoch() public view returns (Epoch) {
        uint256 timeInCycle = block.timestamp % CYCLE;

        if (timeInCycle < OPEN_EPOCH) {
          return Epoch.Open;
        } else if (timeInCycle < OPEN_EPOCH + PENDING_EPOCH) {
          return Epoch.Pending;
        } else {
          return Epoch.Closed;
        }
    }

}
