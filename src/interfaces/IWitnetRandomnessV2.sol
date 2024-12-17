pragma solidity 0.8.19;

interface IWitnetRandomnessV2 {

  function estimateRandomizeFee(uint256 _evmGasPrice) external view returns (uint256);

  function fetchRandomnessAfter(uint256 _blockNumber) external view returns (bytes32);

  function isRandomized(uint256 _blockNumber) external view returns (bool);
  
  function randomize() external payable returns (uint256 _evmRandomizeFee);

  function baseFeeOverheadPercentage() external view returns (uint16);

}
