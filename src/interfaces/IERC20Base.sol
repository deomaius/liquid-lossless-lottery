pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IERC20Base is IERC20, IERC20Metadata {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}
