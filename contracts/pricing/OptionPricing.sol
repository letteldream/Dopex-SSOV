// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { BlackScholes } from "../libraries/BlackScholes.sol";
import { ABDKMathQuad } from "../external/math/ABDKMathQuad.sol";

// Contracts
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract OptionPricing is Ownable {
  using SafeMath for uint256;

  // strike precision 10^9
  uint256 public constant strikePrecision = 1e8;

  // The max iv possible
  uint256 public ivCap;

  // All multipliers will be precision 1e8 (strike precision)
  struct Multipliers {
    uint256 callCurveMultiplier;
    uint256 putCurveMultiplier;
    uint256 callGrowthMultiplier;
    uint256 putGrowthMultiplier;
  }

  // The set of multipliers to be used
  Multipliers public multipliers;

  constructor(
    uint256 _ivCap,
    uint256 _callCurveMultiplier,
    uint256 _putCurveMultiplier,
    uint256 _callGrowthMultiplier,
    uint256 _putGrowthMultiplier
  ) {
    // Initialize ivCap
    ivCap = _ivCap;
    // Initialize multipliers
    multipliers.callCurveMultiplier = _callCurveMultiplier;
    multipliers.putCurveMultiplier = _putCurveMultiplier;
    multipliers.callGrowthMultiplier = _callGrowthMultiplier;
    multipliers.putGrowthMultiplier = _putGrowthMultiplier;
  }

  /*---- GOVERNANCE FUNCTIONS ----*/

  /// @notice updates iv cap for an option pool
  /// @param _ivCap the new iv cap
  /// @return whether iv cap was updated
  function updateIVCap(uint256 _ivCap) external onlyOwner returns (bool) {
    ivCap = _ivCap;

    return true;
  }

  /// @notice propose a new quote for multipliers
  /// @param _callCurveMultiplier call curve multiplier
  /// @param _putCurveMultiplier put curve multiplier
  /// @param _callGrowthMultiplier call growth multiplier
  /// @param _putGrowthMultiplier put growth multiplier
  /// @return whether the multiplier was updated
  function updateMultipliers(
    uint256 _callCurveMultiplier,
    uint256 _putCurveMultiplier,
    uint256 _callGrowthMultiplier,
    uint256 _putGrowthMultiplier
  ) external onlyOwner returns (bool) {
    multipliers.callCurveMultiplier = _callCurveMultiplier;
    multipliers.putCurveMultiplier = _putCurveMultiplier;
    multipliers.callGrowthMultiplier = _callGrowthMultiplier;
    multipliers.putGrowthMultiplier = _putGrowthMultiplier;

    return true;
  }

  /*---- VIEWS ----*/

  /**
   * @notice computes the option price (with liquidity multiplier)
   * @param isPut is put option
   * @param expiry expiry timestamp
   * @param strike strike price
   * @param lastPrice current price
   * @param baseIv baseIv
   */
  function getOptionPrice(
    bool isPut,
    uint256 expiry,
    uint256 strike,
    uint256 lastPrice,
    uint256 baseIv
  ) external view returns (uint256) {
    uint256 iv = getIV(baseIv, strike, lastPrice, expiry, isPut);

    uint256 timeToExpiry = expiry.sub(block.timestamp).div(864);

    return
      BlackScholes
        .calculate(
          isPut ? 1 : 0, // 0 - Put, 1 - Call
          lastPrice,
          strike,
          timeToExpiry, // Number of days to expiry mul by 100
          0,
          iv
        )
        .div(BlackScholes.DIVISOR);
  }

  /**
   * @notice returns the multiplied iv given the strike price
   * @param baseIv the base iv to be used
   * @param strike the strike price
   * @param lastPrice the last price of the base asset
   * @param expiry the expiry of the option
   * @param isPut whether the option is put or call option
   * @return the iv
   */
  function getIV(
    uint256 baseIv,
    uint256 strike,
    uint256 lastPrice,
    uint256 expiry,
    bool isPut
  ) public view returns (uint256) {
    uint256 curveMultiplier;
    uint256 growthMultiplier;

    if (isPut) {
      curveMultiplier = multipliers.putCurveMultiplier;
      growthMultiplier = multipliers.putGrowthMultiplier;
    } else {
      curveMultiplier = multipliers.callCurveMultiplier;
      growthMultiplier = multipliers.callGrowthMultiplier;
    }

    // percentageDifference is the difference in percentage of the strike price from the current price
    uint256 percentageDifference;

    if (strike > lastPrice) {
      percentageDifference = uint256(100).mul(
        (strike.sub(lastPrice).mul(strikePrecision).div(lastPrice))
      );
    } else {
      percentageDifference = uint256(100).mul(
        (lastPrice.sub(strike).mul(strikePrecision).div(lastPrice))
      );
    }

    percentageDifference = percentageDifference.div(strikePrecision);

    // timeToExpiry in days = timestamp (in sec) / 86400
    bytes16 timeToExpiry = ABDKMathQuad.div(
      ABDKMathQuad.fromUInt(expiry.sub(block.timestamp)),
      ABDKMathQuad.fromUInt(86400) // 86400 = seconds in a day
    );

    // Calculate the exponent = e ^ (percentageDifference / (curveMultiplier * timeToExpiry))
    bytes16 exponent = ABDKMathQuad.div(
      ABDKMathQuad.fromUInt(percentageDifference),
      ABDKMathQuad.mul(
        ABDKMathQuad.div(
          ABDKMathQuad.fromUInt(curveMultiplier),
          ABDKMathQuad.fromUInt(1e8)
        ),
        timeToExpiry
      )
    );

    // Calculate ivMultiple = 1 + ((Growth Multiplier * exponent) * (percentageDifference) ^ 2)
    bytes16 ivMultiple = ABDKMathQuad.add(
      ABDKMathQuad.fromUInt(1),
      ABDKMathQuad.mul(
        ABDKMathQuad.mul(
          ABDKMathQuad.div(
            ABDKMathQuad.fromUInt(growthMultiplier),
            ABDKMathQuad.fromUInt(1e8)
          ),
          ABDKMathQuad.exp(exponent)
        ),
        ABDKMathQuad.mul(
          ABDKMathQuad.fromUInt(percentageDifference),
          ABDKMathQuad.fromUInt(percentageDifference)
        )
      )
    );

    // Final iv is baseIv * ivMultiple
    uint256 iv = ABDKMathQuad.toUInt(
      ABDKMathQuad.mul(ABDKMathQuad.fromUInt(baseIv), ivMultiple)
    );

    if (iv > ivCap) {
      iv = ivCap;
    }

    return iv;
  }
}
