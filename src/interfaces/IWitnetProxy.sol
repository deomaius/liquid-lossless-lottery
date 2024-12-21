pragma solidity ^0.8.20;

interface IWitnetProxy {

  function estimateBaseFee(uint256 _gasPrice, uint16 _resultMaxSize) external returns (uint256);

  function estimateBaseFeeWithCallback(uint256 _gasPrice, uint24 _callbackGasLimit) external returns (uint256);

}
