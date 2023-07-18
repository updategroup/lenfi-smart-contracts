use aada/types.{AssetClass, POSIXTime}

pub type Datum {
  oracle_parameters: OracleParameters,
  token_a_amount: Int,
  // if we turn this into a list (for medians), we should fix size for safety.
  token_b_amount: Int,
  // similarly.
  expiration_time: Int,
  maturity_time: Int,
}

pub type OracleParameters {
  pool_nft_cs: AssetClass,
  oracle_nft_cs: AssetClass,
  token_a_cs: AssetClass,
  token_b_cs: AssetClass,
}

pub type OracleSpendRedeemer {
  action: OracleActions,
}

pub type OracleMintRedeemer {
  request_expiration_time: POSIXTime,
}

pub type OracleActions {
  OracleUpdate(Int)
}
