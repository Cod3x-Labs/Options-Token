// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ChainedOracle, IOracle} from "../src/oracles/ChainedOracle.sol";
import {ThenaOracle, IThenaPair} from "../src/oracles/ThenaOracle.sol";

contract ChainedOracleTest is Test {
    using FixedPointMathLib for uint256;

    ChainedOracle oracle;

    IOracle ORACLE_1;
    IOracle ORACLE_2;

    string MODE_RPC_URL = vm.envString("MODE_RPC_URL");
    
    address ICL_ADDRESS = 0x95177295A394f2b9B04545FFf58f4aF0673E839d;
    
    function setUp() public {
        vm.createSelectFork(MODE_RPC_URL);
        ORACLE_1 = ThenaOracle(0xDaA2c821428f62e1B08009a69CE824253CCEE5f9);
        ORACLE_2 = new ThenaOracle(IThenaPair(0x0fba984c97539B3fb49ACDA6973288D0EFA903DB), 0xDfc7C877a950e49D2610114102175A06C2e3167a, address(this), 1800, 0);
        
        IOracle[] memory oracles = new IOracle[](2);
        oracles[0] = ORACLE_1;
        oracles[1] = ORACLE_2;

        oracle = new ChainedOracle(oracles, 0x4200000000000000000000000000000000000006, ICL_ADDRESS, 0, address(this));
    }
    
    function test_calculatePrice() public {
        uint price_1 = ORACLE_1.getPrice();
        uint price_2 = ORACLE_2.getPrice();
        
        uint expectedPrice = price_1.mulWadUp(price_2);
        
        assertEq(expectedPrice, oracle.getPrice());
        emit log_named_decimal_uint("price", oracle.getPrice(), 18);
    }
}