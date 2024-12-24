pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { IAavePoolProvider } from "@interfaces/IAavePoolProvider.sol";
import { IAaveDataProvider } from "@interfaces/IAaveDataProvider.sol";
import { IAaveLendingPool } from "@interfaces/IAaveLendingPool.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";

import { TaxableERC20 } from "./TaxableERC20.sol";

contract LiquidLottery is ILiquidLottery {

    address public _operator;

    uint8 public _bucketId;
    uint8 public _decimalV;
    uint8 public _decimalC;
    uint8 public _decimalT;
    uint256 public _locked;
    uint256 public _reserves;
    uint256 public _premium;
    uint256 public _lastBlockSync;

    IERC20 public _ticket;
    IERC20 public _voucher;
    IERC20 public _collateral;
    IAaveLendingPool public _pool;
    IWitnetRandomnessV2 public _oracle;

    mapping (uint8 => Bucket) public _buckets;
    mapping (uint256 => mapping (uint8 => uint)) public _pots;
    mapping (address => mapping (uint8 => uint)) public _stakes;

    uint256 constant public BUCKET_COUNT = 10;
    uint256 constant public OPEN_EPOCH = 5 days;
    uint256 constant public PENDING_EPOCH = 1 days;
    uint256 constant public CLOSED_EPOCH = 1 days;
    uint256 constant public TICKET_BASE_PRICE = 1000 wei;
    uint256 constant public CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address pool,
        address oracle,
        address operator,
        address provider,
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
        _pool = IAaveLendingPool(IAavePoolProvider(pool).getPool());
        _ticket = IERC20(address(new TaxableERC20(5e16, name, symbol, 0)));

        (address voucher,,) = IAaveDataProvider(provider).getReserveTokensAddresses(collateral);

        _voucher = IERC20(voucher);
        _decimalV = _voucher.decimals();
        _decimalC = _collateral.decimals();
        _decimalT = 1e18;
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

    function ticketPrice() public view return (uint256) {
        uint256 reserves = scale(_reserves, _decimalC, 18);
        uint256 multiplier = TICKET_BASE_PRICE * reserves / 1e24;

        return TICKET_BASE_PRICE + multiplier; 
    }

    function currentPremium() public view returns (uint256) {
        uint256 interest = _voucher.balanceOf(address(this));

        if (premiumEarned > _reserves) return interest - _reserves;
        
        return  0;
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
        uint8 bucketId = index > 9 ? index - 1 : index;

        Pot storage pot = _pots[_lastBlockSync][bucketId];

        require(pot.prize == 0, "Already rolled");

        // TODO: Premium allocations
        pot.prize += currentPremium();

        _bucketId = bucketId;

        emit Roll(block.timestamp, entropy, bucketId, 0);
    }

    function mint(uint256 amount) public onlyCycle(Epoch.Open) syncBlock {
        _collateral.transferFrom(msg.sender, address(this), amount);
        _collateral.approve(address(_pool), amount);      
        _pool.supply(address(_collateral), amount, address(this), 0);

        uint256 price = ticketPrice();
        uint256 tickets = amount * 1e18 / price;

        _ticket.mint(msg.sender, tickets);
        _reserves += amount;

        emit Enter(msg.sender, amount, tickets);
    }

    function burn(uint256 amount) public onlyCycle(Epoch.Pending) syncBlock {
        uint256 reserves = scale(_reserves, _decimalC, 18);
        uint256 proportion = amount * 1e18 / _ticket.totalSupply();
        uint256 alloc = proportion * reserves / 1e18;
        uint256 reciept = scale(alloc, 18, _decimalC);

        uint256 deposit = pool.withdraw(address(_collateral), alloc, address(this));

        _ticket.burn(msg.sender, amount);
        _collateral.transferFrom(address(this), msg.sender, deposit);
        _reserves -= deposit;

        emit Exit(msg.sender, deposit, amount);
    }
 
    function claim(uint8 index) public onlyCycle(Epoch.Closed) {
        Pot storage pot = _pots[_lastBlockSync][index];

        uint256 staked = _buckets[_bucketId].totalDeposits;
        uint256 deposit = _stakes[msg.sender][index];

        require(index == _bucketId, "Invalid bucket");
        require(staked > 0, "No bucket stakes active");
        require(deposit > 0, "Insufficient stake"); 
        require(!pot.claim[msg.sender], "Already claimed");

        uint256 alloc = deposit * 1e18 / staked;
        uint256 prize = scale(pot.prize, _decimalC, 18);
        uint256 reward = scale(alloc * prize / 1e18, 18, _decimalC);

        pot.redeemed += reward; 
        pot.claim[msg.sender] = true;

        _collateral.transferFrom(address(this), msg.sender, reward); 

        emit Claim(msg.sender, index, reward);
    }

    function stake(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        _locked += amount;
        _stakes[msg.sender][index] += amount;
        _buckets[index].totalDeposits += amount;

        _ticket.transferFrom(msg.sender, address(this), amount);

        emit Lock(msg.sender, index, amount);
    }

    function withdraw(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        uint256 deposit = _stakes[msg.sender][index];

        require(amount <= deposit, "Insufficient balance");

        _locked -= amount;
        _buckets[index].totalDeposits -= amount;
        _stakes[msg.sender][index] = deposit - amount;

        _ticket.transferFrom(address(this), msg.sender, amount);

        emit Unlock(msg.sender, index, amount);
    }

    function scale(uint256 amount, uint8 d1, uint8 d2) internal pure returns (uint256) {
      if (d1 < d2) {
        return amount * (10 ** uint256(d2 - d1));
      } else if (d1 > d2) {
        return amount / (10 ** uint256(d1 - d2));
      }
      return amount;
    }

}
