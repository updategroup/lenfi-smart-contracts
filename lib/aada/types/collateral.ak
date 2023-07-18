use aada/types.{AssetClass, POSIXTime}
use aada/types/pool
use aiken/transaction.{OutputReference}
use aiken/transaction/value.{AssetName}

pub type CollateralDatum {
  pool_nft_name: AssetName,
  loan_cs: AssetClass,
  loan_amount: Int,
  pool_config: pool.Config,
  collateral_cs: AssetClass,
  collateral_amount: Int,
  interest_rate: Int,
  deposit_time: POSIXTime,
  borrower_tn: AssetName,
  oracle_collateral_nft: AssetClass,
  // Now I'm not sure if we need oracle NFTs here
  oracle_loan_nft: AssetClass,
  // tagging
  tag: Option<OutputReference>,
}
