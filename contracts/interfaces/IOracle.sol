// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IOracle {
  event PriceUpdated(address asset, uint256 newPrice);

  function getPriceInUSD() external returns (uint256);

  function viewPriceInUSD() external view returns (uint256);
}
