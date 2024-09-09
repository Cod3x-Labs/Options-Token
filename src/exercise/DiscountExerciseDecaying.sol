// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {Pausable} from "oz/security/Pausable.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {BaseExercise} from "../exercise/BaseExercise.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {OptionsToken} from "../OptionsToken.sol";

import {ExchangeType, SwapProps, SwapHelper} from "../helpers/SwapHelper.sol";

struct DiscountExerciseParams {
    uint256 maxPaymentAmount;
    uint256 deadline;
    bool isInstantExit;
}


/// @title Options Token Exercise Contract
/// @author @lookee, Eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract DiscountExerciseDecaying is BaseExercise, Pausable {
    /// Library usage
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// Errors
    error Exercise__SlippageTooHigh();
    error Exercise__PastDeadline();
    error Exercise__MultiplierOutOfRange();
    error Exercise__InvalidOracle();
    error Exercise__FeeGreaterThanMax();
    error Exercise__AmountOutIsZero();
    error Exercise__ZapMultiplierIncompatible();
    error Exercise__ExerciseWindowNotOpen();
    error Exercise__InvalidTimes();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);
    event SetMultiplier(uint256 indexed newMultiplier);
    event Claimed(uint256 indexed amount);
    event SetInstantFee(uint256 indexed instantFee);
    event SetMinAmountToTrigger(uint256 minAmountToTrigger);
    event SetConfigParams(uint256 startTime, uint256 endTime, uint256 startingMultiplier, uint256 multiplierDecay);

    struct ConfigParams {
        uint256 startTime;
        uint256 endTime;
        uint256 startingMultiplier;
        uint256 multiplierDecay;
    }

    /// Constants
    /// Immutable parameters

    /// @notice The token paid by the options token holder during redemption
    IERC20 public immutable paymentToken;

    /// @notice The underlying token purchased during redemption
    IERC20 public immutable underlyingToken;

    /// Storage variables

    /// @notice The oracle contract that provides the current price to purchase
    /// the underlying token while exercising options (the strike price)
    IOracle public oracle;

    /// @notice The multiplier applied to oracle price at startTime
    uint256 public startingMultiplier;

    /// @notice The total amount the multiplier will decay from the startingMultiplier by endTime
    uint256 public multiplierDecay;

    /// @notice The fee amount gathered in the contract to be swapped and distributed
    uint256 private feeAmount;

    /// @notice The time after which users can exercise their option tokens
    uint256 public startTime;

    /// @notice The time at which the price stops decaying
    uint256 public endTime;

    constructor(
        OptionsToken oToken_,
        address owner_,
        IERC20 paymentToken_,
        IERC20 underlyingToken_,
        IOracle oracle_,
        ConfigParams memory configParams_,
        address[] memory feeRecipients_,
        uint256[] memory feeBPS_
    ) BaseExercise(oToken_, feeRecipients_, feeBPS_) Owned(owner_) {
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;

        _setOracle(oracle_);
        _setConfigParams(configParams_);
    }

    /// External functions

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param from The user that is exercising their options tokens
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the purchased underlying tokens
    /// @param params Extra parameters to be used by the exercise function
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        override
        onlyOToken
        whenNotPaused
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        DiscountExerciseParams memory _params = abi.decode(params, (DiscountExerciseParams));
        return _exercise(from, amount, recipient, _params);
    }

    /// Owner functions

    /// @notice Sets the oracle contract. Only callable by the owner.
    /// @param oracle_ The new oracle contract
    function setOracle(IOracle oracle_) external onlyOwner {
        _setOracle(oracle_);
    }

    function setConfigParams(ConfigParams memory configParams_) external onlyOwner {
        _setConfigParams(configParams_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// Internal functions
    function _exercise(address from, uint256 amount, address recipient, DiscountExerciseParams memory params)
        internal
        virtual
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        // check if exercise window is open
        if (block.timestamp < startTime) revert Exercise__ExerciseWindowNotOpen();
        if (block.timestamp > params.deadline) revert Exercise__PastDeadline();
        // apply multiplier to price
        paymentAmount = getPaymentAmount(amount);
        if (paymentAmount > params.maxPaymentAmount) revert Exercise__SlippageTooHigh();
        // transfer payment tokens from user to the set receivers
        distributeFeesFrom(paymentAmount, paymentToken, from);
        // transfer underlying tokens to recipient
        _pay(recipient, amount);

        emit Exercised(from, recipient, amount, paymentAmount);
    }

    function _pay(address to, uint256 amount) internal {
        underlyingToken.safeTransfer(to, amount);
    }

    function _setConfigParams(ConfigParams memory configParams_) internal {
        // check that the end time is after the start time
        // if both are in the past that means we default to the max decay
        // if both are in the future we are disabling until the start time, then running a full window
        // if start is in the past and end is in the future, we are running a partial window from now until end
        if (configParams_.endTime > configParams_.startTime) {
            revert Exercise__InvalidTimes();
        }
        // check that startingMultiplier is less than 2 and greater than 0.1 and that startingMultiplier is greater than the decay
        if (
            configParams_.startingMultiplier > 2 * FixedPointMathLib.WAD || configParams_.startingMultiplier < FixedPointMathLib.WAD / 10
                || configParams_.startingMultiplier < configParams_.multiplierDecay
        ) {
            revert Exercise__MultiplierOutOfRange();
        }
        startTime = configParams_.startTime;
        endTime = configParams_.endTime;
        startingMultiplier = configParams_.startingMultiplier;
        multiplierDecay = configParams_.multiplierDecay;
        emit SetConfigParams(configParams_.startTime, configParams_.endTime, configParams_.startingMultiplier, configParams_.multiplierDecay);
    }

    function _setOracle(IOracle oracle_) internal {
        (address paymentToken_, address underlyingToken_) = oracle_.getTokens();
        if (paymentToken_ != address(paymentToken) || underlyingToken_ != address(underlyingToken)) {
            revert Exercise__InvalidOracle();
        }
        oracle = oracle_;
        emit SetOracle(oracle_);
    }


    /// View functions
    //IS IT OK TO MAKE THIS PUBLIC?? I THINK SO
    /// @notice Returns the amount of payment tokens required to exercise the given amount of options tokens.
    /// @param amount The amount of options tokens to exercise
    function getPaymentAmount(uint256 amount) public view returns (uint256 paymentAmount) {
        uint256 multiplier;
        // if the exercise window has not started, revert
        // if the exercise window has ended, use the max decay
        // otherwise, calculate the decay factor and apply it to the multiplier
        if (block.timestamp < startTime) {
            multiplier = startingMultiplier; // returns price based on startingMultiplier but cannot exercise still
        } else if (block.timestamp > endTime) {
            multiplier = startingMultiplier - multiplierDecay;
        } else {
            // decayFactor goes from 0 to 1 (WAD) from startTime to endTime
            uint256 decayFactor = (block.timestamp - startTime) * WAD / (endTime - startTime);
            // multiplier goes from startingMultiplier to startingMultiplier - multiplierDecay from startTime to endTime
            multiplier = startingMultiplier - multiplierDecay.mulWadUp(decayFactor);
        }
        paymentAmount = amount.mulWadUp(oracle.getPrice().mulWadUp(multiplier)); // check decimals
    }
}
