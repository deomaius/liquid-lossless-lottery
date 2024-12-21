pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TaxableERC20 is ERC20 {
    
    address public _collector;
    address public _controller;

    uint256 public _transferTax;

    event TaxRateUpdated(uint256 newTaxRate);
    event TaxCollectorUpdated(address newCollector);

    constructor(
        uint256 taxRate,
        string memory name, 
        string memory symbol, 
        uint256 initialSupply
    ) 
        ERC20(name, symbol) 
    {
        _transferTax = taxRate;
        _controller = msg.sender;

        _mint(msg.sender, initialSupply);
    }

    modifier onlyController() {
        require(msg.sender == _controller, "Invalid controller");
        _;
    }

    function mint(address to, uint256 amount) public onlyController {
        super._mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyController {
        super._burn(from, amount);
    }

    function transfer(address to,  uint256 amount) virtual override public returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) virtual override public returns (bool) {
        uint256 tax = (amount * _transferTax) / 1e18;

        super._spendAllowance(from, _msgSender(), amount);
        super._transfer(from, to, amount - tax);

        if (tax > 0) super._transfer(from, _collector, tax);

        return true;
    }

    function setTax(uint256 newTaxRate) external onlyController {
        _transferTax = newTaxRate;

        emit TaxRateUpdated(newTaxRate);
    }

    function setCollector(address collector) external onlyController {
        _collector = collector;

        emit TaxCollectorUpdated(collector);
    }

}


