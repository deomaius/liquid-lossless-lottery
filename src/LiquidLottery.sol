pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";

import { TaxableERC20 } from "./TaxableERC20.sol";

contract LiquidLottery is ILiquidLottery {

    address public _operator;

    uint8 public _bucketId;
    uint256 public _reserves;
    uint256 public _lastBlockSync;

    IERC20 public _ticket;
    IERC20 public _collateral;
    IWitnetRandomnessV2 public _oracle;

    mapping (address => Stake) public _stakes;
    mapping (uint8 => Bucket) public _buckets;

    uint256 constant public BUCKET_COUNT = 10;
    uint256 constant public OPEN_EPOCH = 5 days;
    uint256 constant public PENDING_EPOCH = 1 days;
    uint256 constant public CLOSED_EPOCH = 1 days;
    uint256 constant public CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address oracle,
        address operator,
        address collateral,
        string memory ticketName,
        string memory ticketSymbol
    ) {
        _operator = operator;

        _buckets[0] = Bucket(0, 10e16, 0);           // 0-10%
        _buckets[1] = Bucket(10e16, 20e16, 0);       // 10-20%
        _buckets[2] = Bucket(20e16, 30e16, 0);       // 20-30%
        _buckets[3] = Bucket(30e16, 40e16, 0);       // 30-40%
        _buckets[4] = Bucket(40e16, 50e16, 0);       // 90-50%
        _buckets[5] = Bucket(50e16, 60e16, 0);       // 50-60%
        _buckets[6] = Bucket(60e16, 70e16, 0);       // 60-70%
        _buckets[7] = Bucket(70e16, 80e16, 0);       // 70-80%
        _buckets[8] = Bucket(80e16, 90e16, 0);       // 80-90%
        _buckets[9] = Bucket(90e16, 1e18, 0);        // 90-100%

        _collateral = IERC20(_collateral);
        _oracle = IWitnetRandomnessV2(_oracle);
        _ticket = IERC20(address(new TaxableERC20(5e16, ticketSymbol, ticketName, 0)));
    }

    modifier onlyCycle(Epoch e) {
        require(currentEpoch() == e, "C: Invalid epoch");
        _;
    }

    modifier notCycle(Epoch e) {
        require(currentEpoch() != e, "C: Invalid epoch");
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

    function sync() public onlyCycle(Epoch.Closed){
      require(_lastBlockSync == 0, "Already synced");

      _oracle.randomize{ value: msg.value }();
      
      _lastBlockSync = block.timestamp;
    }

    function roll() public onlyCycle(Epoch.Closed) {
      require(_lastBlockSync != 0, "Already rolled");

       bytes32 entropy = _oracle.fetchRandomnessAfter(_lastBlockSync);
       uint256 index = uint256(entropy) % BUCKET_COUNT;

      _bucketId = uint8(index > 9 ? index - 1 : index);
      _lastBlockSync = 0;
    }

    function mint(uint256 amount) public onlyCycle(Epoch.Open) {}

    function burn(uint256 amount) public onlyCycle(Epoch.Pending) {}
 
    function redeem(uint256 amount) public onlyCycle(Epoch.Closed) {}

    function stake(uint8 bucket, uint256 amount) public notCycle(Epoch.Closed) {}

}
