pragma solidity ^0.8.20;

import {IVRFCoordinatorV2} from "@interfaces/IVRFCoordinatorV2.sol";
import {IAavePoolProvider} from "@interfaces/IAavePoolProvider.sol";
import {IAaveDataProvider} from "@interfaces/IAaveDataProvider.sol";
import {IAaveLendingPool} from "@interfaces/IAaveLendingPool.sol";
import {ILiquidLottery} from "@interfaces/ILiquidLottery.sol";
import {IERC20Base} from "@interfaces/IERC20Base.sol";

import {TaxableERC20} from "./TaxableERC20.sol";

/*
    * @author deomaius
    * @title Liquid Lossless Lottery
    * @description An egalitarian prize-savings pool with a liquid ticket system 
*/

contract LiquidLottery is ILiquidLottery {
    bool public _failsafe;

    uint8 public _slots;
    uint8 public _decimalV;
    uint8 public _decimalC;
    uint8 public _decimalT;
    address public _controller;

    uint256 public immutable _start;
    uint256 public immutable _limitLtv;
    uint256 public immutable _reservePrice;
    uint256 public _opfees;
    uint256 public _limitApy;
    uint256 public _reserves;
    uint256 public _lastReqId;
    uint256 public _lastBlockSync;

    address public immutable _coordinator;

    IERC20Base public immutable _ticket;
    IERC20Base public immutable _voucher;
    IERC20Base public immutable _collateral;
    IAaveLendingPool public immutable _pool;
    IVRFCoordinatorV2 public immutable _oracle;

    mapping(uint8 => Bucket) public _buckets;
    mapping(address => Credit) public _credit;
    mapping(uint256 => bool) public _requests;
    mapping(address => mapping(uint256 => Stake)) public _stakes;

    // Chainlink VRF V2 parameters
    bytes32 public immutable _keyHash;
    uint64 public immutable _subscriptionId;

    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 200000;
    uint32 public constant NUM_WORDS = 1;
    uint256 public constant VRF_TIMEOUT = 6 hours;

    uint256 public constant OPEN_EPOCH = 4 days;
    uint256 public constant CLOSED_EPOCH = 12 hours;
    uint256 public constant PENDING_EPOCH = 2 days + 12 hours;
    uint256 public constant CYCLE = OPEN_EPOCH + PENDING_EPOCH + CLOSED_EPOCH;

    constructor(
        address[6] memory addresses, // @param Lottery addresses
            // @addresses[0] Aave pool provider address
            // @addresses[1] Chainlink VRF oracle address
            // @addresses[2] Aave data provider address
            // @addresses[3] Lottery controller address
            // @addresses[4] Lottery collateral token address
            // @addresses[5] Lottery coordinator address
        string memory name, // @param Lottery ticket name
        string memory symbol, // @param Lottery ticket symbol
        uint256 ticketBasePrice, // @param Lottery ticket base conversion rate
        uint256 ticketBaseTax, // @param Lottery ticket tax rate
        uint256 limitingLtv, // @param Lottery loan-to-value (LTV) multiplier
        uint256 limitingApy, // @param Lottery annual per year (APY) rate
        uint8 bucketSlots, // @param Lottery bucket count
        bytes32 keyHash, // @param Chainlink VRF key hash
        uint64 subscriptionId // @param Chainlink VRF subscription ID
    ) {
        require(limitingLtv < 1e18, "Invalid ltv format");
        require(limitingApy < 10000, "Invalid apy bps format");

        _slots = bucketSlots;
        _start = block.timestamp;
        _controller = addresses[3]; // Controller
        _coordinator = addresses[5]; // Coordinator
        _reservePrice = ticketBasePrice;
        _limitLtv = limitingLtv;
        _limitApy = limitingApy;
        _keyHash = keyHash;
        _subscriptionId = subscriptionId;

        _collateral = IERC20Base(addresses[4]); // Collateral token
        _oracle = IVRFCoordinatorV2(addresses[1]); // VRF coordinator 
        _pool = IAaveLendingPool(IAavePoolProvider(addresses[0]).getPool()); // Pool provider
        _ticket = IERC20Base(address(new TaxableERC20(name, symbol, address(this), 0, ticketBaseTax)));

        (address voucher,,) = IAaveDataProvider(addresses[2]).getReserveTokensAddresses(addresses[4]); // Data provider, collateral

        _voucher = IERC20Base(voucher);
        _decimalC = _collateral.decimals();
        _decimalV = _voucher.decimals();
        _decimalT = 18;
    }

    /*    @dev Control statement for configuration        */
    modifier onlyController() {
        require(msg.sender == _controller, "Invalid controller");
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
        delete _lastBlockSync;
        delete _lastReqId;
        _;
    }

    /*
        * @dev Outstanding debt helper
        * @param account Target address
        * @return Collateral denominated debt
    */
    function debt(address account, uint8 index) public view returns (uint256) {
        uint256 premium = interestDue(account, index);
        uint256 principal = _credit[account].notes[index].debt;

        return principal + premium;
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

        if (account != delegator && delegatedTo(delegator, index) == account) {
            base += rewards(delegator, index);
        }

        return base * _limitLtv / 1e18;
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

        if (bucket.rewardCheckpoint < vault.checkpoint) return 0;

        uint256 rate = bucket.rewardCheckpoint - vault.checkpoint;

        return rate * scale(vault.deposit, _decimalT, _decimalC) / 1e18;
    }

    /*
        * @dev Outstanding interest helper
        * @param account Target address
        * @return Collateral denominated interest 
    */
    function interestDue(address account, uint8 index) public view returns (uint256) {
        Note storage note = _credit[account].notes[index];

        uint256 t = block.timestamp - note.timestamp;
        uint256 premium = note.principal * _limitApy / 10000;

        return note.interest + premium * t / 365 days;
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

        uint256 rate = (reserves * 1e18) / supply;

        return scale(rate, _decimalT, _decimalC);
    }

    /*
        * @dev Accured interest helper
        * @return Reserve interest premium
    */
    function currentPremium() public view returns (uint256) {
        uint256 balance = _voucher.balanceOf(address(this));
        uint256 interest = balance - _opfees;

        if (interest > _reserves) return interest - _reserves;

        return 0;
    }

    /*
        * @dev Epoch phase helper
        * @return Current phase 
    */
    function currentEpoch() public view returns (Epoch) {
        uint256 elapsedTime = block.timestamp - _start;
        uint256 timeInCycle = elapsedTime % CYCLE;

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
    function timeToRepay(address from, uint8 index, uint256 amount) public view returns (uint256) {
        Bucket storage bucket = _buckets[index];
        Stake storage vault = _stakes[from][index];

        uint256 alloc = (vault.deposit * 1e18) / bucket.totalDeposits;
        uint256 cycle = (_reserves * _limitApy * CYCLE) / (365 days * 10000);
        uint256 position = cycle * alloc / 1e18;

        uint256 premiumPerSlot = currentPremium() / _slots;
        uint256 avgPremium = premiumPerSlot * alloc / 1e18;
        uint256 totalPerCycle = avgPremium + position;

        if (totalPerCycle == 0) return type(uint256).max;

        return (amount * CYCLE) / totalPerCycle;
    }

    /*
        * @dev Oracle state helper
        * @return Oracle state
    */
      function oracleStatus() public view returns (bool success, bool timedOut) {
        uint256 timeElapsed = block.timestamp - _lastBlockSync;

        success = _lastReqId == 0 && _lastBlockSync != 0;
        timedOut = _lastReqId != 0 && timeElapsed > VRF_TIMEOUT;
    }

   /*   @dev Request randomness from Chainlink VRF                    */
    function sync() public onlyCycle(Epoch.Closed) {
        require(_lastReqId == 0, "Already synced");
        require(_lastBlockSync == 0, "Already synced");

        uint256 requestId = _oracle.requestRandomWords(
            _keyHash,
            _subscriptionId,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        _lastReqId = requestId;
        _lastBlockSync = block.timestamp;

        emit Sync(block.number, requestId);
    }

    /*   @dev Oracle reveal operation                              */
    function draw(uint8 index, bytes32 result) public onlyCycle(Epoch.Closed) {
        (bool success, bool timedOut) = oracleStatus();
        bool shouldFallback = timedOut || _failsafe;

        require(success || shouldFallback, "Request has not been synced"); 

        uint256 premium = currentPremium();
        uint256 coordinatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000; // 20%
        uint256 prizeShare = premium - coordinatorShare - ticketShare; // 70%
        uint8 bucketId  = index > _slots ? _slots : index;

        if (shouldFallback) {
            ticketShare += prizeShare;
            prizeShare = 0;

            _lastReqId = 0;
        } else {
            Bucket storage bucket = _buckets[bucketId];

            uint256 prize = scale(prizeShare, _decimalC, _decimalT);
            uint256 rate = prize * 1e18 / bucket.totalDeposits;

            bucket.rewardCheckpoint += rate;
        }

        _opfees += coordinatorShare;
        _reserves += ticketShare;

        emit Roll(block.number, result, bucketId, prizeShare);
    }

    /* ---------------DO NOT USE IN  PRODUCTION ---------------- */
    function draw(uint256 index, bytes32 result) public onlyCycle(Epoch.Closed) {
        (bool success, bool timedOut) = oracleStatus();
        bool shouldFallback = timedOut || _failsafe;

        require(success || shouldFallback, "Request has not been synced"); 

        uint256 premium = currentPremium();
        uint256 coordinatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000; // 20%
        uint256 prizeShare = premium - coordinatorShare - ticketShare; // 70%

        uint8 bucketId = index > _slots ? _slots : uint8(index);

        if (shouldFallback) {
            ticketShare += prizeShare;
            prizeShare = 0; 

            _lastReqId = 0;
        } else {
            Bucket storage bucket = _buckets[bucketId];

            uint256 prize = scale(prizeShare, _decimalC, _decimalT);
            uint256 rate = prize * 1e18 / bucket.totalDeposits;

            bucket.rewardCheckpoint += rate;
        }

        _opfees += coordinatorShare;
        _reserves += ticketShare;

        emit Roll(block.number, result, bucketId, prizeShare);
    }
    /* --------------------MOCK FUNCTION ------------------------- */

    /*
        * @dev Mint ticket operation
        * @param amount Issuance value
    */
    function mint(uint256 amount) public onlyCycle(Epoch.Open) syncBlock {
        _collateral.transferFrom(msg.sender, address(this), amount);
        _collateral.approve(address(_pool), amount);
        _pool.supply(address(_collateral), amount, address(this), 0);

        uint256 collateral = scale(amount, _decimalC, _decimalT);
        uint256 rate = scale(collateralPerShare(), _decimalC, _decimalT);
        uint256 tickets = collateral * 1e18 / rate;

        _reserves += amount;
        _ticket.mint(msg.sender, tickets);

        emit Enter(msg.sender, amount, tickets);
    }

    /*
        * @dev Burn ticket operation
        * @param amount Settlement value
    */
    function burn(uint256 amount) public onlyCycle(Epoch.Pending) syncBlock {
        uint256 rate = scale(collateralPerShare(), _decimalC, _decimalT);
        uint256 allocation = scale(amount * rate / 1e18, _decimalT, _decimalC);

        _ticket.burn(msg.sender, amount);

        uint256 deposit = _pool.withdraw(address(_collateral), allocation, address(this));

        _reserves -= deposit;
        _collateral.transfer(msg.sender, deposit);

        emit Exit(msg.sender, deposit, amount);
    }

    /*
        * @dev Redeem rewards operation
        * @param amount Claim proportion value
        * @param index Bucket index value
    */
    function claim(uint256 amount, uint8 index) public notCycle(Epoch.Closed) {
        Stake storage vault = _stakes[msg.sender][index];

        uint256 rewards = rewards(msg.sender, index);
        uint256 withdrawal = scale(amount, _decimalC, _decimalT);

        require(vault.deposit > 0, "Insufficient stake");
        require(debt(msg.sender, index) == 0, "Active debt");
        require(rewards >= amount && rewards > 0, "Insufficient rewards");
        require(delegatedTo(msg.sender, index) == msg.sender, "Active delegation");

        _moveCheckpoint(vault, index, withdrawal, rewards);

        uint256 share = _pool.withdraw(address(_collateral), amount, address(this));

        _collateral.transfer(msg.sender, share);

        emit Claim(msg.sender, index, amount);
    }

    /*
        * @dev Open reward credit position
        * @param from Credit address source
        * @param index Bucket index value
        * @param index Collateral denominated position value    
    */
    function leverage(address from, uint256 amount, uint8 index) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");

        uint256 earned = rewards(from, index);

        Credit storage quota = _credit[from];
        Stake storage vault = _stakes[from][index];
        Note storage note = quota.notes[index];

        require(amount <= earned, "Insufficient rewards for collateral");
        require(delegatedTo(from, index) == msg.sender, "Not valid delegate");
        require(credit(msg.sender, index, from) >= amount, "Insufficient credit");

        uint256 collateral = scale(amount, _decimalC, _decimalT) * 1e18 / _limitLtv;
        uint256 position = scale(collateral, _decimalT, _decimalC);

        _reserves += position;

        uint256 tickets = position * 1e18 / collateralPerShare();

        note.debt += amount;
        note.principal += amount;
        note.collateral += tickets;
        note.timestamp = block.timestamp;
        quota.liabilities += amount;
        vault.outstanding += tickets;
        vault.deposit += tickets;

        _moveCheckpoint(vault, index, collateral, earned);
        _pool.withdraw(address(_collateral), amount, msg.sender);
        _ticket.mint(address(this), tickets);

        emit Leverage(from, msg.sender, collateral, amount);
    }

    /*
        * @dev Settle reward credit position
        * @param index Bucket index value
        * @param amount Collateral denominated debit value    
    */
    function repay(uint256 amount, uint8 index) public notCycle(Epoch.Closed) {
        Stake storage vault = _stakes[msg.sender][index];
        Credit storage quota = _credit[msg.sender];
        Note storage note = quota.notes[index];

        uint256 earned = rewards(msg.sender, index);
        uint256 premium = interestDue(msg.sender, index);

        require(index <= _slots, "Invalid bucket index");

        uint256 expense = scale(amount + earned, _decimalC, _decimalT);
        uint256 recoup = selfRepayment(premium, earned, amount, note, vault);

        note.debt -= recoup;
        quota.liabilities -= recoup;
        note.timestamp = block.timestamp;

        _moveCheckpoint(vault, index, expense, earned);
        _collateral.transferFrom(msg.sender, address(this), amount);

        if (note.debt == 0) {
            vault.outstanding -= note.collateral;

            delete note.collateral;
            delete note.timestamp;
        }

        emit Repayment(msg.sender, index, recoup);
    }

    /*
        * @dev Internal interest repayment handler
        * @param interest Interest accrued for period
        * @param premium Current reward premium
        * @param amount Repayment value
        * @param note Credit position note
        * @param vault Stake position vault
        * @return Excess repayment for principal
    */
    function selfRepayment(uint256 interest, uint256 premium, uint256 amount, Note storage note, Stake storage vault)
        internal
        returns (uint256)
    {
        interest += note.interest;
        uint256 recoup = amount + premium;

        if (recoup > 0) {
            if (recoup >= interest) {
                note.interest = 0;
                _reserves += interest;

                return recoup - interest;
            }

            note.interest += interest - recoup;
            _reserves += recoup;

            return 0;
        }

        note.interest = interest;

        return 0;
    }

    /*
        * @dev Credit delegation handler
        * @param to Target delegate address
        * @param index Bucket index value
        * @param duration Delegation timelock period
    */
    function delegate(address to, uint8 index, uint256 duration) public {
        Delegate storage delegation = _credit[msg.sender].delegations[index];

        require(delegation.expiry < block.timestamp, "Active delegation");

        delegation.delegate = to;
        delegation.expiry = block.timestamp + duration;

        emit Delegation(msg.sender, to, delegation.expiry);
    }

    /*
        * @dev Bucket stake operation
        * @param amount Ticket denominated stake value
        * @param index Bucket index value
    */
    function stake(uint256 amount, uint8 index) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");
        require(rewards(msg.sender, index) == 0, "Outstanding rewards");

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
    function unstake(uint256 amount, uint8 index) public notCycle(Epoch.Closed) {
        require(index <= _slots, "Invalid bucket index");
        require(rewards(msg.sender, index) == 0, "Outstanding rewards");

        Stake storage vault = _stakes[msg.sender][index];
        Bucket storage bucket = _buckets[index];

        uint256 balance = vault.deposit - vault.outstanding;

        require(balance >= amount, "Insufficient balance");

        vault.deposit -= amount;
        vault.checkpoint = bucket.rewardCheckpoint;
        bucket.totalDeposits -= amount;

        _ticket.transfer(msg.sender, amount);

        emit Unlock(msg.sender, index, amount);
    }

    /*   @dev Coordinator fee distribution                              */
    function funnel(uint256 amount) public {
        require(_opfees > amount, "Not enough fees to funnel");

        uint256 fees = _pool.withdraw(address(_collateral), amount, address(this));

        _opfees -= amount;
        _collateral.transfer(_coordinator, fees);

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
        require(apy < 10000, "Invalid apy bps format");

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

    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        require(msg.sender == address(_oracle), "Only VRF Coordinator can fulfill");
        require(requestId == _lastReqId, "Invalid request ID");
        require(!_requests[requestId], "Request already fulfilled");

        uint8 bucketId = uint8(randomWords[0] % _slots);

        _requests[requestId] = true;
        _lastReqId = 0;

        draw(bucketId, bytes32(randomWords[0]));
    }

    /*
        * @dev Checkpoint state handler
        * @param vault Checkpoint address deposit
        * @param index Bucket index value
        * @param amount Reward value amount scaled 
        * @param rewards Rewards value unscaled
    */
    function _moveCheckpoint(Stake storage vault, uint8 index, uint256 amount, uint256 rewards) internal {
        Bucket storage bucket = _buckets[index];

        rewards = scale(rewards, _decimalC, _decimalT);

        uint256 deltaRate = bucket.rewardCheckpoint - vault.checkpoint;
        uint256 proportion = amount * 1e18 / rewards;

        vault.checkpoint += deltaRate * proportion / 1e18;
    }

    /*
        * @dev Token decimal rounded interpolation
        * @param amount Target conversion value
        * @param d1 Token 'from' decimals
        * @param d2 Token 'to' decimals
        * @return Token 'to' denominated value
    */
    function scale(uint256 amount, uint8 d1, uint8 d2) public view returns (uint256) {
        if (d1 < d2) {
            return amount * (10 ** uint256(d2 - d1));
        } else if (d1 > d2) {
            uint256 f = 10 ** uint256(d1 - d2);

            return amount / f;
        }
        return amount;
    }

}
