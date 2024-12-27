pragma solidity ^0.8.20;

import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { IAavePoolProvider } from "@interfaces/IAavePoolProvider.sol";
import { IAaveDataProvider } from "@interfaces/IAaveDataProvider.sol";
import { IAaveLendingPool } from "@interfaces/IAaveLendingPool.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";
import { IERC20Base } from "@interfaces/IERC20Base.sol";

import { TaxableERC20 } from "./TaxableERC20.sol";

contract LiquidLottery is ILiquidLottery {

    address public _operator;

    uint8 public _decimalV;
    uint8 public _decimalC;
    uint8 public _decimalT;
    uint256 public _opfees;
    uint256 public _reserves;
    uint256 public _lastBlockSync;

    IERC20Base public _ticket;
    IERC20Base public _voucher;
    IERC20Base public _collateral;
    IAaveLendingPool public _pool;
    IWitnetRandomnessV2 public _oracle;

    mapping (uint8 => Bucket) public _buckets;
    mapping (address => mapping (uint8 => Stake)) public _stakes;

    uint256 constant public BUCKET_COUNT = 12;
    uint256 constant public OPEN_EPOCH = 4 days;
    uint256 constant public CLOSED_EPOCH = 12 hours;
    uint256 constant public PENDING_EPOCH = 2 days + 12 hours; 
    uint256 constant public CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;
    uint256 constant public TICKET_BASE_PRICE = 1000 wei;

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

        _collateral = IERC20Base(collateral);
        _oracle = IWitnetRandomnessV2(oracle);
        _pool = IAaveLendingPool(IAavePoolProvider(pool).getPool());
        _ticket = IERC20Base(address(new TaxableERC20(5e16, name, symbol, 0)));

        (address voucher,,) = IAaveDataProvider(provider).getReserveTokensAddresses(collateral);

        _voucher = IERC20Base(voucher);
        _decimalC = _collateral.decimals();
        _decimalV = _voucher.decimals();
        _decimalT = 18;
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


    function collateralPerShare() public view returns (uint256) {
        uint256 supply = _ticket.totalSupply();
        uint256 reserves = scale(_reserves, _decimalC, _decimalT);

        if (supply == 0) return TICKET_BASE_PRICE;
        
        return (reserves * 1e18) / supply;
    }

    function currentPremium() public view returns (uint256) {
        uint256 interest = _voucher.balanceOf(address(this)) - _opfees;

        if (interest > _reserves) return interest - _reserves;

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

        emit Sync(block.number, 0);
    }

    function roll() public onlyCycle(Epoch.Closed) {
        require(_lastBlockSync != 0, "Already rolled");
 
        bytes32 entropy = _oracle.fetchRandomnessAfter(_lastBlockSync);
        uint8 index = uint8(uint256(entropy) % BUCKET_COUNT);
        uint8 bucketId = index > 9 ? index - 1 : index;

        Bucket storage bucket = _buckets[bucketId];

        uint256 premium = currentPremium();
        uint256 operatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000;   // 20% 
        uint256 prizeShare = premium - operatorShare - ticketShare; // 70%

        bucket.totalRewards += prizeShare;
        bucket.rewardCheckpoint += prizeShare;

        _opfees += operatorShare;
        _reserves += ticketShare;

        emit Roll(block.number, entropy, bucketId, 0);
    }

    function mint(uint256 amount) public onlyCycle(Epoch.Open) syncBlock {
        _collateral.transferFrom(msg.sender, address(this), amount);
        _collateral.approve(address(_pool), amount);      
        _pool.supply(address(_collateral), amount, address(this), 0);

        uint256 tickets = amount * 1e18 / collateralPerShare();

        _reserves += amount;
        _ticket.mint(msg.sender, tickets);

        emit Enter(msg.sender, amount, tickets);
    }

    function burn(uint256 amount) public onlyCycle(Epoch.Pending) syncBlock {
        uint256 allocation = amount * collateralPerShare() / 1e18;
        uint256 collateral = scale(allocation, _decimalT, _decimalC);

        _ticket.burn(msg.sender, amount);

        uint256 deposit = _pool.withdraw(address(_collateral), collateral, address(this));

        _reserves -= deposit;
        _collateral.transferFrom(address(this), msg.sender, deposit);

        emit Exit(msg.sender, deposit, amount);
    }
 
    function claim(uint8 index) public onlyCycle(Epoch.Closed) {
        Stake storage stake = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        require(stake.deposit > 0, "Insufficient stake");
        require(bucket.rewardCheckpoint > stake.checkpoint, "Already claimed");

        uint256 surplus = bucket.rewardCheckpoint - stake.checkpoint;
        uint256 alloc = stake.deposit * 1e18 / bucket.totalDeposits;
        uint256 prize = scale(surplus, _decimalC, _decimalT);
        uint256 reward = scale(alloc * prize / 1e18, _decimalT, _decimalC);

        bucket.totalRewards -= reward;
        stake.checkpoint = bucket.rewardCheckpoint;

        uint256 share = _pool.withdraw(address(_collateral), reward, address(this));

        _collateral.transferFrom(address(this), msg.sender, share); 

        emit Claim(msg.sender, index, reward);
    }

    function stake(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        require(BUCKET_COUNT >= index, "Invalid bucket index");

        Stake storage stake = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        stake.deposit += amount;
        stake.checkpoint = bucket.rewardCheckpoint;
        bucket.totalDeposits += amount;

        _ticket.transferFrom(msg.sender, address(this), amount);

        emit Lock(msg.sender, index, amount);
    }

    function withdraw(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        require(BUCKET_COUNT >= index, "Invalid bucket index");

        Stake storage stake = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        require(stake.deposit >= amount, "Insufficient balance");

        stake.deposit -= amount;
        stake.checkpoint = bucket.rewardCheckpoint;
        bucket.totalDeposits -= amount;

        _ticket.transferFrom(address(this), msg.sender, amount);

        emit Unlock(msg.sender, index, amount);
    }

    function scale(uint256 amount, uint8 d1, uint8 d2) internal pure returns (uint256) {
        if (d1 < d2) {
          return amount * (10 ** uint256(d2 - d1));
        } else if (d1 > d2) {
          uint256 f = 10 ** uint256(d1 - d2);

          return (amount + f / 2) / f;
        }
        return amount;
    }

    function funnel() public {
        require(_opfees > 0, "Not enough fees to funnel");
        
        uint256 fees = _pool.withdraw(address(_collateral), _opfees, address(this));

        _opfees = 0;
        _collateral.transferFrom(address(this), _operator, fees);

        emit Funnel(fees);
    }

}
