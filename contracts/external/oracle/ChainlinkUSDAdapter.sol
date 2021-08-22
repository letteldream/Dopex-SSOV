// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/IOracle.sol";
import "../../interfaces/IChainlinkV3Aggregator.sol";

contract ChainlinkUSDAdapter is IOracle {
  /// @notice the asset with the price oracle
  address public immutable asset;

  /// @notice chainlink aggregator with price in USD
  IChainlinkV3Aggregator public immutable aggregator;

  /// @dev the latestAnser returned
  uint256 private latestAnswer;

  constructor(address _asset, address _aggregator) {
    require(address(_aggregator) != address(0), "invalid aggregator");

    asset = _asset;
    aggregator = IChainlinkV3Aggregator(_aggregator);
  }

  function adjustDecimal(
    uint256 balance,
    uint8 org,
    uint8 target
  ) internal pure returns (uint256 adjustedBalance) {
    adjustedBalance = balance;
    if (target < org) {
      adjustedBalance = adjustedBalance / (10**(org - target));
    } else if (target > org) {
      adjustedBalance = adjustedBalance * (10**(target - org));
    }
  }

  /// @dev returns price of asset in 1e8
  function getPriceInUSD() external override returns (uint256 price) {
    (, int256 priceC, , , ) = aggregator.latestRoundData();
    price = adjustDecimal(uint256(priceC), aggregator.decimals(), 8);
    latestAnswer = price;
    emit PriceUpdated(asset, price);
  }

  /// @dev returns the latest price of asset
  function viewPriceInUSD() external view override returns (uint256) {
    return latestAnswer;
  }
}
