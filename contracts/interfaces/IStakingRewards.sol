//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingRewards {
  function stake(uint256 amount) external payable;

  function withdraw(uint256 amount) external;

  function compound() external;

  function rewardsDPX(address user) external returns (uint256);

  function balanceOf(address user) external returns (uint256);

  function getReward(uint256 id) external;
}
