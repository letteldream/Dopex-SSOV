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

// Libraries
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { BokkyPooBahsDateTimeLibrary } from "./libraries/BokkyPooBahsDateTimeLibrary.sol";
import { SafeERC20 } from "./libraries/SafeERC20.sol";

// Contracts
import { IvOracle } from "./oracle/IvOracle.sol";

// Interfaces
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

  // ivOracle addrss
  address public ivOracleAddress;

  // Current epoch for vault
  uint256 public currentEpoch;
  /// @dev epoch => the epoch start time
  mapping(uint256 => uint256) public epochStartTimes;
  /// @notice Is epoch expired
  /// @dev epoch => whether the epoch is expired
  mapping(uint256 => bool) public isEpochExpired;
  /// @notice Is vault ready for next epoch
  /// @dev epoch => whether the vault is ready (boostrapped)
  mapping(uint256 => bool) public isVaultReady;

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
  event LogNewWithdrawForStrike(
    uint256 epoch,
    uint256 strike,
    address user,
    uint256 amount
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
    require(_stakingRewards != address(0), "Invalid staking rewards address");
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

  /// @notice Sets the current epoch as expired.
  /// @return Whether expire was successful
  function expireEpoch() external onlyOwner returns (bool) {
    // Epoch must not be expired
    require(!isEpochExpired[currentEpoch], "Epoch set as expired");

    (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
    // Current timestamp should be past expiry
    require(
      (block.timestamp > epochExpiry),
      "Cannot expire epoch before epoch's expiry"
    );

    isEpochExpired[currentEpoch] = true;

    return true;
  }

  /**
   * Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
   * @return Whether bootstrap was successful
   */
  function bootstrap() external onlyOwner returns (bool) {
    uint256 nextEpoch = currentEpoch + 1;
    // Vault must not be ready
    require(!isVaultReady[nextEpoch], "Vault already bootstrapped");
    // Next epoch strike must be set
    require(
      epochStrikes[nextEpoch].length > 0,
      "Strikes have not been set for next epoch"
    );

    if (currentEpoch > 0) {
      // Previous epoch must be expired
      require(isEpochExpired[currentEpoch], "Previous epoch has not expired");

      // Unstake all tokens from previous epoch
      stakingRewards.withdraw(stakingRewards.balanceOf(address(this)));
      // Claim DPX and RDPX rewards
      stakingRewards.getReward(2);
      // Update final dpx and rdpx balances for epoch
      totalEpochDpxBalance[currentEpoch] = dpx.balanceOf(address(this));
      totalEpochRdpxBalance[currentEpoch] = rdpx.balanceOf(address(this));
    }

    for (uint256 i = 0; i < epochStrikes[nextEpoch].length; i++) {
      uint256 strike = epochStrikes[nextEpoch][i];
      string memory name = concatenate("DPX-CALL", strike.toString());
      name = concatenate(name, "-EPOCH-");
      name = concatenate(name, (nextEpoch).toString());
      // Create doTokens representing calls for selected strike in epoch
      ERC20PresetMinterPauser _erc20 = new ERC20PresetMinterPauser(name, name);
      epochStrikeTokens[nextEpoch][strike] = address(_erc20);
      // Mint tokens equivalent to deposits for strike in epoch
      _erc20.mint(address(this), totalEpochStrikeDeposits[nextEpoch][strike]);
    }

    // Mark vault as ready for epoch
    isVaultReady[nextEpoch] = true;
    // Increase the current epoch
    currentEpoch = nextEpoch;

    emit LogBootstrap(nextEpoch);

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
    uint256 nextEpoch = currentEpoch + 1;
    // Set the next epoch strikes
    epochStrikes[nextEpoch] = strikes;
    // Set the next epoch start time
    epochStartTimes[nextEpoch] = block.timestamp;

    for (uint256 i = 0; i < strikes.length; i++)
      emit LogNewStrike(nextEpoch, strikes[i]);
    return true;
  }

  /**
   * Deposits dpx into vaults to mint options in the next epoch for selected strikes
   * @param strikeIndex Index of strike
   * @param amount Amout of DPX to deposit
   * @return Whether deposit was successful
   */
  function deposit(uint256 strikeIndex, uint256 amount) public returns (bool) {
    uint256 nextEpoch = currentEpoch + 1;
    // Must be a valid strikeIndex
    require(
      strikeIndex < epochStrikes[nextEpoch].length,
      "Invalid strike index"
    );

    // Must positive amount
    require(amount > 0, "Invalid amount");

    // Must be a valid strike
    uint256 strike = epochStrikes[nextEpoch][strikeIndex];
    require(strike != 0, "Invalid strike");

    bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));

    // Transfer DPX from user to vault
    dpx.transferFrom(msg.sender, address(this), amount);

    // Add to user epoch deposits
    userEpochDeposits[nextEpoch][userStrike] += amount;
    // Add to total epoch strike deposits
    totalEpochStrikeDeposits[nextEpoch][strike] += amount;
    // Add to total epoch deposits
    totalEpochDeposits[nextEpoch] += amount;
    // Deposit into staking rewards
    dpx.approve(address(stakingRewards), amount);
    stakingRewards.stake(amount);

    emit LogNewDeposit(nextEpoch, strike, msg.sender);

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
  function purchase(uint256 strikeIndex, uint256 amount) public returns (bool) {
    if (currentEpoch == 0) {
      return false;
    }

    // Must be a valid strikeIndex
    require(
      strikeIndex < epochStrikes[currentEpoch].length,
      "Invalid strike index"
    );

    // Must positive amount
    require(amount > 0, "Invalid amount");

    // Must be a valid strike
    uint256 strike = epochStrikes[currentEpoch][strikeIndex];
    require(strike != 0, "Invalid strike");

    // Must deposit enough by user
    bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
    require(
      userEpochCallsPurchased[currentEpoch][userStrike] + amount <=
        userEpochDeposits[currentEpoch][userStrike],
      "User didn't deposit enough for purchase"
    );

    // Transfer doTokens to user
    IERC20(epochStrikeTokens[currentEpoch][strike]).transfer(
      msg.sender,
      amount
    );

    // Get total premium for all calls being purchased
    uint256 premium = optionPricing
      .getOptionPrice(
        false,
        getMonthlyExpiryFromTimestamp(block.timestamp),
        strike,
        getUsdPrice(address(dpx)),
        IvOracle(ivOracleAddress).getIv()
      )
      .mul(amount)
      .div(getUsdPrice(address(dpx)));
    // Transfer usd equivalent to premium from user
    dpx.transferFrom(msg.sender, address(this), premium);

    // Add to total epoch calls purchased
    totalEpochCallsPurchased[currentEpoch][strike] += amount;
    // Add to user epoch calls purchased
    userEpochCallsPurchased[currentEpoch][userStrike] += amount;
    // Add to total epoch premium
    totalEpochPremium[currentEpoch][strike] += premium;
    // Add to user epoch premium
    userEpochPremium[currentEpoch][userStrike] += premium;

    emit LogNewPurchase(currentEpoch, strike, msg.sender, amount, premium);

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
    require(exerciseEpoch < currentEpoch, "Exercise epoch must be in the past");

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
    ERC20PresetMinterPauser(epochStrikeTokens[exerciseEpoch][strike]).burnFrom(
      user,
      amount
    );

    // Update state to account for exercised options (amount of DPX used in exercising)
    totalTokenVaultExercises[exerciseEpoch] += PnL;

    // Transfer PnL to user
    dpx.safeTransfer(user, PnL);

    emit LogNewExercise(exerciseEpoch, strike, user, amount, PnL);

    return true;
  }

  /**
   * Allows anyone to call compound()
   * @return Whether compound was successful
   */
  function compound() public returns (bool) {
    if (currentEpoch == 0) {
      return false;
    }

    uint256 oldBalance = stakingRewards.balanceOf(address(this));
    uint256 rewards = stakingRewards.rewardsDPX(address(this));
    // Compound staking rewards
    stakingRewards.compound();
    // Update epoch balance
    totalEpochDpxBalance[currentEpoch] = stakingRewards.balanceOf(
      address(this)
    );
    emit LogCompound(
      currentEpoch,
      rewards,
      oldBalance,
      totalEpochDpxBalance[currentEpoch]
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
    require(withdrawEpoch < currentEpoch, "Withdraw epoch must be in the past");

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
    uint256 userStrikeDeposits = userEpochDeposits[withdrawEpoch][userStrike];
    require(
      userStrikeDeposits > 0,
      "User strike deposit amount must be greater than zero"
    );

    // Transfer DPX tokens to user
    userEpochDeposits[withdrawEpoch][userStrike] = 0;
    totalEpochStrikeDeposits[withdrawEpoch][strike] -= userStrikeDeposits;

    dpx.transfer(msg.sender, userStrikeDeposits);

    emit LogNewWithdrawForStrike(
      withdrawEpoch,
      strike,
      msg.sender,
      userStrikeDeposits
    );

    return true;
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
        lastDay.getDay() + 5 - lastDay.getDayOfWeek(),
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

      lastFridayOfMonth = BokkyPooBahsDateTimeLibrary.timestampFromDateTime(
        temp.getYear(),
        temp.getMonth(),
        temp.getDay() + 5 - temp.getDayOfWeek(),
        12,
        0,
        0
      );
    }
    return lastFridayOfMonth;
  }

  /**
   * Returns start and end times for an epoch
   * @param epoch Target epoch
   */
  function getEpochTimes(uint256 epoch)
    public
    view
    returns (uint256 start, uint256 end)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    return (
      epochStartTimes[epoch],
      getMonthlyExpiryFromTimestamp(epochStartTimes[epoch])
    );
  }

  /**
   * Returns epoch strikes array for an epoch
   * @param epoch Target epoch
   */
  function getEpochStrikes(uint256 epoch)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    return epochStrikes[epoch];
  }

  /**
   * Returns epoch strike tokens array for an epoch
   * @param epoch Target epoch
   */
  function getEpochStrikeTokens(uint256 epoch)
    public
    view
    returns (address[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    address[] memory _epochStrikeTokens = new address[](length);

    for (uint256 i = 0; i < length; i++) {
      _epochStrikeTokens[i] = epochStrikeTokens[epoch][epochStrikes[epoch][i]];
    }

    return _epochStrikeTokens;
  }

  /**
   * Returns total epoch strike deposits array for an epoch
   * @param epoch Target epoch
   */
  function getTotalEpochStrikeDeposits(uint256 epoch)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _totalEpochStrikeDeposits = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      _totalEpochStrikeDeposits[i] = totalEpochStrikeDeposits[epoch][
        epochStrikes[epoch][i]
      ];
    }

    return _totalEpochStrikeDeposits;
  }

  /**
   * Returns user epoch deposits array for an epoch
   * @param epoch Target epoch
   * @param user Address of the user
   */
  function getUserEpochDeposits(uint256 epoch, address user)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _userEpochDeposits = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      uint256 strike = epochStrikes[epoch][i];
      bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

      _userEpochDeposits[i] = userEpochDeposits[epoch][userStrike];
    }

    return _userEpochDeposits;
  }

  /**
   * Returns total epoch calls purchased array for an epoch
   * @param epoch Target epoch
   */
  function getTotalEpochCallsPurchased(uint256 epoch)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _totalEpochCallsPurchased = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      _totalEpochCallsPurchased[i] = totalEpochCallsPurchased[epoch][
        epochStrikes[epoch][i]
      ];
    }

    return _totalEpochCallsPurchased;
  }

  /**
   * Returns user epoch calls purchased array for an epoch
   * @param epoch Target epoch
   * @param user Address of the user
   */
  function getUserEpochCallsPurchased(uint256 epoch, address user)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _userEpochCallsPurchased = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      uint256 strike = epochStrikes[epoch][i];
      bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

      _userEpochCallsPurchased[i] = userEpochCallsPurchased[epoch][userStrike];
    }

    return _userEpochCallsPurchased;
  }

  /**
   * Returns total epoch premium array for an epoch
   * @param epoch Target epoch
   */
  function getTotalEpochPremium(uint256 epoch)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _totalEpochPremium = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      _totalEpochPremium[i] = totalEpochPremium[epoch][epochStrikes[epoch][i]];
    }

    return _totalEpochPremium;
  }

  /**
   * Returns user epoch premium array for an epoch
   * @param epoch Target epoch
   * @param user Address of the user
   */
  function getUserEpochPremium(uint256 epoch, address user)
    public
    view
    returns (uint256[] memory)
  {
    require(epoch > 0, "Epoch passed must be higher than 0");

    uint256 length = epochStrikes[epoch].length;
    uint256[] memory _userEpochPremium = new uint256[](length);

    for (uint256 i = 0; i < length; i++) {
      uint256 strike = epochStrikes[epoch][i];
      bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

      _userEpochPremium[i] = userEpochPremium[epoch][userStrike];
    }

    return _userEpochPremium;
  }

  /**
   * Update & Returns token's price in USD
   * @param _token Address of the token
   */
  function getUsdPrice(address _token) public returns (uint256) {
    return priceOracleAggregator.getPriceInUSD(_token);
  }

  /**
   * Returns token's price in USD
   * @param _token Address of the token
   */
  function viewUsdPrice(address _token) public view returns (uint256) {
    return priceOracleAggregator.viewPriceInUSD(_token);
  }

  function concatenate(string memory a, string memory b)
    internal
    pure
    returns (string memory)
  {
    return string(abi.encodePacked(a, b));
  }
}
