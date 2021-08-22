// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

// Contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract IvOracle is Ownable {
  /*==== PUBLIC VARS ====*/

  uint256 public lastIv;

  /*==== SETTER FUNCTIONS (ONLY OWNER) ====*/

  /**
   * @notice Updates the last iv for DPX
   * @param iv iv
   * @return iv of dpx
   */
  function updateIv(uint256 iv) external onlyOwner returns (uint256) {
    require(iv != 0, "last iv cannot be 0");

    lastIv = iv;

    return iv;
  }

  /*==== VIEWS ====*/

  /**
   * @notice Gets the iv of dpx
   * @return iv
   */
  function getIv() external view returns (uint256 iv) {
    require(lastIv != 0, "Oracle: last iv == 0");

    return lastIv;
  }
}
