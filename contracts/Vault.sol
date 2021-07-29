//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/**                             .                    .                             
                           .'.                    .'.                           
                         .;:.                      .;:.                         
                       .:o:.                        .;l:.                       
                     .:dd,                            ,od:.                     
                   .:dxo'                              .lxd:.                   
                 .:dkxc.                                .:xkd:.                 
               .:dkkx:.                                  .;dkkd:.               
              .ckkkkxl:,'..                            ..':dkkkkl.              
               'codxxkkkxxdol,                     .,cldxkkkxdoc,               
                  ..',;coxkkkl.                  .;dxkxdol:;'..                 
                       .cxkxl.                   ;dkxl,..                       
                      .:xxxc.                   .cxxd'                          
                      ;dxd:.    ;c,.            .:dxo'                          
                     .lddc.    .cdoc.            'odd:.                         
                     .loo;.     .clol'           .;ool,                         
                     .:loc,.      ..'.            .:loc'                        
                      .,cllc;'.                    .;llc'                       
                        .';cccc:'.                  .;cc:.                      
                           ..,;::;'                  .;::;.                     
                              .';::,.                 .;:;.                     
                                .,;;,.                .;;;.                     
                                  .,,,'..            .,,,'.                     
                                   ..',,,'..      ..'','.                       
                                     ...'''''.....'''...                        
                                         ............                           
                            DOPEX SINGLE STAKING OPTION VAULTS
            Mints covered calls while farming yield on single sided DPX staking vaults                                                            
*/

import "hardhat/console.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {BokkyPooBahsDateTimeLibrary} from "./libraries/BokkyPooBahsDateTimeLibrary.sol";
import {SafeERC20} from "./libraries/SafeERC20.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IStakingRewards.sol";
import "./interfaces/IOptionPricing.sol";
import "./interfaces/IPriceOracleAggregator.sol";

