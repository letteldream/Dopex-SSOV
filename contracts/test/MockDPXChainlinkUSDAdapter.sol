// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IOracle.sol";

contract MockDPXChainlinkUSDAdapter is IOracle {
    function getPriceInUSD() external pure override returns (uint256 price) {
        return 100e8; // 100$
    }

    function viewPriceInUSD() external pure override returns (uint256 price) {
        return 100e8; // 100$
    }
}
