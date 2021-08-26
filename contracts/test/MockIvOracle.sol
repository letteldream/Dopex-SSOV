// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockIvOracle {
  /**
   * @notice Gets the iv of dpx
   * @return iv
   */
  function getIv() public pure returns (uint256) {
    return 100;
  }
}
