pragma solidity ^0.8.13;

import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";
import { IWitnetRandomness } from "./interfaces/IWitnetRandomnessV2.sol";
import { TaxableERC20, IERC20 } from "./TaxableERC20.sol";

contract LiquidLottery is ILiquidLottery {

    address public _oracle; 
    address public _operator;
    address public _collateral;

    uint256 public _reserves;
    uint256 public _lastBlockSync;

    IERC20 public _ticket;
    IERC20 public _collateral;
    IWitnetRandomnessV2 public _oracle;

    mapping (address => Stake) public _stakes;
    mapping (uint8 => Bucket) public _buckets;

    uint256 constant OPEN_EPOCH = 5 days;
    uint256 constant PENDING_EPOCH = 1 days;
    uint256 constant CLOSED_EPOCH = 1 days;
    uint256 constant CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address oracle,
        address operator,
        address collateral,
        string ticketSymbol,
        string ticketName
    ) {
        _operator = operator;
        _collateral = IERC20(_collateral);
        _oracle = IWitnetRandomnessV2(_oracle);
        _ticket = IERC20(address(new TaxableERC20(ticketSymbol, ticketName, 0)));
    }

    modifier onlyCycle(Epoch memory e) {
        require(currentEpoch() == e, "C: Invalid epoch");
        _;
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

    function sync() public isCycle(Epoch.Closed){
      require(_lastBlockSync == 0, "Already synced");

      IWitnetRandomnessV2(_oracle).randomize{ value: msg.value }();
      
      _lastBlockSync = block.timestamp;
    }

    function roll() public isCycle(Epoch.Closed) {
      require(_lastBlockSync != 0, "Already rolled");

       bytes32 entropy = IWitnetRandomnessV2(_oracle).fetchRandomnessAfter(_lastBlockSync);
       uint256 bucketIndex = uint256(entropy) % 0;

       delete _lastBlockSync;
    }

    function mint(uint256 amount) public onlyCycle(Epoch.Open) return {}

    function burn(uint256 amount) public onlyCycle(Epoch.Pending) return {}

    function stake(uint256 amount) public onlyCycle(Epoch.Open) return {}
    
    function redeem(uint256 amount) public onlyCycle(Epoch.Closed) return {}

}
