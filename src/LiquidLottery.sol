pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";

import { TaxableERC20 } from "./TaxableERC20.sol";

contract LiquidLottery is ILiquidLottery {

    address public _operator;

    uint8 public _bucketId;
    uint256 public _locked;
    uint256 public _reserves;
    uint256 public _premium;
    uint256 public _lastBlockSync;

    IERC20 public _ticket;
    IERC20 public _collateral;
    IWitnetRandomnessV2 public _oracle;

    mapping (uint8 => Bucket) public _buckets;
    mapping (address => mapping (uint8 => Stake)) public _stakes;

    uint256 constant public BUCKET_COUNT = 10;
    uint256 constant public OPEN_EPOCH = 5 days;
    uint256 constant public PENDING_EPOCH = 1 days;
    uint256 constant public CLOSED_EPOCH = 1 days;
    uint256 constant public CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address oracle,
        address operator,
        address collateral,
        string memory name,
        string memory symbol
    ) {
        _operator = operator;

        _buckets[0] = Bucket(0, 10e16, 0);           // 0-10
        _buckets[1] = Bucket(10e16, 20e16, 0);       // 10-20
        _buckets[2] = Bucket(20e16, 30e16, 0);       // 20-30
        _buckets[3] = Bucket(30e16, 40e16, 0);       // 30-40
        _buckets[4] = Bucket(40e16, 50e16, 0);       // 90-50
        _buckets[5] = Bucket(50e16, 60e16, 0);       // 50-60
        _buckets[6] = Bucket(60e16, 70e16, 0);       // 60-70
        _buckets[7] = Bucket(70e16, 80e16, 0);       // 70-80
        _buckets[8] = Bucket(80e16, 90e16, 0);       // 80-90
        _buckets[9] = Bucket(90e16, 1e18, 0);        // 90-100

        _collateral = IERC20(collateral);
        _oracle = IWitnetRandomnessV2(oracle);
        _ticket = IERC20(address(new TaxableERC20(5e16, name, symbol, 0)));
    }

    modifier onlyCycle(Epoch e) {
        require(currentEpoch() == e, "C: Invalid epoch");
        _;
    }

    modifier notCycle(Epoch e) {
        require(currentEpoch() != e, "C: Invalid epoch");
        _;
    }

    modifier syncBlock() {
       if (_lastBlockSync != 0) delete _lastBlockSync;
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

    function sync() public payable onlyCycle(Epoch.Closed) {
        require(_lastBlockSync == 0, "Already synced");

        _oracle.randomize{ value: msg.value }(); 
        _lastBlockSync = block.number;

        emit Sync(block.timestamp, 0);
    }

    function roll() public onlyCycle(Epoch.Closed) {
        require(_lastBlockSync != 0, "Already rolled");

        bytes32 entropy = _oracle.fetchRandomnessAfter(_lastBlockSync);
        uint8 index = uint8(uint256(entropy) % BUCKET_COUNT);

        _bucketId = index > 9 ? index - 1 : index;

        Pot storage pot = _pot[_lastBlockSync][_bucketId];

        require(pot.prize == 0, "Already rolled");

        // TODO: Premium allocations
        pot.prize += _premium;

        emit Roll(block.timestamp, entropy, index, 0);
    }

    function mint(uint256 amount) public onlyCycle(Epoch.Open) public syncBlock {}

    function burn(uint256 amount) public onlyCycle(Epoch.Pending) public syncBlock {}
 
    function claim(uint8 index) public onlyCycle(Epoch.Closed) {
        Pot storage pot = _pot[_lastBlockSync][index];
        Stake storage slot = _stakes[msg.sender][index];

        uint256 staked = _buckets[_bucketId].totalOdds;

        require(index == _bucketId, "Invalid bucket");
        require(staked > 0, "No bucket stakes active");
        require(slot.deposit > 0, "Insufficient stake"); 
        require(!pot.claim[msg.sender], "Already claimed");

        uint256 odds = slot.deposit * 1e18 / staked;
        uint256 reward = odds * pot.prize / 1e18;

        pot.redeemed += reward; 
        pot.claim[msg.sender] = true;

        _collateral.transferFrom(address(this), msg.sender, reward); 

        emit Claim(msg.sender, index, reward);
    }

    function stake(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        Stake storage slot = _stakes[msg.sender][index];

        // @TODO: odds calculation
        slot.odds = 0;
        slot.deposit += amount;

        _locked += amount;
        _buckets[index].totalOdds += amount;

        _ticket.transferFrom(msg.sender, address(this), amount);

        emit Lock(msg.sender, index, amount);
    }

    function withdraw(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        Stake storage slot = _stakes[msg.sender][index];
        
        require(amount <= slot.deposit, "Insufficient balance");

        // @TODO: odds calculation
        slot.odds = 0;
        slot.deposit -= amount;

        _locked -= amount;
        _buckets[index].totalOdds -= amount;

        _ticket.transferFrom(address(this), msg.sender, amount);

        emit Unlock(msg.sender, index, amount);
    } 

}
