//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IOptionPricing {

  function getOptionPrice(
    bool isPut,
    uint256 expiry,
    uint256 strike
  ) external view returns (uint256);

}