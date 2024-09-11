# **Table of content**
- [Description](#description)
  - [OptionsToken](#optionstoken)
  - [OptionsCompounder](#optionscompounder)
- [Installation](#installation)
  - [Local Development](#local-development)
- [Testing](#testing)
  - [Dynamic](#dynamic)
  - [Static](#static)
- [Deployment](#deployment)
- [Checklist](#checklist)
- [Frontend integration](#frontend-integration)



# Description 
## OptionsToken

An options token representing the right to exercise any one of the whitelisted exercise contracts, allowing the user to receive different forms of discounted assets in return for the appropriate payment. The option does not expire. The options token receives user input and a specified exercise contract address, passing through to the exercise contract to execute the option. We fork https://github.com/timeless-fi/options-token, which is a simple implementation of an option for discounted tokens at an adjusted oracle rate. Here, we divorce the exercise functionality from the token contract, and allow an admin to whitelist and fund exercise contracts as the desired. We also implement more potential oracle types, and make several other minor changes.

We want to ensure there are no attacks on pricing in DiscountExercise, atomically or otherwise, in each oracle implementation.  We want to ensure users will never pay more than maxPaymentAmount. When properly specified, this should ensure users experience no more deviation in price than they specify.

Given the nature of this token, it is fine for the admin to have some centralized permissions (admin can mint tokens, admin is the one who funds exercise contracts, etc).  The team is responsible for refilling the exercise contracts. We limit the amount of funds we leave in an exercise contract at any given time to limit risk.  

### Flow of an Option Token Exercise (Ex. Discount Exercise)

The user will always interact with the OptionsToken itself, and never with any exercise contract directly.

#### ZAP
1. User calls exercise on the OptionsToken, specifying their desired exercise contract and encoding exercise parameters
2. OptionsToken validates the exercise contract.
3. DiscountExercise decodes the parameters for the exercise function on the chosen exercise contract, and calls the specified function. In the case of zapping in DiscountExercise, the parameters are maxPaymentAmount, deadline, and isInstantExit set to true.
4. OptionsTokens are burnt.
5. A penalty fee in the form of underlying tokens (available in the contract) is calculated, then conditionally swapped to the desired token and distributed to the fee recipients.
    - Swapping and distribution occur only when the fee amount exceeds a specified trigger to avoid swapping small amounts.
    - The transaction reverts if the minimal desired amount of desired tokens is not obtained.
6. The underlying tokens available in the DiscountExercise contract are sent to the user. The amount of underlying tokens is discounted by the multiplier and reduced by the penalty fee.

#### REDEEM
1. The user approves OptionsToken the amount of Payment Token they wish to spend
2. User calls exercise on the OptionsToken, specifying their desired exercise contract and encoding exercise parameters
3. OptionsToken validates the exercise contract, decodes the parameters for the exercise function on the exercise contract of choice, and calls said function. In the case of DiscountExercise, the params are maxPaymentAmount, deadline and isInstantExit set to false.
4. oTokens are burnt, WETH is sent to the treasury, and underlyingTokens, discounted by the multiplier, are sent to the user exercising
    - Can be priced using balancer, thena, univ3 twap oracles
    - Reverts above maxPaymentAmount or past deadline

## OptionsCompounder

The Compounder platform facilitates the utilization of flash loans to exercise the option, enabling the acquisition of the underlying token at a discounted rate via payment token.

### Flow of an Options Compounder (Ex. Discount Exercise) - strategy usage

1. Admin configures swap paths, oracles, initializer args, etc
2. Strategy has an oToken balance
3. Keeper calls harvestOTokens
4. Calculate Payment Amount from Discount Exercise given oToken balance
5. Flashloan the necessary amount of funds to exercise in paymentToken
6. Callback from flashloan is called
    - oTokens are exercised using paymentToken that was flash loaned
    - Underlying token is received by the strategy
    - Calculate minAmountOut by directly querying the same oracle consumed by the DiscountExercise we interact with
    - Swap entire amount into payment token to repay flashloan
    - Assess profitability in units of paymentToken, swap profits to want of the strategy if not same token as paymentToken
    - Emit event that reflects the oTokens compounded

# Installation

To install with [DappTools](https://github.com/dapphub/dapptools):

```
dapp install timeless-fi/options-token
```

To install with [Foundry](https://github.com/gakonst/foundry):

```
forge install timeless-fi/options-token
```

## Local development

This project uses [Foundry](https://github.com/gakonst/foundry) as the development framework.

### Dependencies

```
forge install
```

### Compilation

```
forge build
```

# Testing

## Dynamic

```
forge test
```

`--report lcov` - coverage which can be turned on in code using "Coverage Gutters"

## Static 

`slither . --include-path src/<targetFile>`

`--checklist` - report in md

`--print inheritance-graph` - generate inheritance graph in xdot

`xdot inheritance-graph.dot` - open inheritance graph

# Deployment

Inside `./scripts` there is "config.json" where can be defined deployment configurations.
You can choose which contract to deploy by adding/removing string in CONTRACTS_TO_DEPLOY. If some contracts are removed from CONTRACTS_TO_DEPLOY, there must be defined the address for already existing contract on the chain (example: SWAPPER, OPTIONS_COMPOUNDER).
There are 2 deployment scripts. One is for swapper and paths updates and second for all optionsToken infra (swapper address must be passed here).

## Examples of config.json
### All contracts to deploy
```
{
  "VERSION": "1.1.0",
  "OWNER": <OWNER ADDRESS>,
  "ORACLE_SOURCE": <PRICE TWAP ORACLE>,
  "ORACLE_SECS": 1800,
  "ORACLE_MIN_PRICE": 10000000,
  "OT_NAME": "ICL Call Option Token",
  "OT_SYMBOL": "oICL",
  "OT_PAYMENT_TOKEN": "0xDfc7C877a950e49D2610114102175A06C2e3167a",
  "OT_UNDERLYING_TOKEN": "0x95177295a394f2b9b04545fff58f4af0673e839d",
  "OT_TOKEN_ADMIN": "0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5",
  "VELO_ROUTER": "0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45",
  "ADDRESS_PROVIDER": "0xEDc83309549e36f3c7FD8c2C5C54B4c8e5FA00FC",
  "MULTIPLIER": 5000,
  "FEE_RECIPIENTS": [
    <TREASURY>
  ],
  "FEE_BPS": [
    10000
  ],
  "STRATS": [
    <STRATEGY ADDRESS>
  ],
  "INSTANT_EXIT_FEE": 1000,
  "MIN_AMOUNT_TO_TRIGGER_SWAP": 1e15,
  "CONTRACTS_TO_DEPLOY": [],
  "SWAPPER": "0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53",
  "DISCOUNT_EXERCISE": "0xcb727532e24dFe22E74D3892b998f5e915676Da8",
  "OPTIONS_TOKEN": "0x3B6eA0fA8A487c90007ce120a83920fd52b06f6D",
  "OPTIONS_COMPOUNDER": "0xf6cf2065C35595c12B532e54ACDe5A4597e32e6e",
  "ORACLE": "0xDaA2c821428f62e1B08009a69CE824253CCEE5f9"
}
```
### Only configure options compounder (no deployments)
```
{
  "VERSION": "1.1.0",
  "OWNER": <OWNER ADDRESS>,
  "ORACLE_SOURCE": <PRICE TWAP ORACLE>,
  "ORACLE_SECS": 1800,
  "ORACLE_MIN_PRICE": 10000000,
  "OT_NAME": "ICL Call Option Token",
  "OT_SYMBOL": "oICL",
  "OT_PAYMENT_TOKEN": "0xDfc7C877a950e49D2610114102175A06C2e3167a",
  "OT_UNDERLYING_TOKEN": "0x95177295a394f2b9b04545fff58f4af0673e839d",
  "OT_TOKEN_ADMIN": "0xF29dA3595351dBFd0D647857C46F8D63Fc2e68C5",
  "VELO_ROUTER": "0x3a63171DD9BebF4D07BC782FECC7eb0b890C2A45",
  "ADDRESS_PROVIDER": "0xEDc83309549e36f3c7FD8c2C5C54B4c8e5FA00FC",
  "MULTIPLIER": 5000,
  "FEE_RECIPIENTS": [
    <TREASURY>
  ],
  "FEE_BPS": [
    10000
  ],
  "STRATS": [
    <STRATEGY ADDRESS>
  ],
  "INSTANT_EXIT_FEE": 1000,
  "MIN_AMOUNT_TO_TRIGGER_SWAP": 1e15,
  "CONTRACTS_TO_DEPLOY": [
    "OptionsToken",
    "DiscountExercise",
    "ThenaOracle"
  ],
  "SWAPPER": "0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53",
  "DISCOUNT_EXERCISE": "undefined",
  "OPTIONS_TOKEN": "undefined",
  "OPTIONS_COMPOUNDER": "undefined",
  "ORACLE": "undefined"
}
```

# Checklist

## Internal Audit Checklist

- [x]  All functionality that touches funds can be paused
- [ ]  Pause function called by 2/7 Guardian
- [ ]  Guardian has 7 members globally dispersed
- [x]  Arithmetic errors
- [x]  Re-entrancy
- [x]  Flashloans
- [x]  Access Control

- [x]  (N/A) Unchecked External Calls
- [x]  (N/A) Account abstraction/multicall issues 
- [x]  Static analysis -> Slither
  - [x]  [Discount-Exercise](#discount-exercise-slither)
  - [x]  [Options-Compounder](#options-compounder-slither)
  - [x]  [Options-Token](#options-token-slither)
  - [x]  [Thena-Oracle](#thena-oracle-slither)
  - [x]  [Base-Exercise](#base-exercise-slither)

## Pre-deployment Checklist

- [x]  Contracts pass all tests
- [x]  Contracts deployed to testnet
  - [x]  [DiscountExercise](https://explorer.mode.network/address/0xcb727532e24dFe22E74D3892b998f5e915676Da8?tab=contract)
  - [x]  [ReaperSwapper](https://explorer.mode.network/address/0x63D170618A8Ed1987F3CA6391b5e2F6a4554Cf53?tab=contract)
  - [x]  [VeloOracle](https://explorer.mode.network/address/0xDaA2c821428f62e1B08009a69CE824253CCEE5f9?tab=contract)
  - [x]  [OptionsToken](https://explorer.mode.network/address/0x3B6eA0fA8A487c90007ce120a83920fd52b06f6D?tab=contract)
  - [ ]  [OptionsCompounder](https://explorer.mode.network/address/0xf6cf2065C35595c12B532e54ACDe5A4597e32e6e?tab=contract)
- [x]  Unchecked External Calls
- [ ]  Account abstraction/multicall issues
- [x]  USE SLITHER

- [x]  Does this deployment have access to funds, either directly or indirectly (zappers, leveragers, etc.)?

Minimum security if Yes:

- [x]  Internal Audit (not the author, minimum 1x Junior review + minimum 1x Senior review)
- [x]  External Audit (impact scope)
  - [x]  [OptionsToken zapping feature scope](https://docs.google.com/document/d/1HrmXSEKuBK5U9Ix8ZSkAYf2VEYwxZ17piOjhjY4XPzs/edit?usp=drive_link)
  - [x]  [OptionsToken zapping feature audit](https://drive.google.com/file/d/1kbYnVN1HJrpllkMXXb4mmwLeU361YASG/view?usp=drive_link)
  - [x]  [OptionsCompounder integration scope](https://docs.google.com/document/d/1eKcyiVvmux2wv2P92qLQLSYIgbD-qETurHObyhOLh8Y/edit?usp=drive_link)
  - [x]  [OptionsCompounder integration audit](https://drive.google.com/file/d/1GR0Jnxo9Txa6sJ8aM_mP4xBfaBJ9UNG2/view)

Action items in support of deployment:

- [ ]  Minimum two people present for deployment
- [x]  All developers who worked on and reviewed the contract should be included in the readme
  - Developers involved: xRave110 (change owner), Eidolon (reviewer), Zokunei (reviewer), Goober (reviewer), Beirao (reviewer)
- [ ]  Documentation of deployment procedure if non-standard (i.e. if multiple scripts are necessary)  

# Frontend Integration

Frontend shall allow to go through 3 different scenarios:
- Pay [PaymentTokens](#paymenttoken) to [**redeem**](#redeem-flow) [UnderlyingTokens](#underlyingtoken) from OptionsTokens
- [**Zap**](#zap-flow) OptionsTokens into the [UnderlyingTokens](#underlyingtoken)
- [**Claim**](#claim-flow---optional) not exercised [UnderlyingTokens](#underlyingtoken) (due to lack of funds in exercise contract) -> this is probably optional frontend feature

## Redeem flow
 - Standard ERC20 approve action on [PaymentToken](#paymenttoken) 
   - Note: `getPaymentAmount(uint256 amount)` interface may be usefull to get correct amount of PaymentToken needed.
 - Exercise optionsToken with following parameters:
   - amount of options tokens to spend (defined by user)
   - recipient of the [UnderlyingTokens](#underlyingtoken) transferred during exercise (user address)
   - option of the exercise -> it is DiscountExercise contract address
   - encoded params:
     - maxPaymentAmount - calculated maximal payment amount (amount * price * multiplier). Price can be get from oracle contract using interface `getPrice()`. Multiplier can be get from DiscountExercise contract using interface `multiplier()`
     - deadline - current block timestamp
     - isInstantExit - determines whether it is redeem (false) or zap (true) action. **Shall be hardcoded to false.**
 - Events emitted:
   - `Exercise(address indexed sender, address indexed recipient, uint256 amount, address data0, uint256 data1, uint256 data2)` - from OptionsToken contract. data0, data1, data2 - are not used in this case.
   - `Exercised(from, recipient, underlyingAmount, paymentAmount)` from DiscountExercise contract
 - Note: Amount of [UnderlyingTokens](#underlyingtoken) to receive from redeeming is the same amount that is specified for optionsTokens.

## Zap flow
 - Call `exercise(uint256 amount, address recipient, address option, bytes calldata params)` from  optionsToken contract with following parameters:
   - amount of options tokens to spend (defined by user)
   - recipient of the [UnderlyingTokens](#underlyingtoken) transferred during exercise (user address)
   - option of the exercise -> it is DiscountExercise contract address
   - encoded params:
     - maxPaymentAmount - calculated maximal payment amount (amount * price * multiplier). Price can be get from oracle contract using interface `getPrice()`. Multiplier can be get from DiscountExercise contract using interface `multiplier()`
     - deadline - current block timestamp
     - isInstantExit - determines whether it is redeem (false) or zap (true) action. **Shall be hardcoded to true.**
 - Events emitted:
   - `Exercise(address indexed sender, address indexed recipient, uint256 amount, address data0, uint256 data1, uint256 data2)` - from OptionsToken contract. data0, data1, data2 - are not used in this case.
   - `Exercised(from, recipient, underlyingAmount, paymentAmount)` from DiscountExercise contract
 - Note: Amount of [UnderlyingTokens](#underlyingtoken) to receive from zapping is: amountOfOTokens * (1 - multiplier) * (1 - instantExitFee). Everything is denominated in BPS (10 000). InstantExitFee can be get by calling `instantExitFee()`.
 - Note: `getPaymentAmount(uint256 amount)` interface may be usefull to get correct amount of PaymentToken needed.
 - Note: Usually swap action happens here so standard events for swapping are here, but contract handles all actions like approvals etc

## Claim flow - optional
- Call `claim(address to)` with address of recipient of the [UnderlyingTokens](#underlyingtoken) transferred during claiming process
- `Claimed(amount)` event is emitted

## Changelog
Main change between version 1.0.0 deployed on Harbor is the zap feature which requires additional variable in `params` argument (`isInstantExit`) of the `exercise(uint256 amount, address recipient, address option, bytes calldata params)` interface. 
Now frontend shall allow to obtain [UnderlyingTokens](#underlyingtoken) in two ways (redeem and zap).

## Legend
### PaymentToken
Token used to pay for exercising options token. Ironclad -> MODE, Harbor -> WBNB
### UnderlyingToken
Token which can be obtained from exercising. Ironclad -> ICL, Harbor -> HBR

