import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "hardhat-contract-sizer";
import "solidity-coverage";

require("dotenv").config();

export default {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  typechain: {
    outDir: "types/",
    target: "ethers-v5",
  },
  mocha: {
    timeout: 100000,
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      forking: {
        url: process.env.MAIN_NET_API_URL,
      },
      hardfork: "london",
      gasPrice: "auto",
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    // kovan: {
    //   url: process.env.KOVAN_NET_API_URL,
    //   accounts: [process.env.PRIVATE_KEY],
    // },
  },
};