use aada/nft.{NFTRedeemer, check_uniqueness}
use aada/rats
use aada/types.{AssetClass}
use aada/types/oracle.{OracleMintRedeemer,
  OracleParameters, OracleSpendRedeemer}
use aada/utils
use aiken/interval.{Finite}
use aiken/transaction.{InlineDatum, Mint, ScriptContext, Transaction}
use aiken/transaction/value.{quantity_of}

// Take Minswap pool token and mint new Referencable oracle NFT
validator {
  fn oracle_spend_validator(
    oracle_datum: oracle.Datum,
    _oracle_redeemer: OracleSpendRedeemer,
    ctx: ScriptContext,
  ) {
    let oracle.Datum {
      oracle_parameters,
      maturity_time: old_maturity_time,
      token_a_amount: old_token_a_amount,
      token_b_amount: old_token_b_amount,
      ..
    } = oracle_datum
    let OracleParameters {
      pool_nft_cs: AssetClass(pool_policy, pool_asset),
      token_a_cs: AssetClass(token_a_policy, token_a_name),
      token_b_cs: AssetClass(token_b_policy, token_b_name),
      oracle_nft_cs: AssetClass(oracle_nft_policy, oracle_nft_name),
    } = oracle_parameters
    // Find an NFT in the DEX pool
    let dex_ref_input =
      utils.get_input_by_nft(
        ctx.transaction.reference_inputs,
        pool_policy,
        pool_asset,
      )
    // This is the an avg of current price and previous averaged price
    let token_a_amount =
      quantity_of(dex_ref_input.output.value, token_a_policy, token_a_name) + old_token_a_amount
        |> rats.div_int(2)
        |> rats.truncate
    let token_b_amount =
      quantity_of(dex_ref_input.output.value, token_b_policy, token_b_name) + old_token_b_amount
        |> rats.div_int(2)
        |> rats.truncate
    // Validate if there is right output with the correct datum
    let oracle_output =
      utils.expect_unique(
        utils.get_outputs_by_nft(
          ctx.transaction.outputs,
          oracle_nft_policy,
          oracle_nft_name,
        ),
      )
    expect Finite(lower_bound) =
      ctx.transaction.validity_range.lower_bound.bound_type
    // Must expire in 20 minutes
    let data_matured = old_maturity_time < lower_bound
    let expiration_time = lower_bound + 1200000
    let maturity_time = lower_bound + 600000
    let expected_datum: Data =
      oracle.Datum {
        oracle_parameters,
        token_a_amount,
        token_b_amount,
        expiration_time,
        maturity_time,
      }
    expect InlineDatum(raw_new_oracle_datum) = oracle_output.datum
    expected_datum == raw_new_oracle_datum && data_matured
  }

  fn oracle_mint_validator(
    redeemer: NFTRedeemer<OracleMintRedeemer>,
    ctx: ScriptContext,
  ) {
    let ScriptContext { transaction: Transaction { inputs, mint, .. }, purpose } =
      ctx
    expect Mint(own_purpose) = purpose
    check_uniqueness(redeemer.action, inputs, mint, own_purpose)
  }
}
