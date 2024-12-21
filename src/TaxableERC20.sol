pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TaxableERC20 is ERC20 {
    
    address public _collector;
    address public _controller;

    uint256 public _transferTax;

    event TaxRateUpdated(uint256 newTaxRate);
    event TaxCollectorUpdated(address newCollector);

    modifier onlyController() {
      require(msg.sender == _controller, "Invalid controller");
      _;
    }

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

    function mint(address to, uint256 amount) public onlyController {
        super._mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyController {
        super._burn(from, amount);
    }

    function _transfer(
        address sender, 
        address recipient, 
        uint256 amount
    ) internal virtual override {
        uint256 taxAmount = (amount * _transferTax) / 10000;
        uint256 transferAmount = amount - taxAmount;

        super._transfer(sender, recipient, transferAmount);
        
        if (taxAmount > 0) {
            super._transfer(sender, _collector, taxAmount);
        }
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


