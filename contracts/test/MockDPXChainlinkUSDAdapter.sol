// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

import {IOracle} from '../interfaces/IOracle.sol';

contract MockDPXChainlinkUSDAdapter is IOracle, Ownable {
    uint256 public price = 100e8;

    function updatePrice(uint256 _price) external onlyOwner returns (bool) {
        price = _price;
        return true;
    }

    function getPriceInUSD() external view override returns (uint256) {
        return price;
    }

    function viewPriceInUSD() external view override returns (uint256) {
        return price;
    }
}
