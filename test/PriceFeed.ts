import { expect } from "chai";
import { Contract } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";

import {
  deployPriceOracleAggregator,
  deployChainlinkUSDAdapter,
  deployUniswapV2Oracle
} from "../helper/contract";
import { timeTravel } from "../helper/util";
import { priceFeedAddresses, dpx, weth, uniswapFactory } from "../helper/data";
import { PriceOracleAggregator } from "../types";

describe("chainlink PriceFeed test", async () => {
  let chainId: number;
  let signers: SignerWithAddress[];
  let priceOracleAggregator: PriceOracleAggregator;

  before(async () => {
    signers = await ethers.getSigners();
    priceOracleAggregator = await deployPriceOracleAggregator(
      signers[0].address
    );
    chainId = (await ethers.provider.getNetwork()).chainId;
  });

  // Mainnet Tokens test
  it("Check mainnet token price", async () => {

    // Chainlink Adapter Setup (ETH, WETH, SUSHI, AAVE, UNI)
    const tokens = Object.keys(priceFeedAddresses);
    for (let i = 0; i < tokens.length; i++) {
      const token = (priceFeedAddresses as any)[tokens[i]].token;
      const priceFeed = (priceFeedAddresses as any)[tokens[i]].priceFeed;

      const chainlinkUsdAdapter = await deployChainlinkUSDAdapter(
        token,
        priceFeed
      );
      await priceOracleAggregator.updateOracleForAsset(
        token,
        chainlinkUsdAdapter.address
      );
      await priceOracleAggregator.getPriceInUSD(token);
    }

    // UniswapV2Oracle Setup (DPX)
    const uniswapV2Oracle = await deployUniswapV2Oracle(
        uniswapFactory,
        dpx[chainId],
        weth,
        priceOracleAggregator.address
    )
    await priceOracleAggregator.updateOracleForAsset(
        dpx[chainId],
        uniswapV2Oracle.address
    )
    timeTravel(24 * 60 * 60);
    await priceOracleAggregator.getPriceInUSD(dpx[chainId]);

    // Get Tokens USD Price
    console.log("Ethereum price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
      )).toNumber()
    );

    console.log("WETH price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
      )).toNumber()
    );

    console.log("UNI Token price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
      )).toNumber()
    );

    console.log("AAVE Token price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9"
      )).toNumber()
    );

    console.log("SUSHI Token price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2"
      )).toNumber()
    );

    console.log("DPX Token price in USD");
    console.log(
      (await priceOracleAggregator.viewPriceInUSD(
        dpx[chainId]
      )).toNumber()
    );
  });
});