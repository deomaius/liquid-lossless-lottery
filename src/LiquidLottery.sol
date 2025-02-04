pragma solidity ^0.8.20;

import { IWitnetRandomnessV2 } from "@interfaces/IWitnetRandomnessV2.sol";
import { IAavePoolProvider } from "@interfaces/IAavePoolProvider.sol";
import { IAaveDataProvider } from "@interfaces/IAaveDataProvider.sol";
import { IAaveLendingPool } from "@interfaces/IAaveLendingPool.sol";
import { ILiquidLottery } from "@interfaces/ILiquidLottery.sol";
import { IERC20Base } from "@interfaces/IERC20Base.sol";

import { TaxableERC20 } from "./TaxableERC20.sol";

/*
    * @title Liquid Lossless Lottery
    * @author deomaius
    * @description An egalitarian prize-savings pool with a liquid ticket system 
*/

contract LiquidLottery is ILiquidLottery {

    bool public _failsafe;

    uint8 public _slots;
    uint8 public _decimalV;
    uint8 public _decimalC;
    uint8 public _decimalT;

    uint256 public _opfees;
    uint256 public _limitLtv;
    uint256 public _limitApy;
    uint256 public _reserves;
    uint256 public _reservePrice;
    uint256 public _lastBlockSync;

    address public _controller;
    address public _coordinator;

    IERC20Base public _ticket;
    IERC20Base public _voucher;
    IERC20Base public _collateral;
    IAaveLendingPool public _pool;
    IWitnetRandomnessV2 public _oracle;

    mapping (uint8 => Bucket) public _buckets;
    mapping (address => Credit) public _credit;
    mapping (address => mapping (uint => Stake)) public _stakes;

    uint256 constant public OPEN_EPOCH = 4 days;
    uint256 constant public CLOSED_EPOCH = 12 hours;
    uint256 constant public PENDING_EPOCH = 2 days + 12 hours; 
    uint256 constant public CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address pool,               // @param Aave lending pool address
        address oracle,             // @param Witnet oracle address
        address provider,           // @param Aave pool provider address
        address controller,         // @param Lottery controller address
        address collateral,         // @param Lottery collateral token address 
        address coordinator,        // @param Lottery coordinator address
        string memory name,         // @param Lottery ticket name
        string memory symbol,       // @param Lottery ticket symbol 
        uint256 ticketBasePrice,    // @param Lottery ticket base conversion rate
        uint256 ltvMultiplier,      // @param Lottery loan-to-value (LTV) multiplier
        uint256 limitingApy,        // @param Lottery annual per year (APY) rate
        uint8 bucketSlots           // @param Lottery bucket count 
    ) {
        _slots = bucketSlots;
        _controller = controller;
        _coordinator = coordinator;
        _reservePrice = ticketBasePrice;
        _limitLtv = ltvMultiplier;
        _limitApy = limitingApy;

        _collateral = IERC20Base(collateral);
        _oracle = IWitnetRandomnessV2(oracle);
        _pool = IAaveLendingPool(IAavePoolProvider(pool).getPool());
        _ticket = IERC20Base(address(new TaxableERC20(500, name, symbol, 0)));

        (address voucher,,) = IAaveDataProvider(provider).getReserveTokensAddresses(collateral);

        _voucher = IERC20Base(voucher);
        _decimalC = _collateral.decimals();
        _decimalV = _voucher.decimals();
        _decimalT = 18;
    }

    /*    @dev Control statement for configuration        */
    modifier onlyController() {
        require (msg.sender != _controller, "Invalid controller");
        _;
    }

    /*    @dev Control statement for a epoch pnase        */
    modifier onlyCycle(Epoch e) {
        require(currentEpoch() == e, "Invalid epoch");
        _;
    }

    /*    @dev Control statement for not an epoch pnase   */
    modifier notCycle(Epoch e) {
        require(currentEpoch() != e, "Invalid epoch");
        _;
    }

    /*    @dev Oracle state sync                          */
    modifier syncBlock() {
        if (_lastBlockSync != 0) delete _lastBlockSync;
        _;
    }

    /*
        * @dev Outstanding debt helper
        * @param account Target address
        * @return Collateral denominated debt
    */
    function debt(address account) public view returns (uint256) {
        return _credit[account].liabilities;
    }

    /*
        * @dev Active credit helper
        * @param account Target address
        * @param index Bucket index value
        * @param index Delegator address
        * @return Collateral denominated credit
    */
    function credit(address account, uint8 index, address delegator) public view returns (uint256) {
        uint256 base = rewards(account, index);

        if (account != delegator && delegatedTo(account, index) == delegator) {
            base += rewards(delegator, index);
        }
    
        return base * _limitLtv / 10000;
    }

    /*
        * @dev Unclaimed rewards helper
        * @param account Target address
        * @param index Bucket index value
        * @return Collateral denominated rewards 
    */
    function rewards(address account, uint8 index) public view returns (uint256) {
        Stake storage vault = _stakes[account][index];
        Bucket storage bucket = _buckets[index];

        return bucket.rewardCheckpoint - vault.checkpoint;
    }


    /*
        * @dev Delegated address helper
        * @param from Target address
        * @param index Bucket index value
        * @return Delegate address 
    */
    function delegatedTo(address from, uint8 index) public view returns (address) {
        Delegate storage delegation = _credit[from].delegations[index];

        if (delegation.expiry < block.timestamp) return from;

        return delegation.delegate;
    }


    /*
        * @dev Ticket collateral value helper
        * @return Collateral per unit ticket
    */
    function collateralPerShare() public view returns (uint256) {
        uint256 supply = _ticket.totalSupply();
        uint256 reserves = scale(_reserves, _decimalC, _decimalT);

        if (supply == 0) return _reservePrice;
        
        return (reserves * 1e18) / supply;
    }

    /*
        * @dev Accured interest helper
        * @return Reserve interest premium
    */
    function currentPremium() public view returns (uint256) {
        uint256 interest = _voucher.balanceOf(address(this)) - _opfees;

        if (interest > _reserves) return interest - _reserves;

        return  0;
    }

    /*
        * @dev Epoch phase helper
        * @return Current phase 
    */
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

    /*
        * @dev Credit Repayment time helper
        * @param account User address
        * @param index Bucket index
        * @param amount Loan amount
        * @return Expected repayment time in seconds
    */
    function repaymentTime(address from, uint8 index, uint256 amount) public view returns (uint256) {
        Bucket storage bucket = _buckets[index];
        Stake storage vault = _stakes[from][index];
    
        uint256 alloc = (vault.deposit * 1e18) / bucket.totalDeposits;
        uint256 cycle = (_reserves * _limitApy * CYCLE) / (365 days * 10000);
        uint256 position = (cycleApy * alloc) / 1e18;
    
        uint256 avgPremium = currentPremium() / _slots;
        uint256 userAvgPremium = (avgPremium * alloc) / 1e18;   
        uint256 totalPerCycle = userAvgPremium + position;
    
        if (totalPerCycle == 0) return type(uint256).max;
    
        return (amount * CYCLE) / totalPerCycle;
    }

    /*
        * @dev Oracle state helper
        * @return Oracle state
    */
    function isOracleReady() public view returns (bool) {
        if (!_failsafe) {
            return _lastBlockSync != 0 && _oracle.isRandomized(_lastBlockSync);                                                              
        }

        return true;
    }

    /*   @dev Oracle state sync                                    */
    function sync() public payable onlyCycle(Epoch.Closed) {
        require(_lastBlockSync == 0, "Already synced");

        _oracle.randomize{ value: msg.value }(); 
        _lastBlockSync = block.number;

        emit Sync(block.number, 0);
    }

    /*   @dev Oracle reveal operation                              */
    function roll() public onlyCycle(Epoch.Closed) { 
        require(isOracleReady(), "Oracle not ready");

        bytes32 entropy;
        uint8 bucketId;

        try _oracle.fetchRandomnessAfter(_lastBlockSync) returns (bytes32 result) {
            uint8 index = uint8(uint256(result) % _slots);

            bucketId = index > 9 ? index - 1 : index;
            entropy = result;
        } catch {
            _failsafe = true;
        }

        uint256 premium = currentPremium();
        uint256 coordinatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000;   // 20%
        uint256 prizeShare = premium - coordinatorShare - ticketShare; // 70%

        if (_failsafe) {
            ticketShare += prizeShare;
            prizeShare = 0; 
        } else {
            Bucket storage bucket = _buckets[bucketId];

            bucket.totalRewards += prizeShare;
            bucket.rewardCheckpoint += prizeShare; 
        }

        _opfees += coordinatorShare;
        _reserves += ticketShare;

        emit Roll(block.number, entropy, bucketId, 0);
    }

    /*
        * @dev Mint ticket operation
        * @param amount Issuance value
    */
    function mint(uint256 amount) public onlyCycle(Epoch.Open) syncBlock {
        _collateral.transferFrom(msg.sender, address(this), amount);
        _collateral.approve(address(_pool), amount);      
        _pool.supply(address(_collateral), amount, address(this), 0);

        uint256 tickets = amount * 1e18 / collateralPerShare();

        _reserves += amount;
        _ticket.mint(msg.sender, tickets);

        emit Enter(msg.sender, amount, tickets);
    }

    /*
        * @dev Burn ticket operation
        * @param amount Settlement value
    */
    function burn(uint256 amount) public onlyCycle(Epoch.Pending) syncBlock {
        uint256 allocation = amount * collateralPerShare() / 1e18;
        uint256 collateral = scale(allocation, _decimalT, _decimalC);

        _ticket.burn(msg.sender, amount);

        uint256 deposit = _pool.withdraw(address(_collateral), collateral, address(this));

        _reserves -= deposit;
        _collateral.transferFrom(address(this), msg.sender, deposit);

        emit Exit(msg.sender, deposit, amount);
    }

    /*
        * @dev Redeem rewards operation
        * @param index Bucket index value
    */
    function claim(uint8 index) public onlyCycle(Epoch.Closed) {
        Stake storage vault = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        require(vault.deposit > 0, "Insufficient stake");
        require(_credit[msg.sender].notes[index].debt == 0, "Active debt");  
        require(bucket.rewardCheckpoint > vault.checkpoint, "Already claimed");
        require(delegatedTo(msg.sender, index) == msg.sender, "Active delegation");

        uint256 unclaimed = bucket.rewardCheckpoint - vault.checkpoint;
        uint256 alloc = vault.deposit * 1e18 / bucket.totalDeposits;
        uint256 prize = scale(unclaimed, _decimalC, _decimalT);
        uint256 reward = scale(alloc * prize / 1e18, _decimalT, _decimalC);

        bucket.totalRewards -= reward;
        vault.checkpoint = bucket.rewardCheckpoint;

        uint256 share = _pool.withdraw(address(_collateral), reward, address(this));

        _collateral.transferFrom(address(this), msg.sender, share); 

        emit Claim(msg.sender, index, reward);
    }

    /*
        * @dev Open reward credit position
        * @param from Credit address source
        * @param index Bucket index value
        * @param index Collateral denominated position value    
    */
    function leverage(address from, uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");
        require(credit(msg.sender, index, from) >= amount, "Insufficient credit");

        uint256 position = amount * 10000 / _limitLtv; 
        uint256 earned =  rewards(from, index);
        uint256 collateral = scale(position, _decimalV, _decimalT);

        Credit storage quota = _credit[from];
        Stake storage vault = _stakes[from][index];
        Note storage note = quota.notes[index];

        require(position <= earned, "Insufficient rewards for collateral");
        require(delegatedTo(from, index) == msg.sender, "Not valid delegate");

        _reserves += position;

        uint256 tickets = collateral * 1e18 / collateralPerShare();
 
        note.debt += amount;
        note.principal += amount; 
        note.collateral += tickets;
        note.timestamp = block.timestamp;
        quota.liabilities += amount;
        vault.outstanding += tickets;
        vault.checkpoint -= position;
        vault.deposit += tickets;

        _ticket.mint(address(this), tickets);  
        _pool.withdraw(address(_collateral), amount, msg.sender);

        emit Leverage(from, msg.sender, collateral, amount);
    }

    /*
        * @dev Settle reward credit position
        * @param index Bucket index value
        * @param amount Collateral denominated debit value    
    */
    function repay(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        Stake storage vault = _stakes[msg.sender][index];
        Credit storage quota = _credit[msg.sender];
        Note storage note = quota.notes[index];

        uint256 t = block.timestamp - note.timestamp;
        uint256 earned = rewards(msg.sender, index);
        uint256 interest = note.principal * _limitApy / 1000;
        uint256 premium = interest * t / 10000 / 365 days;

        require(index <= _slots, "Invalid bucket index");

        uint256 recoup = selfRepayment(premium, earned, amount, note, vault);

        note.debt -= recoup;
        quota.liabilities -= recoup;
        note.timestamp = block.timestamp;

        _collateral.transferFrom(msg.sender, address(this), amount);

        if (note.debt == 0) {
            vault.outstanding -= note.collateral;
          
            delete note.collateral;
            delete note.timestamp;
        } 

        emit Repayment(msg.sender, index, recoup);
    } 

    function selfRepayment(
        uint256 interest,
        uint256 premium,
        uint256 amount,
        Note storage note,
        Stake storage vault 
    ) internal returns (uint256) {
        interest += note.interest;

        uint256 recoup = amount + premium;
    
        if (recoup > 0) {
            if (recoup >= interest) {
                note.interest = 0;
                vault.checkpoint -= premium >= interest ? interest : premium;
                _reserves += interest;

                return recoup - interest;
            }
        
            note.interest += interest - recoup;
            vault.checkpoint -= premium;
            _reserves += recoup;
        
            return 0;
        }
    
        note.interest = interest;
    
        return 0;
    }

    function delegate(address to, uint8 index, uint256 duration) public {
        Delegate storage delegation = _credit[msg.sender].delegations[index];
        
        require(delegation.expiry < block.timestamp, "Active delegation");

        delegation.delegate = to;
        delegation.expiry = block.timestamp + duration;
      
        emit Delegation(msg.sender, to, delegation.expiry);
    }

    /*
        * @dev Bucket stake operation
        * @param index Bucket index value
        * @param amount Ticket denominated stake value    
    */
    function stake(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");

        Stake storage vault = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        vault.deposit += amount;
        vault.checkpoint = bucket.rewardCheckpoint;
        bucket.totalDeposits += amount;

        _ticket.transferFrom(msg.sender, address(this), amount);

        emit Lock(msg.sender, index, amount);
    }

    /*
        * @dev Bucket unstake operation
        * @param index Bucket index value
        * @param amount Ticket denominated withdrawal value    
    */
    function unstake(uint8 index, uint256 amount) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");

        Stake storage vault = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        uint256 balance = vault.deposit - vault.outstanding;

        require(balance >= amount, "Insufficient balance");

        vault.deposit -= amount;
        vault.checkpoint = bucket.rewardCheckpoint;
        bucket.totalDeposits -= amount;

        _ticket.transferFrom(address(this), msg.sender, amount);

        emit Unlock(msg.sender, index, amount);
    }

    /*   @dev Coordinator fee distribution                              */
    function funnel(uint256 amount) public {
        require(_opfees > amount, "Not enough fees to funnel");
        
        uint256 fees = _pool.withdraw(address(_collateral), amount, address(this));

        _opfees -= amount;
        _collateral.transferFrom(address(this), _coordinator, fees);

        emit Funnel(fees);
    }

    /*
        * @dev Allocate tax rebate
        * @param account Target rebate address
        * @param amount Ticket denominated rebate value    
    */
    function issueRebate(address account, uint256 amount) public onlyController {
        TaxableERC20(address(_ticket)).rebate(account, amount);
    }

    /*
        * @dev Configure credit apy rate 
        * @param apy Pool annual per year (APY) rate
    */
    function setApy(uint256 apy) public onlyController {
        _limitApy = apy;

        emit Configure(apy);
    }

    /*
        * @dev Configure controller
        * @param controller Target address inheritence  
    */
     function setController(address controller) public onlyController {
        _controller = controller;

        emit Configure(controller);
    }

    /*
        * @dev Configure ticket tax
        * @param rate Percentage tax value (@ 1BPS = 1000)  
    */
    function setTicketTax(uint256 rate) public onlyController {
        TaxableERC20(address(_ticket)).setTax(rate);
    }

    /*
        * @dev Trigger failsafe mode
        * @param toggle State value 
    */
    function setFailsafe(bool toggle) public onlyController {
        _failsafe = toggle;

        emit Failsafe(toggle);
    }

    /*
        * @dev Token decimal rounded interpolation
        * @param amount Target conversion value
        * @param d1 Token 'from' decimals
        * @param d2 Token 'to' decimals
        * @return Token 'to' denominated value
    */
    function scale(uint256 amount, uint8 d1, uint8 d2) internal pure returns (uint256) {
        if (d1 < d2) {
          return amount * (10 ** uint256(d2 - d1));
        } else if (d1 > d2) {
          uint256 f = 10 ** uint256(d1 - d2);

          return (amount + f / 2) / f;
        }
        return amount;
    }

}
