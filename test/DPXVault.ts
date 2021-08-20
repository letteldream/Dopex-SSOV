import { expect } from "chai";
import { Contract, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";

import {
  deployPriceOracleAggregator,
  deployMockDPXChainlinkUSDAdapter,
  deployMockOptionPricing,
  deployVault
} from "../helper/contract";
import { timeTravel, expandTo18Decimals, expandToDecimals, unlockAccount } from "../helper/util";
import { dpxHolders, dpx, dpxTokenAbi, rdpx, rdpxTokenAbi, stakingRewards, stakingRewardsContractAbi } from "../helper/data";
import { Vault, MockOptionPricing } from '../types';

describe("Vault test", async () => {
  let chainId: number;
  let signers: SignerWithAddress[];
  let owner: SignerWithAddress;
  let user0: Signer;
  let user1: Signer;
  let user2: Signer;
  let dpxToken: Contract;
  let rdpxToken: Contract;
  let stakingRewardsContract: Contract;
  let optionPricing: MockOptionPricing;
  let vault: Vault;
  let strikes = [expandToDecimals(80, 8), expandToDecimals(120, 8), expandToDecimals(150, 8), 0];

  // Contract Setup
  before(async () => {
    signers = await ethers.getSigners();
    owner = signers[0];
    chainId = (await ethers.provider.getNetwork()).chainId;

    // Users
    await unlockAccount(dpxHolders[0]);
    await signers[1].sendTransaction({ to: dpxHolders[0], value: expandTo18Decimals(500)});
    user0 = await ethers.provider.getSigner(dpxHolders[0]);

    await unlockAccount(dpxHolders[1]);
    await signers[2].sendTransaction({ to: dpxHolders[1], value: expandTo18Decimals(500)});
    user1 = await ethers.provider.getSigner(dpxHolders[1]);

    await unlockAccount(dpxHolders[2]);
    await signers[3].sendTransaction({ to: dpxHolders[2], value: expandTo18Decimals(500)});
    user2 = await ethers.provider.getSigner(dpxHolders[2]);

    // DpxToken
    dpxToken = await ethers.getContractAt(dpxTokenAbi, dpx[chainId]);

    // RdpxToken
    rdpxToken = await ethers.getContractAt(rdpxTokenAbi, rdpx[chainId]);

    // StakingRewardsContract
    stakingRewardsContract = await ethers.getContractAt(stakingRewardsContractAbi, stakingRewards[chainId]);

    // Chainlink Price Aggregator
    const priceOracleAggregator = await deployPriceOracleAggregator(
        owner.address
    );

    // Mock DPX Chainlink USD Adapter
    const mockERC20ChainlinkUSDAdapter = await deployMockDPXChainlinkUSDAdapter();
    await priceOracleAggregator.updateOracleForAsset(
        dpx[chainId],
        mockERC20ChainlinkUSDAdapter.address
    );
    await priceOracleAggregator.getPriceInUSD(dpx[chainId]);

    // Mock Option Pricing
    optionPricing = await deployMockOptionPricing();

    // Vault
    vault = await deployVault(dpx[chainId], rdpx[chainId], stakingRewards[chainId], optionPricing.address, priceOracleAggregator.address);
  });

  // Contract Info
  describe("Vault Contract Info", async () => {

      // DPX/RDPX/StakingRewards
      it("DPX/RDPX/StakingRewards Address", async () => {
        expect((await vault.dpx()).toString().toLowerCase()).to.equal(dpx[chainId]);
        expect((await vault.rdpx()).toString().toLowerCase()).to.equal(rdpx[chainId]);
        expect((await vault.stakingRewards()).toString().toLowerCase()).to.equal(stakingRewards[chainId]);
      });

      // DPX token price = 100$
      it("DPX token price is 100 USD", async () => {
          expect((await vault.viewUsdPrice(dpx[chainId]))).to.equal(expandToDecimals(100, 8));
      })
  });

  // Strikes
  describe("Vault Strikes", async () => {

    // Set Strikes OnlyOwner
    it("Set Strikes OnlyOnwer", async () => {
        await expect(vault.connect(user0).setStrikes([120])).to.be.revertedWith("Ownable: caller is not the owner");
    })

    // Set Strikes
    it("Set Strikes Success", async () => {
        await vault.connect(owner).setStrikes(strikes);

        expect((await vault.epochStrikes(1, 0))).to.equal(strikes[0]);
        expect((await vault.epochStrikes(1, 1))).to.equal(strikes[1]);
        expect((await vault.epochStrikes(1, 2))).to.equal(strikes[2]);
    })
  });

  // Deposit Single/Multiple
  describe("Deposit Single/Multiple", async () => {

    // Deposit with wrong strike
    it("Deposit with wrong strike", async () => {
        await expect(vault.connect(user0).deposit(3, 100)).to.be.revertedWith("Invalid strike");
        await expect(vault.connect(user0).deposit(4, 100)).to.
        be.revertedWith("Invalid strike index")
    });

    // Deposit single
    it("Deposit single & userEpochDeposits/totalEpochStrikeDeposits/totalEpochDeposits", async () => {
        const amount0 = expandTo18Decimals(10);
        const user0Address = await user0.getAddress();
        const epoch = (await vault.currentEpoch()).add(1);
        const strike = await vault.epochStrikes(epoch, 0);
        const userStrike = ethers.utils.solidityKeccak256(["address", "uint256"], [user0Address, strike]);

        // Past Data
        const pastBalance = await dpxToken.balanceOf(user0Address);
        const pastUserEpochDeposits = await vault.userEpochDeposits(epoch, userStrike);
        const pastTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        const pastTotalEpochDeposits = await vault.totalEpochDeposits(epoch);

        // Approve
        await dpxToken.connect(user0).approve(vault.address, amount0);

        // Deposit & Event
        await expect(vault.connect(user0).deposit(0, amount0)).to.emit(vault, "LogNewDeposit");

        // Current Data
        const currentBalance = await dpxToken.balanceOf(user0Address);
        expect(currentBalance).to.equal(pastBalance.sub(amount0));

        const currentUserEpochDeposits = await vault.userEpochDeposits(epoch, userStrike);
        expect(currentUserEpochDeposits).to.equal(pastUserEpochDeposits.add(amount0));

        const currentTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        expect(currentTotalEpochStrikeDeposits).to.equal(pastTotalEpochStrikeDeposits.add(amount0));

        const currentTotalEpochDeposits = await vault.totalEpochDeposits(epoch);
        expect(currentTotalEpochDeposits).to.equal(pastTotalEpochDeposits.add(amount0));

    });

    // Deposit multiple
    it("Deposit multiple", async () => {
        const amount0 = expandTo18Decimals(15);
        const amount1 = expandTo18Decimals(25);
        const pastBalance = await dpxToken.balanceOf(await user1.getAddress());

        // Approve
        await dpxToken.connect(user1).approve(vault.address, amount0.add(amount1));

        // Deposit
        await vault.connect(user1).depositMultiple([1, 2], [amount0, amount1]);

        // Balance
        const currentBalance = await dpxToken.balanceOf(await user1.getAddress());
        expect(currentBalance).to.equal(pastBalance.sub(amount0.add(amount1)));
    });
  });

  // Bootstrap
  describe("Bootstrap", async () => {

    // Bootstrap OnlyOwner
    it("Bootstrap OnlyOwner", async () => {
        await expect(vault.connect(user0).bootstrap()).to.be.revertedWith("Ownable: caller is not the owner");
    })

    // Bootstrap EpochStrikeTokens
    it("Bootstrap EpochStrikeTokens name/symbol/amount", async () => {
        const pastEpoch = await vault.currentEpoch();
        await vault.connect(owner).bootstrap();
        const currentEpoch = await vault.currentEpoch();
        expect(currentEpoch).to.equal(pastEpoch.add(1));
        for (let i = 0; i < 3; i++) {
            const epochStrikeTokenAddress = await vault.epochStrikeTokens(currentEpoch, strikes[i]);
            const epochStrikeToken = await ethers.getContractAt(dpxTokenAbi, epochStrikeTokenAddress);

            expect(await epochStrikeToken.name()).to.equal(`DPX-CALL${strikes[i]}-EPOCH-${currentEpoch}`)

            expect(await epochStrikeToken.symbol()).to.equal(`DPX-CALL${strikes[i]}-EPOCH-${currentEpoch}`)

            expect(await epochStrikeToken.balanceOf(vault.address)).to.equal(await vault.totalEpochStrikeDeposits(currentEpoch, strikes[i]))
        }
    })

    // Bootsrap with not expired previous epoch
    it("Bootstrap with not expired previous epoch", async () => {
        timeTravel(24 * 60 * 60 * 30);

        // Set Strikes & Bootstrap
        await vault.connect(owner).setStrikes(strikes);
        await expect(vault.connect(owner).bootstrap()).to.be.revertedWith("Previous epoch has not expired");

        timeTravel(-24 * 60 * 60 * 30);
    })
  });

  // Expire
  describe("Expire", async () => {

    // Expire OnlyOwner
    it("Expire OnlyOwner", async () => {
        await expect(vault.connect(user0).expireEpoch()).to.be.revertedWith("Ownable: caller is not the owner");
    })

    // Expire before epoch's expiry
    it("Expire before epoch's expiry", async () => {
        await expect(vault.connect(owner).expireEpoch()).to.be.revertedWith("Cannot expire epoch before epoch's expiry");
    })

    // Expire 1st epoch
    it("Expire 1st epoch", async () => {
        timeTravel(24 * 60 * 60 * 30);

        await vault.connect(owner).expireEpoch();

        timeTravel(-24 * 60 * 60 * 30);
    })

    // Expire 1st epoch again
    it("Expire 1st epoch again", async () => {
        timeTravel(24 * 60 * 60 * 30);

        await expect(vault.connect(owner).expireEpoch()).to.be.revertedWith("Epoch set as expired");

        timeTravel(-24 * 60 * 60 * 30);
    })
  });

  // Compound
  describe("Compound", async () => {

    // Compound un-bootstrapped epoch
    // it("Compound un-bootstrapped epoch", async () => {
    //     timeTravel(24 * 60 * 60 * 30);

    //     // Purchase before bootstrap
    //     await expect(vault.connect(user0).compound()).to.be.revertedWith("Epoch hasn't been bootstrapped");

    //     timeTravel(-24 * 60 * 60 * 30);
    // });

    // Compound
    it("Compound by any user", async () => {
        const epoch = await vault.currentEpoch();

        await expect(vault.connect(user2).compound()).to.emit(vault, "LogCompound");

        const totalEpochDpxBalance = await vault.totalEpochDpxBalance(epoch);
        const stakingRewardsBalanceOfVault = await stakingRewardsContract.balanceOf(vault.address);

        expect(totalEpochDpxBalance).to.equal(stakingRewardsBalanceOfVault);
    });
  });

  // Purchase
  describe("Purchase", async () => {
      
    // Purhcase Invalid Strike
    it("Purhcase Invalid Strike", async () => {
        await expect(vault.connect(user0).purchase(4, 10)).to.be.revertedWith("Invalid strike index");
        await expect(vault.connect(user0).purchase(3, 10)).to.be.revertedWith("Invalid strike");
    });

    // Purchase un-bootstrapped epoch
    // it("Purchase un-bootstrapped epoch", async () => {
    //     timeTravel(24 * 60 * 60 * 30);
        
    //     // Set Strikes
    //     await vault.connect(owner).setStrikes(strikes);
        
    //     // Deposit
    //     const amount0 = expandTo18Decimals(10);
    //     await dpxToken.connect(user0).approve(vault.address, amount0);
    //     await vault.connect(user0).deposit(0, amount0);

    //     // Purchase before bootstrap
    //     await expect(vault.connect(user0).purchase(0, amount0)).to.be.revertedWith("Epoch hasn't been bootstrapped");

    //     timeTravel(-24 * 60 * 60 * 30);
    // })

    // Purchase exceeds the deposit amount
    it("Purhcase exceeds the deposit amount", async () => {
        await expect(vault.connect(user0).purchase(0, expandTo18Decimals(20))).to.be.revertedWith("User didn't deposit enough for purchase");
    })

    // Purchase
    it("Purchase by user0", async () => {
        const amount = expandTo18Decimals(5);
        const user0Address = await user0.getAddress();
        const epoch = await vault.currentEpoch();
        const strike = await vault.epochStrikes(epoch, 0);
        const userStrike = ethers.utils.solidityKeccak256(["address", "uint256"], [user0Address, strike]);
        const block = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());
        const expiry = await vault.getMonthlyExpiryFromTimestamp(block.timestamp);
        const usdPrice = await vault.viewUsdPrice(dpxToken.address);
        const premium = amount.mul(await optionPricing.getOptionPrice(false, expiry, strike)).div(usdPrice);

        // Epoch Strike Token
        const epochStrikeTokenAddress = await vault.epochStrikeTokens(epoch, strike);
        const epochStrikeToken = await ethers.getContractAt(dpxTokenAbi, epochStrikeTokenAddress);

        // Past Data
        const pastEpochStrikeTokenBalanceOfVault = await epochStrikeToken.balanceOf(vault.address);
        const pastEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user0Address);
        const pastDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        const pastDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        const pastTotalEpochCallsPurchased = await vault.totalEpochCallsPurchased(epoch, strike);
        const pastUserEpochCallsPurchased = await vault.userEpochCallsPurchased(epoch, userStrike);
        const pastTotalEpochPremium = await vault.totalEpochPremium(epoch, strike);
        const pastUserEpochPremium = await vault.userEpochPremium(epoch, userStrike);
        
        // Purchase & Event
        await dpxToken.connect(user0).approve(vault.address, premium);
        await expect(vault.connect(user0).purchase(0, amount)).to.emit(vault, "LogNewPurchase");

        // Current Data
        const currentEpochStrikeTokenBalanceOfVault = await epochStrikeToken.balanceOf(vault.address);
        expect(currentEpochStrikeTokenBalanceOfVault).to.equal(pastEpochStrikeTokenBalanceOfVault.sub(amount));

        const currentEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user0Address);
        expect(currentEpochStrikeTokenBalanceOfUser).to.equal(pastEpochStrikeTokenBalanceOfUser.add(amount));

        const currentDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        expect(currentDpxTokenBalanceOfVault).to.equal(pastDpxTokenBalanceOfVault.add(premium));

        const currentDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        expect(currentDpxTokenBalanceOfUser).to.equal(pastDpxTokenBalanceOfUser.sub(premium));

        const currentTotalEpochCallsPurchased = await vault.totalEpochCallsPurchased(epoch, strike);
        expect(currentTotalEpochCallsPurchased).to.equal(pastTotalEpochCallsPurchased.add(amount));

        const currentUserEpochCallsPurchased = await vault.userEpochCallsPurchased(epoch, userStrike);
        expect(currentUserEpochCallsPurchased).to.equal(pastUserEpochCallsPurchased.add(amount));

        const currentTotalEpochPremium = await vault.totalEpochPremium(epoch, strike);
        expect(currentTotalEpochPremium).to.equal(pastTotalEpochPremium.add(premium));

        const currentUserEpochPremium = await vault.userEpochPremium(epoch, userStrike);
        expect(currentUserEpochPremium).to.equal(pastUserEpochPremium.add(premium));
    })

    it("Purchase by user1", async () => {
        const amount = expandTo18Decimals(10);
        const user1Address = await user1.getAddress();
        const epoch = await vault.currentEpoch();
        const strike = await vault.epochStrikes(epoch, 1);
        const userStrike = ethers.utils.solidityKeccak256(["address", "uint256"], [user1Address, strike]);
        const block = await ethers.provider.getBlock(await ethers.provider.getBlockNumber());
        const expiry = await vault.getMonthlyExpiryFromTimestamp(block.timestamp);
        const usdPrice = await vault.viewUsdPrice(dpxToken.address);
        const premium = amount.mul(await optionPricing.getOptionPrice(false, expiry, strike)).div(usdPrice);

        // Epoch Strike Token
        const epochStrikeTokenAddress = await vault.epochStrikeTokens(epoch, strike);
        const epochStrikeToken = await ethers.getContractAt(dpxTokenAbi, epochStrikeTokenAddress);

        // Past Data
        const pastEpochStrikeTokenBalanceOfVault = await epochStrikeToken.balanceOf(vault.address);
        const pastEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user1Address);
        const pastDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        const pastDpxTokenBalanceOfUser = await dpxToken.balanceOf(user1Address);
        const pastTotalEpochCallsPurchased = await vault.totalEpochCallsPurchased(epoch, strike);
        const pastUserEpochCallsPurchased = await vault.userEpochCallsPurchased(epoch, userStrike);
        const pastTotalEpochPremium = await vault.totalEpochPremium(epoch, strike);
        const pastUserEpochPremium = await vault.userEpochPremium(epoch, userStrike);
        
        // Purchase & Event
        await dpxToken.connect(user1).approve(vault.address, premium);
        await expect(vault.connect(user1).purchase(1, amount)).to.emit(vault, "LogNewPurchase");

        // Current Data
        const currentEpochStrikeTokenBalanceOfVault = await epochStrikeToken.balanceOf(vault.address);
        expect(currentEpochStrikeTokenBalanceOfVault).to.equal(pastEpochStrikeTokenBalanceOfVault.sub(amount));

        const currentEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user1Address);
        expect(currentEpochStrikeTokenBalanceOfUser).to.equal(pastEpochStrikeTokenBalanceOfUser.add(amount));

        const currentDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        expect(currentDpxTokenBalanceOfVault).to.equal(pastDpxTokenBalanceOfVault.add(premium));

        const currentDpxTokenBalanceOfUser = await dpxToken.balanceOf(user1Address);
        expect(currentDpxTokenBalanceOfUser).to.equal(pastDpxTokenBalanceOfUser.sub(premium));

        const currentTotalEpochCallsPurchased = await vault.totalEpochCallsPurchased(epoch, strike);
        expect(currentTotalEpochCallsPurchased).to.equal(pastTotalEpochCallsPurchased.add(amount));

        const currentUserEpochCallsPurchased = await vault.userEpochCallsPurchased(epoch, userStrike);
        expect(currentUserEpochCallsPurchased).to.equal(pastUserEpochCallsPurchased.add(amount));

        const currentTotalEpochPremium = await vault.totalEpochPremium(epoch, strike);
        expect(currentTotalEpochPremium).to.equal(pastTotalEpochPremium.add(premium));

        const currentUserEpochPremium = await vault.userEpochPremium(epoch, userStrike);
        expect(currentUserEpochPremium).to.equal(pastUserEpochPremium.add(premium));
    })
  });

  // Exercise
  describe("Exercise", async () => {

    // Exercise Invalid Strike
    it("Exercise Invalid Strike", async () => {
        timeTravel(24 * 60 * 60 * 30);

        // Set Strikes & Bootstrap
        await vault.connect(owner).setStrikes(strikes);
        await vault.connect(owner).bootstrap();

        const user0Address = await user0.getAddress()
        const epoch = (await vault.currentEpoch()).sub(1)

        await expect(vault.connect(user0).exercise(epoch, 4, 10, user0Address)).to.be.revertedWith("Invalid strike index")
        await expect(vault.connect(user0).exercise(epoch, 3, 10, user0Address)).to.be.revertedWith("Invalid strike")
        await expect(vault.connect(user0).exercise(epoch, 1, 10, user0Address)).to.be.revertedWith("Strike is higher than current price")

        timeTravel(-24 * 60 * 60 * 30);
    });

    // Exercise not past epoch
    it("Exercise not past epoch", async () => {
        const user0Address = await user0.getAddress()
        const epoch = await vault.currentEpoch()

        await expect(vault.connect(user0).exercise(epoch, 0, 1, user0Address)).to.be.revertedWith("Exercise epoch must be in the past")


        timeTravel(24 * 60 * 60 * 30);

        await expect(vault.connect(user0).exercise(epoch, 0, 1, user0Address)).to.be.revertedWith("Exercise epoch must be in the past")

        timeTravel(-24 * 60 * 60 * 30);
    });

    // Exercise by user0
    it("Exercise by user0", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const user0Address = await user0.getAddress()
        const epoch = (await vault.currentEpoch()).sub(1)
        const amount = expandTo18Decimals(2);
        const strike = await vault.epochStrikes(epoch, 0);
        const usdPrice = await vault.viewUsdPrice(dpxToken.address);
        const PnL = amount.mul(usdPrice.sub(strike)).div(usdPrice);

        // Epoch Strike Token
        const epochStrikeTokenAddress = await vault.epochStrikeTokens(epoch, strike);
        const epochStrikeToken = await ethers.getContractAt(dpxTokenAbi, epochStrikeTokenAddress);

        // Past Data
        const pastEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user0Address);
        const pastEpochStrikeTokenTotalSupply = await epochStrikeToken.totalSupply();
        const pastTotalTokenVaultExercises = await vault.totalTokenVaultExercises(epoch);
        const pastDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        const pastDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);

        // Exercise
        await epochStrikeToken.connect(user0).approve(vault.address, amount);
        await expect(vault.connect(user0).exercise(epoch, 0, amount, user0Address)).to.emit(vault, "LogNewExercise");

        // Current Data
        const currentEpochStrikeTokenBalanceOfUser = await epochStrikeToken.balanceOf(user0Address);
        expect(currentEpochStrikeTokenBalanceOfUser).to.equal(pastEpochStrikeTokenBalanceOfUser.sub(amount))

        const currentEpochStrikeTokenTotalSupply = await epochStrikeToken.totalSupply();
        expect(currentEpochStrikeTokenTotalSupply).to.equal(pastEpochStrikeTokenTotalSupply.sub(amount))

        const currentTotalTokenVaultExercises = await vault.totalTokenVaultExercises(epoch);
        expect(currentTotalTokenVaultExercises).to.equal(pastTotalTokenVaultExercises.add(PnL))

        const currentDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        expect(currentDpxTokenBalanceOfUser).to.equal(pastDpxTokenBalanceOfUser.add(PnL))

        const currentDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        expect(currentDpxTokenBalanceOfVault).to.equal(pastDpxTokenBalanceOfVault.sub(PnL))
        
        timeTravel(-24 * 60 * 60 * 30);
    });

    // Exercise by user1
    it("Exercise by user1", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const user1Address = await user1.getAddress()
        const epoch = (await vault.currentEpoch()).sub(1)
        const amount = expandTo18Decimals(2);

        await expect(vault.connect(user1).exercise(epoch, 0, 1, user1Address)).to.be.revertedWith("Option token balance is not enough")

        timeTravel(-24 * 60 * 60 * 30);
    });
  });

  // Withdraw For Strike
  describe("Withdraw For Strike", async () => {

    // WithdrawForStrike Invalid Strike
    it("WithdrawForStrike Invalid Strike", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const epoch = (await vault.currentEpoch()).sub(1)

        await expect(vault.connect(user0).withdrawForStrike(epoch, 4)).to.be.revertedWith("Invalid strike index")
        await expect(vault.connect(user0).withdrawForStrike(epoch, 3)).to.be.revertedWith("Invalid strike")

        timeTravel(-24 * 60 * 60 * 30);
    });

    // WithdrawForStrike not past epoch
    it("WithdrawForStrike not past epoch", async () => {
        const epoch = await vault.currentEpoch()

        await expect(vault.connect(user0).withdrawForStrike(epoch, 0)).to.be.revertedWith("Withdraw epoch must be in the past")


        timeTravel(24 * 60 * 60 * 30);

        await expect(vault.connect(user0).withdrawForStrike(epoch, 0)).to.be.revertedWith("Withdraw epoch must be in the past")

        timeTravel(-24 * 60 * 60 * 30);
    });

    // WithdrawForStrike by user0
    it("WithdrawForStrike by user0", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const user0Address = await user0.getAddress()
        const epoch = (await vault.currentEpoch()).sub(1)
        const strike = await vault.epochStrikes(epoch, 0);
        const userStrike = ethers.utils.solidityKeccak256(["address", "uint256"], [user0Address, strike]);

        // Past Data
        const pastUserStrikeDeposits = await vault.userEpochDeposits(epoch, userStrike);
        const pastTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        const pastDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        const pastDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);

        // Exercise
        await expect(vault.connect(user0).withdrawForStrike(epoch, 0)).to.emit(vault, "LogNewWithdrawForStrike");

        // Current Data
        const currentUserStrikeDeposits = await vault.userEpochDeposits(epoch, userStrike);
        expect(currentUserStrikeDeposits).to.equal(0);

        const currentTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        expect(currentTotalEpochStrikeDeposits).to.equal(pastTotalEpochStrikeDeposits.sub(pastUserStrikeDeposits));

        const currentDpxTokenBalanceOfUser = await dpxToken.balanceOf(user0Address);
        expect(currentDpxTokenBalanceOfUser).to.equal(pastDpxTokenBalanceOfUser.add(pastUserStrikeDeposits));

        const currentDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        expect(currentDpxTokenBalanceOfVault).to.equal(pastDpxTokenBalanceOfVault.sub(pastUserStrikeDeposits));
        
        timeTravel(-24 * 60 * 60 * 30);
    });

    // WithdrawForStrike by user1
    it("WithdrawForStrike by user1", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const user1Address = await user1.getAddress()
        const epoch = (await vault.currentEpoch()).sub(1)
        const strike = await vault.epochStrikes(epoch, 1);
        const userStrike = ethers.utils.solidityKeccak256(["address", "uint256"], [user1Address, strike]);

        // Past Data
        const pastUserStrikeDeposits = await vault.userEpochDeposits(epoch, userStrike);
        const pastTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        const pastDpxTokenBalanceOfUser = await dpxToken.balanceOf(user1Address);
        const pastDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);

        // Exercise
        await expect(vault.connect(user1).withdrawForStrike(epoch, 1)).to.emit(vault, "LogNewWithdrawForStrike");

        // Current Data
        const currentUserStrikeDeposits = await vault.userEpochDeposits(epoch, userStrike);
        expect(currentUserStrikeDeposits).to.equal(0);

        const currentTotalEpochStrikeDeposits = await vault.totalEpochStrikeDeposits(epoch, strike);
        expect(currentTotalEpochStrikeDeposits).to.equal(pastTotalEpochStrikeDeposits.sub(pastUserStrikeDeposits));

        const currentDpxTokenBalanceOfUser = await dpxToken.balanceOf(user1Address);
        expect(currentDpxTokenBalanceOfUser).to.equal(pastDpxTokenBalanceOfUser.add(pastUserStrikeDeposits));

        const currentDpxTokenBalanceOfVault = await dpxToken.balanceOf(vault.address);
        expect(currentDpxTokenBalanceOfVault).to.equal(pastDpxTokenBalanceOfVault.sub(pastUserStrikeDeposits));
        
        timeTravel(-24 * 60 * 60 * 30);
    });

    // WithdrawForStrike by user2
    it("WithdrawForStrike by user2", async () => {
        timeTravel(24 * 60 * 60 * 30);

        const epoch = (await vault.currentEpoch()).sub(1)

        await expect(vault.connect(user2).withdrawForStrike(epoch, 1)).to.be.revertedWith("User strike deposit amount must be greater than zero")
        
        timeTravel(-24 * 60 * 60 * 30);
    });
  })
});