contract Vault is Ownable {
    using BokkyPooBahsDateTimeLibrary for uint256;
    using Strings for uint256;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // DPX token
    IERC20 public dpx;

    // rDPX token
    IERC20 public rdpx;
    // DPX single staking rewards contract
    IStakingRewards public stakingRewards;
    // Option pricing provider
    IOptionPricing public optionPricing;

    // Current epoch for vault
    uint256 public epoch;
    // Initial bootstrap time
    uint256 public epochInitTime;
    // Mapping of strikes for each epoch
    mapping(uint256 => uint256[]) public epochStrikes;
    // Mapping of (epoch => (strike => tokens))
    mapping(uint256 => mapping(uint256 => address)) public epochStrikeTokens;

    // Total epoch deposits for specific strikes
    // mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDeposits;
    // Total epoch deposits across all strikes
    // mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochDeposits;
    // Epoch deposits by user for each strike
    // mapping (epoch => (abi.encodePacked(user, strike) => user deposits))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochDeposits;
    // Epoch DPX balance after accounting for rewards
    // mapping (epoch => balance)
    mapping(uint256 => uint256) public totalEpochDpxBalance;
    // Epoch rDPX balance after accounting for rewards
    // mapping (epoch => balance)
    mapping(uint256 => uint256) public totalEpochRdpxBalance;
    // Calls purchased for each strike in an epoch
    // mapping (epoch => (strike => calls purchased))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochCallsPurchased;
    // Calls purchased by user for each strike
    // mapping (epoch => (abi.encodePacked(user, strike) => user calls purchased))
    mapping(uint256 => mapping(bytes32 => uint256))
        public userEpochCallsPurchased;
    // Premium collected per strike for an epoch
    // mapping (epoch => (strike => premium))
    mapping(uint256 => mapping(uint256 => uint256)) public totalEpochPremium;
    // User premium collected per strike for an epoch
    // mapping (epoch => (abi.encodePacked(user, strike) => user premium))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochPremium;
    // Total dpx tokens that were sent back to the buyer when a
    // vault is exercised
    // mapping (epoch => amount)
    mapping(uint256 => uint256) public totalTokenVaultExercises;

    // Price Oracle Aggregator
    /// @dev getPriceInUSD(address _token)
    IPriceOracleAggregator public priceOracleAggregator;

    event LogNewStrike(uint256 epoch, uint256 strike);
    event LogBootstrap(uint256 epoch);
    event LogNewDeposit(uint256 epoch, uint256 strike, address user);
    event LogNewPurchase(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 premium
    );
    event LogNewExercise(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl
    );
    event LogCompound(
        uint256 epoch,
        uint256 rewards,
        uint256 oldBalance,
        uint256 newBalance
    );

    constructor(
        address _dpx,
        address _rdpx,
        address _stakingRewards,
        address _optionPricing,
        address _priceOracleAggregator
    ) {
        require(_dpx != address(0), "Invalid dpx address");
        require(_rdpx != address(0), "Invalid rdpx address");
        require(
            _stakingRewards != address(0),
            "Invalid staking rewards address"
        );
        require(_optionPricing != address(0), "Invalid option pricing address");
        require(
            _priceOracleAggregator != address(0),
            "Invalid price oracle aggregator"
        );

        dpx = IERC20(_dpx);
        rdpx = IERC20(_rdpx);
        stakingRewards = IStakingRewards(_stakingRewards);
        optionPricing = IOptionPricing(_optionPricing);
        priceOracleAggregator = IPriceOracleAggregator(_priceOracleAggregator);
    }

    /**
     * Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
     * @return Whether bootstrap was successful
     */
    function bootstrap() public onlyOwner returns (bool) {
        require(
            epochStrikes[epoch + 1].length > 0,
            "Strikes have not been set for next epoch"
        );
        require(
            getCurrentMonthlyEpoch() == epoch + 1,
            "Epoch hasn't completed yet"
        );
        if (epoch == 0) {
            epochInitTime = block.timestamp;
        } else {
            // Unstake all tokens from previous epoch
            stakingRewards.withdraw(stakingRewards.balanceOf(address(this)));
            // Claim DPX and RDPX rewards
            stakingRewards.getReward(2);
            // Update final dpx and rdpx balances for epoch
            totalEpochDpxBalance[epoch] = dpx.balanceOf(address(this));
            totalEpochRdpxBalance[epoch] = rdpx.balanceOf(address(this));
        }
        for (uint256 i = 0; i < epochStrikes[epoch + 1].length; i++) {
            uint256 strike = epochStrikes[epoch + 1][i];
            string memory name = concatenate("DPX-CALL", strike.toString());
            name = concatenate(name, "-EPOCH-");
            name = concatenate(name, (epoch + 1).toString());
            // Create doTokens representing calls for selected strike in epoch
            ERC20PresetMinterPauser _erc20 = new ERC20PresetMinterPauser(
                name,
                name
            );
            epochStrikeTokens[epoch + 1][strike] = address(_erc20);
            // Mint tokens equivalent to deposits for strike in epoch
            _erc20.mint(
                address(this),
                totalEpochStrikeDeposits[epoch + 1][strike]
            );
        }
        epoch += 1;
        emit LogBootstrap(epoch);
        return true;
    }

    /**
     * Sets strikes for next epoch
     * @param strikes Strikes to set for next epoch
     * @return Whether strikes were set
     */
    function setStrikes(uint256[] memory strikes)
        public
        onlyOwner
        returns (bool)
    {
        epochStrikes[epoch + 1] = strikes;
        for (uint256 i = 0; i < strikes.length; i++)
            emit LogNewStrike(epoch + 1, strikes[i]);
        return true;
    }

    /**
     * Deposits dpx into vaults to mint options in the next epoch for selected strikes
     * @param strikeIndex Index of strike
     * @param amount Amout of DPX to deposit
     * @return Whether deposit was successful
     */
    function deposit(uint256 strikeIndex, uint256 amount)
        public
        returns (bool)
    {
        // Must be a valid strikeIndex
        require(
            strikeIndex < epochStrikes[epoch + 1].length,
            "Invalid strike index"
        );

        // Must positive amount
        require(amount > 0, "Invalid amount");

        // Must be a valid strike
        uint256 strike = epochStrikes[epoch + 1][strikeIndex];
        require(strike != 0, "Invalid strike");

        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));

        // Transfer DPX from user to vault
        dpx.transferFrom(msg.sender, address(this), amount);

        // Add to user epoch deposits
        userEpochDeposits[epoch + 1][userStrike] += amount;
        // Add to total epoch strike deposits
        totalEpochStrikeDeposits[epoch + 1][strike] += amount;
        // Add to total epoch deposits
        totalEpochDeposits[epoch + 1] += amount;
        // Deposit into staking rewards
        dpx.approve(address(stakingRewards), amount);
        stakingRewards.stake(amount);

        emit LogNewDeposit(epoch + 1, strike, msg.sender);

        return true;
    }

    /**
     * Deposit DPX multiple times
     * @param strikeIndices Indices of strikes to deposit into
     * @param amounts Amount of DPX to deposit into each strike index
     * @return Whether deposits went through successfully
     */
    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts
    ) public returns (bool) {
        require(
            strikeIndices.length == amounts.length,
            "Invalid strikeIndices/amounts"
        );
        for (uint256 i = 0; i < strikeIndices.length; i++)
            deposit(strikeIndices[i], amounts[i]);
        return true;
    }

    /**
     * Purchases calls for the current epoch
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to purchase
     * @return Whether purchase was successful
     */
    function purchase(uint256 strikeIndex, uint256 amount)
        public
        returns (bool)
    {
        // Must be a valid strikeIndex
        require(
            strikeIndex < epochStrikes[epoch].length,
            "Invalid strike index"
        );

        // Must positive amount
        require(amount > 0, "Invalid amount");

        // Must be bootstrapped
        require(
            getCurrentMonthlyEpoch() == epoch,
            "Epoch hasn't been bootstrapped"
        );

        // Must be a valid strike
        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, "Invalid strike");

        // Must deposit enough by user
        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
        require(
            userEpochCallsPurchased[epoch][userStrike] + amount <=
                userEpochDeposits[epoch][userStrike],
            "User didn't deposit enough for purchase"
        );

        // Transfer doTokens to user
        IERC20(epochStrikeTokens[epoch][strike]).transfer(msg.sender, amount);

        // Get total premium for all calls being purchased
        uint256 premium = optionPricing
        .getOptionPrice(
            false,
            getMonthlyExpiryFromTimestamp(block.timestamp),
            strike
        ).mul(amount)
        .div(getUsdPrice(address(dpx)));
        // Transfer usd equivalent to premium from user
        dpx.transferFrom(msg.sender, address(this), premium);

        // Add to total epoch calls purchased
        totalEpochCallsPurchased[epoch][strike] += amount;
        // Add to user epoch calls purchased
        userEpochCallsPurchased[epoch][userStrike] += amount;
        // Add to total epoch premium
        totalEpochPremium[epoch][strike] += premium;
        // Add to user epoch premium
        userEpochPremium[epoch][userStrike] += premium;

        emit LogNewPurchase(epoch, strike, msg.sender, amount, premium);

        return true;
    }

    /**
     * Exercise calculates the PnL for the user. Withdraw the PnL in DPX from the SSF and transfer it to the user. Will also the burn the doTokens from the user.
     * @param exerciseEpoch Target epoch
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to exercise
     * @param user Address of the user
     * @return Whether vault was exercised
     */
    function exercise(
        uint256 exerciseEpoch,
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) public returns (bool) {
        // Must be a past epoch
        require(
            exerciseEpoch < epoch && epoch == getCurrentMonthlyEpoch(),
            "Exercise epoch must be in the past"
        );

        // Must be a valid strikeIndex
        require(
            strikeIndex < epochStrikes[exerciseEpoch].length,
            "Invalid strike index"
        );

        // Must positive amount
        require(amount > 0, "Invalid amount");

        // Must be a valid strike
        uint256 strike = epochStrikes[exerciseEpoch][strikeIndex];
        require(strike != 0, "Invalid strike");

        uint256 currentPrice = getUsdPrice(address(dpx));

        // Revert if strike price is higher than current price
        require(strike < currentPrice, "Strike is higher than current price");

        // Revert if user is zero address
        require(user != address(0), "Invalid user address");

        // Revert if user does not have enough option token balance for the amount specified
        require(
            IERC20(epochStrikeTokens[exerciseEpoch][strike]).balanceOf(user) >=
                amount,
            "Option token balance is not enough"
        );

        // Calculate PnL
        uint256 PnL = ((currentPrice - strike) * amount) / currentPrice;

        // Burn user option tokens
        ERC20PresetMinterPauser(epochStrikeTokens[exerciseEpoch][strike])
            .burnFrom(user, amount);

        // Update state to account for exercised options (amount of DPX used in exercising)
        totalTokenVaultExercises[exerciseEpoch] += PnL;

        // Transfer PnL to user
        dpx.safeTransfer(user, PnL);

        emit LogNewExercise(epoch, strike, user, amount, PnL);

        return true;
    }

    /**
     * Allows anyone to call compound()
     * @return Whether compound was successful
     */
    function compound() public returns (bool) {
        // Must be bootstrapped
        require(
            getCurrentMonthlyEpoch() == epoch,
            "Epoch hasn't been bootstrapped"
        );
        uint256 oldBalance = stakingRewards.balanceOf(address(this));
        uint256 rewards = stakingRewards.rewardsDPX(address(this));
        // Compound staking rewards
        stakingRewards.compound();
        // Update epoch balance
        totalEpochDpxBalance[epoch] = stakingRewards.balanceOf(address(this));
        emit LogCompound(
            epoch,
            rewards,
            oldBalance,
            totalEpochDpxBalance[epoch]
        );

        return true;
    }

    /**
     * Withdraws balances for a strike in a completed epoch
     * @param withdrawEpoch Epoch to withdraw from
     * @param strikeIndex Index of strike
     * @return Whether withdraw was successful
     */
    function withdrawForStrike(uint256 withdrawEpoch, uint256 strikeIndex)
        public
        returns (bool)
    {
        // Must be a past epoch
        require(
            withdrawEpoch < epoch && epoch == getCurrentMonthlyEpoch(),
            "Withdraw epoch must be in the past"
        );

        // Must be a valid strikeIndex
        require(
            strikeIndex < epochStrikes[withdrawEpoch].length,
            "Invalid strike index"
        );

        // Must be a valid strike
        uint256 strike = epochStrikes[withdrawEpoch][strikeIndex];
        require(strike != 0, "Invalid strike");

        // Must be a valid user strike deposit amount
        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
        uint256 userStrikeDeposits = userEpochDeposits[withdrawEpoch][
            userStrike
        ];
        require(
            userStrikeDeposits > 0,
            "User strike deposit amount must be greater than zero"
        );

        // Transfer DPX tokens to user
        userEpochDeposits[withdrawEpoch][userStrike] = 0;
        totalEpochStrikeDeposits[withdrawEpoch][strike] -= userStrikeDeposits;

        dpx.transfer(msg.sender, userStrikeDeposits);

        return true;
    }

    /**
     * Returns start and end times for an epoch
     * @param epoch Target epoch
     * @param timePeriod Time period of the epoch (7 days or 28 days)
     */
    function getEpochTimes(uint256 epoch, uint256 timePeriod)
        external
        view
        returns (uint256 start, uint256 end)
    {
        if (timePeriod == 7 days) {
            if (epoch == 1) {
                return (
                    epochInitTime,
                    getWeeklyExpiryFromTimestamp(epochInitTime)
                );
            } else {
                uint256 _start = getWeeklyExpiryFromTimestamp(epochInitTime) +
                    (timePeriod * (epoch - 2));
                return (_start, _start + timePeriod);
            }
        } else if (timePeriod == 28 days) {
            if (epoch == 1) {
                return (
                    epochInitTime,
                    getMonthlyExpiryFromTimestamp(epochInitTime)
                );
            } else {
                uint256 _start = getMonthlyExpiryFromTimestamp(epochInitTime) +
                    (timePeriod * (epoch - 2));
                return (_start, _start + timePeriod);
            }
        }
    }

    /*=== PURE FUNCTIONS ====*/

    /// @notice Calculates next available Friday expiry from a solidity date
    /// @param timestamp Timestamp from which the friday expiry is to be calculated
    /// @return The friday expiry
    function getWeeklyExpiryFromTimestamp(uint256 timestamp)
        public
        pure
        returns (uint256)
    {
        // Use friday as 1-index
        uint256 dayOfWeek = BokkyPooBahsDateTimeLibrary.getDayOfWeek(
            timestamp,
            6
        );
        uint256 nextFriday = timestamp + ((7 - dayOfWeek + 1) * 1 days);
        return
            BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
                nextFriday.getYear(),
                nextFriday.getMonth(),
                nextFriday.getDay(),
                12,
                0,
                0
            );
    }

    /// @notice Calculates the monthly expiry from a solidity date
    /// @param timestamp Timestamp from which the monthly expiry is to be calculated
    /// @return The monthly expiry
    function getMonthlyExpiryFromTimestamp(uint256 timestamp)
        public
        pure
        returns (uint256)
    {
        uint256 lastDay = BokkyPooBahsDateTimeLibrary.timestampFromDate(
            timestamp.getYear(),
            timestamp.getMonth() + 1,
            0
        );

        if (lastDay.getDayOfWeek() < 5) {
            lastDay = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                lastDay.getYear(),
                lastDay.getMonth(),
                lastDay.getDay() - 7
            );
        }

        uint256 lastFridayOfMonth = BokkyPooBahsDateTimeLibrary
        .timestampFromDateTime(
            lastDay.getYear(),
            lastDay.getMonth(),
            lastDay.getDay() - (lastDay.getDayOfWeek() - 5),
            12,
            0,
            0
        );

        if (lastFridayOfMonth <= timestamp) {
            uint256 temp = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                timestamp.getYear(),
                timestamp.getMonth() + 2,
                0
            );

            if (temp.getDayOfWeek() < 5) {
                temp = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                    temp.getYear(),
                    temp.getMonth(),
                    temp.getDay() - 7
                );
            }

            lastFridayOfMonth = BokkyPooBahsDateTimeLibrary
            .timestampFromDateTime(
                temp.getYear(),
                temp.getMonth(),
                temp.getDay() - (temp.getDayOfWeek() - 5),
                12,
                0,
                0
            );
        }
        return lastFridayOfMonth;
    }

    /**
     * @notice Returns the current epoch based on the epoch init time and a 4 week time period
     * @dev Epochs are 1-indexed
     * @return Current monthly epoch number
     */
    function getCurrentMonthlyEpoch() public view returns (uint256) {
        if (block.timestamp < epochInitTime) return 0;
        if (epochInitTime == 0) return 1;
        /**
         * Monthly Epoch = ((Current time - Init time) / 28 days) + 1
         * The current time is adjust to account for any 'init time' by adding to it the difference
         * between the init time and the first expiry.
         * Current time = block.timestamp - (28 days - (The first expiry - init time))
         */
        return
            (((block.timestamp +
                (28 days -
                    (getMonthlyExpiryFromTimestamp(epochInitTime) -
                        epochInitTime))) - epochInitTime) / (28 days)) + 1;
    }

    /**
     * @notice Returns the current epoch based on the epoch init time and a 1 week time period
     * @dev Epochs are 1-indexed
     * @return Current weekly epoch number
     */
    function getCurrentWeeklyEpoch() external view returns (uint256) {
        if (block.timestamp < epochInitTime) return 0;
        /**
         * Weekly Epoch = ((Current time - Init time) / 7 days) + 1
         * The current time is adjust to account for any 'init time' by adding to it the difference
         * between the init time and the first expiry.
         * Current time = block.timestamp - (7 days - (The first expiry - init time))
         */
        return
            (((block.timestamp +
                (7 days -
                    (getWeeklyExpiryFromTimestamp(epochInitTime) -
                        epochInitTime))) - epochInitTime) / (7 days)) + 1;
    }

    function concatenate(string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    function getUsdPrice(address _token) public returns (uint256) {
        return priceOracleAggregator.getPriceInUSD(_token);
    }

    function viewUsdPrice(address _token) public view returns (uint256) {
        return priceOracleAggregator.viewPriceInUSD(_token);
    }
}
