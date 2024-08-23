// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {Owned} from "solmate/auth/Owned.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import "forge-std/console.sol";

/// @title Combined oracle for sourcing a price using multiple pools
/// @author zefram.eth/lookee/Eidolon
/// @notice This oracle uses two or more oracles that are queried in sequence;
/// i.e "pay WETH, get discounted ICL", but there is no liquid WETH/ICL pool:
/// 1st Oracle: ICL underlying/MODE payment; 2nd Oracle: MODE underlying/WETH payment.
contract ChainedOracle is IOracle, Owned {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    
    error ChainedOracle__IncompatibleOracles();
    error ChainedOracle__BelowMinPrice();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------
    
    event SetParams(uint256 minPrice);

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice List of oracles queried
    IOracle[] oracles;

    /// @notice The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    uint128 public minPrice;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(IOracle[] memory oracles_, address paymentToken_, address underlyingToken_, uint128 minPrice_, address owner_) Owned(owner_) {
        if (oracles_.length < 2) revert();
        // verify that each oracle matches the one before it
        (address lastPaymentToken, address lastUnderlyingToken) = oracles_[0].getTokens();
        (address currentPaymentToken, address currentUnderlyingToken) = oracles_[1].getTokens();

        // first token must be the underlying token
        if (lastUnderlyingToken != underlyingToken_) revert ChainedOracle__IncompatibleOracles();
        console.log(1);
        // each oracle must match the previous one
        if (currentUnderlyingToken != lastPaymentToken) revert ChainedOracle__IncompatibleOracles();
        console.log(2);

        // loop reserved for 3+ oracles
        for (uint256 i = 2; i < oracles_.length; i++) { // starts at second oracle
            lastPaymentToken = currentPaymentToken;
            lastUnderlyingToken = currentUnderlyingToken;
            (currentPaymentToken, currentUnderlyingToken) = oracles_[i].getTokens();
            // each oracle must match previous one
            if (currentPaymentToken != lastUnderlyingToken) revert ChainedOracle__IncompatibleOracles();
        console.log(3);
        }
        
        // check if last token is the underlying
        if (currentPaymentToken != paymentToken_) revert ChainedOracle__IncompatibleOracles();
        console.log(4);
        
        oracles = oracles_;
        minPrice = minPrice_;
    }

    /// -----------------------------------------------------------------------
    /// IOracle
    /// -----------------------------------------------------------------------

    /// @inheritdoc IOracle
    function getPrice() external view override returns (uint256 price) {
        /// -----------------------------------------------------------------------
        /// Computation
        /// -----------------------------------------------------------------------

        price = oracles[0].getPrice();
        
        for (uint256 i = 1; i < oracles.length; i++) {
            price = oracles[i].getPrice().mulWadUp(price);
        }

        if (price < minPrice) revert ChainedOracle__BelowMinPrice();
    }

    /// @inheritdoc IOracle
    function getTokens() external view override returns (address _paymentToken, address _underlyingToken) {
        (_paymentToken, ) = oracles[0].getTokens();
        (, _underlyingToken) = oracles[0].getTokens();
    }

    /// -----------------------------------------------------------------------
    /// Owner functions
    /// -----------------------------------------------------------------------

    /// @notice Updates the oracle parameters. Only callable by the owner.
    /// @param minPrice_ The minimum value returned by getPrice(). Maintains a floor for the
    /// price to mitigate potential attacks on the TWAP oracle.
    function setParams(uint128 minPrice_) external onlyOwner {
        minPrice = minPrice_;
        emit SetParams(minPrice_);
    }
}
