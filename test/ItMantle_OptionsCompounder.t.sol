// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.13;

import "./Common.sol";

import {BalancerOracle} from "../src/oracles/BalancerOracle.sol";
import {MockBalancerTwapOracle} from "../test/mocks/MockBalancerTwapOracle.sol";
// import {CErc20I} from "./strategies/interfaces/CErc20I.sol";
// import {Helper} from "./mocks/HelperFunctions.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
// import {IAToken} from "./strategies/interfaces/IAToken.sol";
// import {ReaperStrategyGranary, Externals} from "./strategies/ReaperStrategyGranary.sol";
import {OptionsCompounder} from "../src/OptionsCompounder.sol";
// import {MockedLendingPool} from "../test/mocks/MockedStrategy.sol";
import {ReaperSwapper, MinAmountOutData, MinAmountOutKind, IThenaRamRouter, ISwapRouter, UniV3SwapData} from "vault-v2/ReaperSwapper.sol";

contract ItMantleOptionsCompounder is Common {
    using FixedPointMathLib for uint256;

    /* Variable assignment (depends on chain) */
    uint256 constant FORK_BLOCK = 68452928;
    string MAINNET_URL = vm.envString("MANTLE_RPC_URL");

    /* Contract variables */
    OptionsCompounder optionsCompounder;
    // ReaperStrategyGranary strategy;
    IOracle oracle;

    address[] strategies;

    function setUp() public {
        /* Common assignments */
        ExchangeType exchangeType = ExchangeType.VeloSolid;
        nativeToken = IERC20(MANTLE_MNT);
        paymentToken = IERC20(MANTLE_MNT);
        underlyingToken = IERC20(MANTLE_CLEO);
        addressProvider = MANTLE_ADDRESS_PROVIDER;
        veloRouter = IThenaRamRouter(MANTLE_VELO_ROUTER);
        veloFactory = MANTLE_VELO_FACTORY;

        /* Setup network */
        uint256 fork = vm.createFork(MAINNET_URL, FORK_BLOCK);
        vm.selectFork(fork);

        /* Setup accounts */
        fixture_setupAccountsAndFees(3000, 7000);
        vm.deal(address(this), AMOUNT * 3);
        vm.deal(owner, AMOUNT * 3);

        /* Setup roles */
        address[] memory strategists = new address[](1);
        strategists[0] = strategist;

        /* Variables */

        /**
         * Contract deployments and configurations ***
         */

        /* Reaper deployment and configuration */
        reaperSwapper = new ReaperSwapper();
        tmpProxy = new ERC1967Proxy(address(reaperSwapper), "");
        reaperSwapper = ReaperSwapper(address(tmpProxy));
        reaperSwapper.initialize(strategists, address(this), address(this));

        /* Configure swapper */
        fixture_updateSwapperPaths(exchangeType);

        /* Oracle mocks deployment */
        oracle = fixture_getMockedOracle(exchangeType);

        /* Option token deployment */
        vm.startPrank(owner);
        optionsToken = new OptionsToken();
        tmpProxy = new ERC1967Proxy(address(optionsToken), "");
        optionsTokenProxy = OptionsToken(address(tmpProxy));
        optionsTokenProxy.initialize("TIT Call Option Token", "oTIT", tokenAdmin);

        /* Exercise contract deployment */
        SwapProps memory swapProps = fixture_getSwapProps(exchangeType, 1000);
        uint256 minAmountToTriggerSwap = 1e5;
        exerciser = new DiscountExercise(
            optionsTokenProxy,
            owner,
            paymentToken,
            underlyingToken,
            oracle,
            PRICE_MULTIPLIER,
            INSTANT_EXIT_FEE,
            minAmountToTriggerSwap,
            treasuries,
            feeBPS,
            swapProps
        );
        /* Add exerciser to the list of options */

        optionsTokenProxy.setExerciseContract(address(exerciser), true);

        /* Strategy deployment */
        strategies.push(makeAddr("strategy"));
        optionsCompounder = new OptionsCompounder();
        tmpProxy = new ERC1967Proxy(address(optionsCompounder), "");
        optionsCompounder = OptionsCompounder(address(tmpProxy));
        console.log("Initializing...");
        optionsCompounder.initialize(address(optionsTokenProxy), address(addressProvider), swapProps, oracle, strategies);

        vm.stopPrank();

        /* Prepare EOA and contracts for tests */
        console.log("Dealing payment token..");
        uint256 maxPaymentAmount = AMOUNT * 2;
        deal(address(nativeToken), address(this), maxPaymentAmount);

        console.log("Calculation max amount of underlying..");
        maxUnderlyingAmount = maxPaymentAmount.divWadUp(oracle.getPrice());
        console.log("Max underlying amount to distribute: ", maxUnderlyingAmount);
        deal(address(underlyingToken), address(exerciser), maxUnderlyingAmount);

        /* Set up contracts */
        paymentToken.approve(address(exerciser), type(uint256).max);
    }

    function test_mantleFlashloanPositiveScenario(uint256 amount) public {
        /* Test vectors definition */
        amount = bound(amount, maxUnderlyingAmount / 10, underlyingToken.balanceOf(address(exerciser)));
        uint256 minAmount = 5;

        /* Prepare option tokens - distribute them to the specified strategy 
        and approve for spending */
        fixture_prepareOptionToken(amount, address(optionsCompounder), strategies[0], optionsTokenProxy, tokenAdmin);

        /* Check balances before compounding */
        uint256 paymentTokenBalance = paymentToken.balanceOf(strategies[0]);

        // vm.startPrank(address(strategy));
        /* already approved in fixture_prepareOptionToken */
        vm.prank(strategies[0]);
        optionsCompounder.harvestOTokens(amount, address(exerciser), minAmount);
        // vm.stopPrank();

        /* Assertions */
        assertGt(paymentToken.balanceOf(strategies[0]), paymentTokenBalance + minAmount, "Gain not greater than 0");
        assertEq(optionsTokenProxy.balanceOf(address(optionsCompounder)), 0, "Options token balance in compounder is 0");
        assertEq(paymentToken.balanceOf(address(optionsCompounder)), 0, "Payment token balance in compounder is 0");
    }
}