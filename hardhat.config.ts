import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-etherscan';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'solidity-coverage';
import 'hardhat-deploy';

require('dotenv').config();

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
  namedAccounts: {
    deployer: 0,
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
  },
  typechain: {
    outDir: 'types/',
    target: 'ethers-v5',
  },
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
    ...(process.env.KOVAN_NET_API_URL &&
      process.env.KOVAN_MNEMONIC && {
        kovan: {
          url: process.env.KOVAN_NET_API_URL,
          accounts: { mnemonic: process.env.KOVAN_MNEMONIC },
        },
      }),
  },
  paths: {
    deploy: 'deploy',
    deployments: 'deployments',
    imports: 'imports',
  },
  ...(process.env.ETHERSCAN_API_KEY && {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY,
    },
  }),
};
