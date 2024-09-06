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

struct ConstructorParams {
    uint256 startTime_;
    uint256 endTime_;
    uint256 maxDecay_;

}

/// @title Options Token Exercise Contract
/// @author @lookee, @eidolon
/// @notice Contract that allows the holder of options tokens to exercise them,
/// in this case, by purchasing the underlying token at a discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals.
contract DiscountExercise is BaseExercise, Pausable {
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

    /// Events
    event Exercised(address indexed sender, address indexed recipient, uint256 amount, uint256 paymentAmount);
    event SetOracle(IOracle indexed newOracle);
    event SetTreasury(address indexed newTreasury);
    event SetMultiplier(uint256 indexed newMultiplier);
    event Claimed(uint256 indexed amount);
    event SetInstantFee(uint256 indexed instantFee);
    event SetMinAmountToTrigger(uint256 minAmountToTrigger);

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

    /// @notice The multiplier applied to the TWAP value. Encodes the discount of
    /// the options token. Uses 4 decimals.
    uint256 public multiplier;

    /// @notice The fee amount gathered in the contract to be swapped and distributed
    uint256 private feeAmount;

    /// @notice The time after which users can exercise their option tokens
    uint256 public startTime;

    /// @notice The time at which the price stops decaying
    uint256 public endTime;

    /// @notice The maximum decay of the price
    uint256 public maxDecay;

    constructor(
        OptionsToken oToken_,
        address owner_,
        IERC20 paymentToken_,
        IERC20 underlyingToken_,
        IOracle oracle_,
        uint256 multiplier_,
        address[] memory feeRecipients_,
        uint256[] memory feeBPS_
    ) BaseExercise(oToken_, feeRecipients_, feeBPS_) Owned(owner_) {
        paymentToken = paymentToken_;
        underlyingToken = underlyingToken_;

        _setOracle(oracle_);
        _setMultiplier(multiplier_);

        emit SetOracle(oracle_);
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

    function _setOracle(IOracle oracle_) internal {
        (address paymentToken_, address underlyingToken_) = oracle_.getTokens();
        if (paymentToken_ != address(paymentToken) || underlyingToken_ != address(underlyingToken)) {
            revert Exercise__InvalidOracle();
        }
        oracle = oracle_;
        emit SetOracle(oracle_);
    }

    /// @notice Sets the discount multiplier.
    /// @param multiplier_ The new multiplier
    function setMultiplier(uint256 multiplier_) external onlyOwner {
        _setMultiplier(multiplier_);
    }

    function _setMultiplier(uint256 multiplier_) internal {
        if (
            multiplier_ > FEE_DENOMINATOR * 2 // over 200%
                || multiplier_ < FEE_DENOMINATOR / 10 // under 10%
        ) revert Exercise__MultiplierOutOfRange();
        multiplier = multiplier_;
        emit SetMultiplier(multiplier_);
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

    /// View functions
    //IS IT OK TO MAKE THIS PUBLIC?? I THINK SO
    /// @notice Returns the amount of payment tokens required to exercise the given amount of options tokens.
    /// @param amount The amount of options tokens to exercise
    function getPaymentAmount(uint256 amount) public view returns (uint256 paymentAmount) {
        uint256 decayFactor = (block.timestamp - startTime) * WAD / (endTime - startTime); //out of DENOM, will be near 1e18 (1) at the end of the time window, will be near 0 at start
        uint256 decayedPrice = (decayFactor > maxDecay) ? (price - price.mulWadUp(maxDecay)) : (price - price.mulWadUp(decayFactor));
        paymentAmount = amount.mulWadUp(oracle.getPrice().mulDivUp(multiplier, FEE_DENOMINATOR));
    }
}
