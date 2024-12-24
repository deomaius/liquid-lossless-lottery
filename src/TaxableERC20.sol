pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TaxableERC20 is ERC20 {
    
    uint256 public _tax;
    uint256 public _rebates;
    address public _controller;

    mapping (address => bool) public _exempt;

    event TaxRateUpdated(uint256 rate);
    event TaxExemptionAdded(address subsidiary);
    event TaxRebate(address benefactor, uint256 amount);

    constructor(
        uint256 taxRate,
        string memory name, 
        string memory symbol, 
        uint256 initialSupply
    ) 
        ERC20(name, symbol) 
    {
        _tax = taxRate;
        _controller = msg.sender;

        _exempt[msg.sender] = true;
        _exempt[address(0)] = true;
        
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

    function rebate(address to, uint256 amount) public onlyController {
        require(to != address(0), "Cannot rebate to zero address");
        require(amount > 0, "Rebate amount must be greater than zero");
        require(_rebates >= amount, "Insufficient taxes");

        _rebates -= amount;
        _mint(to, amount);

        emit TaxRebate(to, amount);
    }

    function transfer(address to,  uint256 amount) virtual override public returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) virtual override public returns (bool) {
        uint256 tax = (amount * _tax) / 1e18;

        super._spendAllowance(from, _msgSender(), amount);
        super._transfer(from, to, amount - tax);

        bool context = to != _controller && from != _controller;
        bool taxable = !_exempt[from] && context && tax > 0;

        if (taxable) {
          _rebates += tax;

          super._burn(from, tax);
        }

        return true;
    }

    function setTax(uint256 rate) external onlyController {
        _tax = rate;

        emit TaxRateUpdated(rate);
    }

    function setTaxExemption(address account) external onlyController {
        _exempt[account] = true;

        emit TaxExemptionAdded(account);
    }

}


