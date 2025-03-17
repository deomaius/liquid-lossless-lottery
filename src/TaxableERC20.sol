pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TaxableERC20 is ERC20 {
    uint256 public _tax;
    uint256 public _rebates;
    address public _controller;

    mapping(address => bool) public _exempt;

    event TaxRateUpdated(uint256 rate);
    event TaxExemptionAdded(address subsidiary);
    event TaxRebate(address benefactor, uint256 amount);

    constructor(string memory name, string memory symbol, address controller, uint256 supply, uint256 rate)
        ERC20(name, symbol)
    {
        require(_tax < 10000, "Invalid tax bps format");

        _tax = rate;
        _controller = controller;

        _exempt[controller] = true;
        _exempt[address(0)] = true;

        _mint(msg.sender, supply);
    }

    modifier onlyController() {
        require(msg.sender == _controller, "Invalid controller");
        _;
    }

    function tax(address from, address to, uint256 amount) public returns (uint256) {
        bool taxable = !_exempt[to] && !_exempt[from];

        return taxable ? (amount * _tax) / 10000 : 0;
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

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        uint256 tax = tax(msg.sender, to, amount);

        if (tax > 0) _deductTax(msg.sender, tax);

        super._transfer(msg.sender, to, amount - tax);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        uint256 tax = tax(from, to, amount);

        super._spendAllowance(from, _msgSender(), amount - tax);
        super._transfer(from, to, amount - tax);

        if (tax > 0) _deductTax(from, tax);

        return true;
    }

    function setTax(uint256 rate) external onlyController {
        require(_tax < 10000, "Invalid tax bps format");

        _tax = rate;

        emit TaxRateUpdated(rate);
    }

    function setTaxExemption(address account) external onlyController {
        _exempt[account] = true;

        emit TaxExemptionAdded(account);
    }

    function _deductTax(address from, uint256 amount) internal {
        _rebates += amount;

        super._burn(from, amount);
    }
}
