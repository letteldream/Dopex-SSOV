import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import {
  chainIdToNetwork,
  dpx,
  rdpx,
  stakingRewards,
  optionPricing,
} from '../helper/data'

const deploy = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, getChainId, ethers } = hre
  const { deployer } = await getNamedAccounts()
  const chainId = parseInt(await getChainId())
  const network = chainIdToNetwork[chainId]
  const dpxAddress = dpx[chainId]
  const rdpxAddress = rdpx[chainId]
  const stakingRewardsAddress = stakingRewards[chainId]
  const optionPricingAddress = optionPricing[chainId]

  console.log('111000000>>>>>', deployer, chainId)
  if (
    !network ||
    !dpxAddress ||
    !rdpxAddress ||
    !stakingRewardsAddress ||
    !optionPricingAddress
  )
    return

  // Deploy MockDPXChainlinkUSDAdapter
  const mockDPXChainlinkUSDAdapter = await deployments.deploy(
    'MockDPXChainlinkUSDAdapter',
    {
      from: deployer,
      args: [],
      // libraries: {},
      log: true,
    }
  )

  // Deploy PriceOracleAggregator
  const { address } = await deployments.deploy('PriceOracleAggregator', {
    from: deployer,
    args: [deployer],
    // libraries: {},
    log: true,
  })

  const priceOracleAggregator = await ethers.getContractAt(
    'PriceOracleAggregator',
    address
  )
  await priceOracleAggregator.updateOracleForAsset(
    dpxAddress,
    mockDPXChainlinkUSDAdapter.address
  )

  // Deploy Vault
  const vault = await deployments.deploy('Vault', {
    from: deployer,
    args: [
      dpxAddress,
      rdpxAddress,
      stakingRewardsAddress,
      optionPricingAddress,
      priceOracleAggregator.address,
    ],
    // libraries: {},
    log: true,
  })

  // Verify
  await hre.run('verify:verify', {
    address: mockDPXChainlinkUSDAdapter.address,
  })
  await hre.run('verify:verify', {
    address: priceOracleAggregator.address,
    constructorArguments: [deployer],
  })
  await hre.run('verify:verify', {
    address: vault.address,
    constructorArguments: [
      dpxAddress,
      rdpxAddress,
      stakingRewardsAddress,
      optionPricingAddress,
      priceOracleAggregator.address,
    ],
  })
}

deploy.tags = ['Vault']
export default deploy
