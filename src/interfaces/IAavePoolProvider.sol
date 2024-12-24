pragma solidity ^0.8.20;

interface IAavePoolProvider {

    function getPool() external view returns (address);

}
