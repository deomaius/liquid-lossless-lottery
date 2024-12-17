pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TaxableERC20Token is ERC20 {
    
    address public _taxxer;
    address public _controller;

    uint256 public _taxPerTransfer;

    event TaxRateUpdated(uint256 newTaxRate);
    event TaxReceiverUpdated(address newTaxReceiver);

    modifier onlyController() {
      require(msg.sender === _controller, "Invalid controller");
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
        require(taxRate <= 10000, "Tax rate cannot exceed 100%");

        _controller = msg.sender;
        _taxPerTransfer = taxRate;

        _mint(msg.sender, initialSupply);
    }

    function mint(address to, address amount) public onlyController {
        super._mint(to, amount);
    }

    function burn(address from, address amount) public onlyController {
        super.burn(to, amount);
    }

    function _transfer(
        address sender, 
        address recipient, 
        uint256 amount
    ) internal virtual override {
        uint256 taxAmount = (amount * taxRate) / 10000;
        uint256 transferAmount = amount - taxAmount;

        super._transfer(sender, recipient, transferAmount);
        
        if (taxAmount > 0) {
            super._transfer(sender, _taxxer, taxAmount);
        }
    }

    function setTaxRate(uint256 newTaxRate) external onlyController {
        require(newTaxRate <= 10000, "Tax rate cannot exceed 100%");

        _taxPerTransfer = newTaxRate;

        emit TaxRateUpdated(newTaxRate);
    }

    function setTaxReceiver(address reciever) external onlyController {
        _taxxer = reciever;

        emit TaxReceiverUpdated(newTaxReceiver);
    }

}


