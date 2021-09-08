import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { BigNumber } from 'ethers';

import { chainIdToNetwork, dpx, rdpx, stakingRewards } from '../helper/data';

const deploy = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre;
  const { deployer } = await getNamedAccounts();
  const chainId = parseInt(await getChainId());
  const network = chainIdToNetwork[chainId];
  const dpxAddress = dpx[chainId];
  const rdpxAddress = rdpx[chainId];
  const stakingRewardsAddress = stakingRewards[chainId];

  if (!network || !dpxAddress || !rdpxAddress || !stakingRewardsAddress) return;

  // Deploy MockDPXChainlinkUSDAdapter
  const mockDPXChainlinkUSDAdapter = await deployments.deploy(
    'MockDPXChainlinkUSDAdapter',
    {
      from: deployer,
      args: [],
      log: true,
    }
  );

  // Deploy PriceOracleAggregator
  const { address } = await deployments.deploy('PriceOracleAggregator', {
    from: deployer,
    args: [deployer],
    log: true,
  });

  const priceOracleAggregator = await ethers.getContractAt(
    'PriceOracleAggregator',
    address
  );

  await priceOracleAggregator.updateOracleForAsset(
    dpxAddress,
    mockDPXChainlinkUSDAdapter.address
  );

  // Deploy OptionPricing
  const optionPricing = await deployments.deploy('OptionPricing', {
    from: deployer,
    args: [
      BigNumber.from(500).toString(),
      BigNumber.from(10).pow(8).toString(),
      BigNumber.from(10).pow(8).toString(),
      BigNumber.from(9).pow(8).div(1000).toString(),
      BigNumber.from(9).pow(8).div(1000).toString(),
    ],
    log: true,
  });

  // Deploy IvOracle
  const ivOracle = await deployments.deploy('IvOracle', {
    from: deployer,
    args: [],
    log: true,
  });

  // Deploy Vault
  const vault = await deployments.deploy('Vault', {
    from: deployer,
    args: [
      dpxAddress,
      rdpxAddress,
      stakingRewardsAddress,
      optionPricing.address,
      priceOracleAggregator.address,
      ivOracle.address,
    ],
    log: true,
  });
};

deploy.tags = ['Vault'];
export default deploy;
