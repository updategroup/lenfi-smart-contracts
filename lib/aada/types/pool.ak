use aada/types.{AssetClass}
use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Address}
use aiken/transaction/value.{AssetName}

pub type Redeemer {
  action: Action,
  config_ref: OutputReference,
  order: Option<OutputReference>,
}

pub type Action {
  Transition { value_delta: Int }
  Borrow {
    loan_amount: Int,
    collateral_amount: Int,
    borrower_tn: AssetName,
    interest_rate: Int,
  }
  CloseLoan { loan_amount: Int, interest_amount: Int }
  PayFee { fee: Int }
  Destroy
}

pub type Datum {
  params: Constants,
  balance: Int,
  lent_out: Int,
  total_lp_tokens: Int,
}

pub type Constants {
  collateral_address: Address,
  loan_cs: AssetClass,
  collateral_cs: AssetClass,
  oracle_collateral_nft: AssetClass,
  oracle_loan_nft: AssetClass,
  lp_token: AssetClass,
  pool_nft_name: AssetName,
  pool_config_assetname: AssetName,
}

pub type Config {
  liquidation_threshold: Int,
  initial_collateral_ratio: Int,
  pool_fee: Int,
  loan_fee_details: PlatformFeeDetails,
}

pub type PlatformFeeDetails {
  tier_1_fee: Int,
  tier_1_threshold: Int,
  tier_2_fee: Int,
  tier_2_threshold: Int,
  tier_3_fee: Int,
  tier_3_threshold: Int,
  liquidation_fee: Int,
  platform_fee_collector_address: Address,
}
