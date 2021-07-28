import { Contract } from "ethers";

import { PriceOracleAggregator } from "../types/PriceOracleAggregator";
import { ChainlinkUSDAdapter } from "../types/ChainlinkUSDAdapter";
import { UniswapV2Oracle } from "../types/UniswapV2Oracle";
import { MockDPXChainlinkUSDAdapter } from "../types/MockDPXChainlinkUSDAdapter";
import { MockOptionPricing } from "../types/MockOptionPricing";
import { Vault} from "../types/Vault";

const hre = require("hardhat");

export const deployContract = async <ContractType extends Contract>(
  contractName: string,
  args: any[],
  libraries?: {}
) => {
  const signers = await hre.ethers.getSigners();
  const contract = (await (
    await hre.ethers.getContractFactory(contractName, signers[0], {
      libraries: {
        ...libraries,
      },
    })
  ).deploy(...args)) as ContractType;

  return contract;
};

export const deployPriceOracleAggregator = async (owner: string) => {
  return await deployContract<PriceOracleAggregator>("PriceOracleAggregator", [
    owner,
  ]);
};

export const deployChainlinkUSDAdapter = async (
  asset: string,
  aggregator: string
) => {
  return await deployContract<ChainlinkUSDAdapter>("ChainlinkUSDAdapter", [
    asset,
    aggregator,
  ]);
};

export const deployUniswapV2Oracle = async (
    factory: string,
    tokenA: string,
    tokenB: string,
    aggregator: string
) => {
  return await deployContract<UniswapV2Oracle>("UniswapV2Oracle", [
    factory,
    tokenA,
    tokenB,
    aggregator,
  ]);
}

export const deployMockDPXChainlinkUSDAdapter = async () => {
  return await deployContract<MockDPXChainlinkUSDAdapter>(
    "MockDPXChainlinkUSDAdapter",
    []
  );
};

export const deployMockOptionPricing = async () => {
  return await deployContract<MockOptionPricing>(
    "MockOptionPricing",
    []
  );
};

export const deployVault = async (
    dpx: string,
    rdpx: string,
    stakingRewards: string,
    optionPricing: string,
    priceOracleAggregator: string
) => {
  return await deployContract<Vault>("Vault", [
    dpx,
    rdpx,
    stakingRewards,
    optionPricing,
    priceOracleAggregator
  ]);
}