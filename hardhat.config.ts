import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-contract-sizer'
import 'solidity-coverage'
import 'hardhat-deploy'
import '@nomiclabs/hardhat-etherscan'

require('dotenv').config()

export default {
  solidity: {
    version: '0.8.4',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  // contractSizer: {
  //   alphaSort: true,
  //   runOnCompile: true,
  //   disambiguatePaths: false,
  // },
  namedAccounts: {
    deployer: {
      default: 0,
      42: '0x482C9f85644f1686C490D38291511657da767e61',
    },
  },
  typechain: {
    outDir: 'types/',
    target: 'ethers-v5',
  },
  defaultNetwork: 'kovan',
  networks: {
    hardhat: {
      forking: {
        url: process.env.MAIN_NET_API_URL,
      },
      hardfork: 'london',
      gasPrice: 'auto',
    },
    localhost: {
      url: 'http://127.0.0.1:8545',
    },
    kovan: {
      url: process.env.KOVAN_NET_API_URL,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  paths: {
    deploy: 'deploy',
    deployments: 'deployments',
    imports: 'imports',
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
}
