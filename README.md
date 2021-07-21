# DPX Single Staking Option Vaults

## Working

Users can lock in DPX into this Option Vault. Option Vault has a monthly expiry. People deposit for every epoch. No auto roll over. All the deposited DPX gets staked into the SSF.. Since a single address stakes the DPX we can call a bot every certain frequency to auto compound the DPX in the SSF Allows calls to be exercised from the vault by purchasers prior to expiry.

## Functions

- `bootstrap()` This will bootstrap the pool for the month. Strikes are passed. This will auto create doTokens for the monthly expiries and strikes. This will also deposit all the DPX from user deposits into the SSF.
- `deposit()` Allows users to deposit DPX into the option vault, while selecting the different strikes available, that they want to provide liquidity for. Arguments will be DPX amount to deposit, array of strikes, array of %s for liquidity to provide for each strike. This function will update global vars which track the liquidity for each strike currently available.
- `purchase()` Allows a user to purchase options from the vault from the strikes available. Use the current OptionPricing contract to get pricing. Will need the RV of DPX on chain. Use oracles for this. doTokens will be minted to the user.
- `exercise()` This will calculate the PnL for the user. Withdraw the PnL in DPX from the SSF and transfer it to the user. Will also the burn the doTokens from the user.
- `compound()` Calls compound for the Option Vault in the single staking DPX farming contract. This will increment the total deposited DPX in the vault adding liquidity for all the strikes.
- `withdraw()` Lets a user withdraw his share of DPX from the vault for an epoch. This will only work when the epoch has expired (meaning all options minted from the pool have either expired or been exercised). This will withdraw the users share from the SSF and return it to him.

## For local network fork and test

1. `npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/********`
2. `npx hardhat test --network localhost`
