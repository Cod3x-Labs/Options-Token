// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "oz/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {BaseExercise} from "../exercise/BaseExercise.sol";
import {OptionsToken} from "../OptionsToken.sol";

/// @title Options Token Fixed Price Decaying Exercise Contract
/// @author @adamo, @funkornaut, Eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to a fixed
/// price set by owner.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract FixedExerciseDecaying is BaseExercise {
    /// Library usage
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    /// Errors
    error Exercise__ExerciseWindowNotOpen();
    error Exercise__ExerciseWindowClosed();
    error Exercise__InvalidTimes();
    error Exercise__InvalidPrices();

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetPriceAndTimeWindow(uint256 indexed price, uint256 indexed startTime, uint256 endTime);
    event SetTreasury(address indexed newTreasury);
    event SetPrice(uint256 indexed price);
    event SetConfigParams(uint256 startTime, uint256 endTime, uint256 startingPrice, uint256 priceDecay);

    struct ConfigParams {
        uint256 startTime;
        uint256 endTime;
        uint256 startingPrice;
        uint256 priceDecay;
    }

    /// Constants

    /// Immutable parameters

    /// @notice The token paid by the options token holder during redemption
    IERC20 public immutable paymentToken;

    /// @notice The underlying token purchased during redemption
    IERC20 public immutable underlyingToken;

    /// Storage variables

    /// @notice The time after which users can exercise their option tokens
    uint256 public startTime;

    /// @notice The time after which users can no longer exercise their option tokens
    uint256 public endTime;

    /// @notice The fixed token starting price, set by the owner
    uint256 public startingPrice;

    /// @notice The fixed token amount to decay from startingPrice, set by the owner
    uint256 public priceDecay;

    constructor(
        OptionsToken oToken_,
        address owner_,
        IERC20 paymentToken_,
        IERC20 underlyingToken_,
        ConfigParams memory configParams_,
        address[] memory feeRecipients_,
        uint256[] memory feeBPS_
    ) BaseExercise(oToken_, feeRecipients_, feeBPS_) Owned(owner_) {
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;

        _setConfigParams(configParams_);
    }

    /// External functions

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @param from The user that is exercising their options tokens
    /// @param amount The amount of options tokens to exercise
    /// @param recipient The recipient of the purchased underlying tokens
    /// @param params Extra parameters to be used by the exercise function
    function exercise(address from, uint256 amount, address recipient, bytes memory params)
        external
        virtual
        override
        onlyOToken
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        return _exercise(from, amount, recipient, params);
    }

    /// Owner functions

    /// @notice Set the prices and time window for the exercise contract
    /// @param configParams_ The new configuration parameters
    function setConfigParams(ConfigParams memory configParams_) external onlyOwner {
        _setConfigParams(configParams_);
    }

    /// Internal functions

    function _setConfigParams(ConfigParams memory configParams_) internal {
        // check that the end time is after the start time
        // if both are in the past that means we default to the max decay
        // if both are in the future we are disabling until the start time, then running a full window
        // if start is in the past and end is in the future, we are running a partial window from now until end
        if (configParams_.endTime < configParams_.startTime) {
            revert Exercise__InvalidTimes();
        }

        if (configParams_.priceDecay > configParams_.startingPrice) {
            revert Exercise__InvalidPrices();
        }

        startTime = configParams_.startTime;
        endTime = configParams_.endTime;
        startingPrice = configParams_.startingPrice;
        priceDecay = configParams_.priceDecay;
        emit SetConfigParams(startTime, endTime, startingPrice, priceDecay);

    }
    

    function _exercise(address from, uint256 amount, address recipient, bytes memory params)
        internal
        virtual
        returns (uint256 paymentAmount, address, uint256, uint256)
    {
        // check if exercise window is open
        if (block.timestamp < startTime) revert Exercise__ExerciseWindowNotOpen();

        // decode params if needed

        paymentAmount = getPaymentAmount(amount);

        // transfer payment tokens from user to the set receivers
        distributeFeesFrom(paymentAmount, paymentToken, from);
        // transfer underlying tokens to recipient
        _pay(recipient, amount);

        emit Exercised(from, recipient, amount, paymentAmount);
    }

    function _pay(address to, uint256 amount) internal {
        underlyingToken.safeTransfer(to, amount);
    }

    /// View functions

    //IS IT OK TO MAKE THIS PUBLIC?? I THINK SO
    /// @notice Returns the amount of payment tokens required to exercise the given amount of options tokens.
    /// @param amount The amount of options tokens to exercise
    function getPaymentAmount(uint256 amount) public view returns (uint256 paymentAmount) {
        uint256 decayedPrice;
        if (block.timestamp < startTime) {
            decayedPrice = startingPrice; // returns startingPrice but cannot exercise still
        } else if (block.timestamp > endTime) {
            decayedPrice = startingPrice - priceDecay;
        } else {
            uint256 decayFactor = (block.timestamp - startTime) * FixedPointMathLib.WAD / (endTime - startTime); //out of WAD, will be near 1e18 (1) at the end of the time window, will be near 0 at start
            decayedPrice = startingPrice - decayFactor.mulWadUp(priceDecay); // check decimals
        }
        paymentAmount = amount.mulWadUp(decayedPrice); // check decimals
    }
}
