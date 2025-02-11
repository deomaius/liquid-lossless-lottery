pragma solidity 0.8.20;

import "@root/LiquidLottery.sol";

contract MockLottery is LiquidLottery {

    constructor(
        address pool,               // @param Aave pool provider address
        address oracle,             // @param Witnet oracle address
        address provider,           // @param Aave data provider address
        address controller,         // @param Lottery controller address
        address collateral,         // @param Lottery collateral token address 
        address coordinator,        // @param Lottery coordinator address
        string memory name,         // @param Lottery ticket name
        string memory symbol,       // @param Lottery ticket symbol 
        uint256 ticketBasePrice,    // @param Lottery ticket base conversion rate
        uint256 ticketBaseTax,      // @param Lottery ticket tax rate
        uint256 ltvMultiplier,      // @param Lottery loan-to-value (LTV) multiplier
        uint256 limitingApy,        // @param Lottery annual per year (APY) rate
        uint8 bucketSlots           // @param Lottery bucket count
    )
        LiquidLottery(
            pool,
            oracle,
            provider,
            controller,
            collateral,
            coordinator,
            name,
            symbol,
            ticketBasePrice,
            ticketBaseTax,
            ltvMultiplier,
            limitingApy,
            bucketSlots
        )
    {}

    function draw(bytes32 result) public onlyCycle(Epoch.Closed) {  
        uint8 index = uint8(uint256(result) % _slots);

        uint8 bucketId = index > _slots ? _slots : index;

        uint256 premium = currentPremium();
        uint256 coordinatorShare = (premium * 1000) / 10000; // 10%
        uint256 ticketShare = (premium * 2000) / 10000;   // 20%
        uint256 prizeShare = premium - coordinatorShare - ticketShare; // 70%

        if (_failsafe) {
            ticketShare += prizeShare;
            prizeShare = 0; 
        } else {
            Bucket storage bucket = _buckets[bucketId];

            uint256 rate = prizeShare * 1e18 / bucket.totalDeposits;

            bucket.rewardCheckpoint += rate;
        }

        _opfees += coordinatorShare;
        _reserves += ticketShare;

        emit Roll(block.number, result, bucketId, prizeShare);
    }

}
