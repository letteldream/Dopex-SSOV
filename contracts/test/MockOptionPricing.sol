// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IOptionPricing } from "../interfaces/IOptionPricing.sol";

contract MockOptionPricing is IOptionPricing {
  function getOptionPrice(
    bool isPut,
    uint256 expiry,
    uint256 strike,
    uint256 lastPrice,
    uint256 baseIv
  ) external pure override returns (uint256) {
    return 5e8; // 5$
  }
}
