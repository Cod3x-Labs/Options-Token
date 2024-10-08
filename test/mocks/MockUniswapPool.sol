// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.11;

import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

contract MockUniswapPool is IUniswapV3Pool {
    int56[2] cumulatives;
    address public token0;
    address public token1;

    function setCumulatives(int56[2] memory value) external {
        cumulatives = value;
    }

    function setToken0(address value) external {
        token0 = value;
    }

    function setToken1(address value) external {
        token1 = value;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        secondsAgos;
        secondsPerLiquidityCumulativeX128s;

        tickCumulatives = new int56[](2);
        tickCumulatives[0] = cumulatives[0];
        tickCumulatives[1] = cumulatives[1];
    }

    // mandatory overrides

    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {}

    function factory() external view override returns (address) {}

    function fee() external view override returns (uint24) {}

    function tickSpacing() external view override returns (int24) {}

    function maxLiquidityPerTick() external view override returns (uint128) {}

    function slot0()
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {}

    function feeGrowthGlobal0X128() external view override returns (uint256) {}

    function feeGrowthGlobal1X128() external view override returns (uint256) {}

    function protocolFees() external view override returns (uint128, uint128) {}

    function liquidity() external view override returns (uint128) {}

    function ticks(int24 tick)
        external
        view
        override
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {}

    function tickBitmap(int16 wordPosition) external view override returns (uint256) {}

    function positions(bytes32 key)
        external
        view
        override
        returns (uint128 _liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)
    {}

    function observations(uint256 index)
        external
        view
        override
        returns (uint32 blockTimestamp, int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128, bool initialized)
    {}

    function initialize(uint160 sqrtPriceX96) external override {}

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {}

    function collect(address recipient, int24 tickLower, int24 tickUpper, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        returns (uint128 amount0, uint128 amount1)
    {}

    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external override returns (uint256 amount0, uint256 amount1) {}

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96, bytes calldata data)
        external
        override
        returns (int256 amount0, int256 amount1)
    {}

    function flash(address recipient, uint256 amount0, uint256 amount1, bytes calldata data) external override {}

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external override {}

    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override {}

    function collectProtocol(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        override
        returns (uint128 amount0, uint128 amount1)
    {}
}
