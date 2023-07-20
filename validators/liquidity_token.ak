use aada/types/pool
use aada/utils
use aiken/dict
use aiken/list
use aiken/transaction.{InlineDatum, Mint, OutputReference, ScriptContext}
use aiken/transaction/credential.{Address, from_script}
use aiken/transaction/value.{from_minted_value, quantity_of, tokens}

type TokenRedeemer {
  TransitionPool { pool_oref: OutputReference }
  CreatePool
  DestroyPool { pool_oref: OutputReference }
}

// FOR AUDITORS:
// MAINTAIN: QUANTITY OF LPS MINTED = TOTAL_LP_TOKENS

// Mint liquidity tokens that are the right to claim deposits
validator(pool_hash: ByteArray) {
  fn liquidity_token(redeemer: TokenRedeemer, ctx: ScriptContext) {
    let pool_address_spend_key_only: Address = from_script(pool_hash)
    // This is not representation of pool address. Pool address contains stake hash as well.
    expect Mint(own_policy) = ctx.purpose
    when redeemer is {
      TransitionPool { .. } -> {
        let pool_input =
          utils.expect_unique(
            list.filter(
              ctx.transaction.inputs,
              fn(inp) {
                inp.output.address.payment_credential == pool_address_spend_key_only.payment_credential
              },
            ),
          )
        let pool_output =
          utils.expect_unique(
            list.filter(
              ctx.transaction.outputs,
              fn(out) {
                out.address.payment_credential == pool_address_spend_key_only.payment_credential
              },
            ),
          )
        expect InlineDatum(output_datum) = pool_output.datum
        expect output_datum: pool.Datum = output_datum
        expect InlineDatum(input_datum) = pool_input.output.datum
        expect input_datum: pool.Datum = input_datum
        // let (lp_token_name, lp_tokens_amount) =
        //   utils.expect_unique(
        //     tokens(from_minted_value(ctx.transaction.mint), own_policy)
        //       |> dict.to_list(),
        //   )s
        expect [(lp_token_name, lp_tokens_amount)] =
          tokens(from_minted_value(ctx.transaction.mint), own_policy)
            |> dict.to_list()
        let valid_lp_token_name =
          lp_token_name == output_datum.params.pool_nft_name
        let valid_lp_token_change =
          output_datum.total_lp_tokens - input_datum.total_lp_tokens == lp_tokens_amount
        valid_lp_token_name && valid_lp_token_change
      }

      // let depositing_amount =
      //   rats.from_int(output_datum.balance - input_datum.balance)
      // let expected_deposit_amount =
      //   utils.get_expected_deposit_amount(lp_tokens_amount, input_datum)
      // // obvious stop doing this, just assert sign
      // let valid_lp_token_change =
      //   if depositing_amount |> rats.lt(rats.from_int(0)) {
      //     depositing_amount |> rats.ge(expected_deposit_amount)
      //   } else {
      //     depositing_amount |> rats.le(expected_deposit_amount)
      //   }
      // output_datum.lent_out == input_datum.lent_out && input_datum.params.pool_nft_name == output_datum.params.pool_nft_name && lp_token_name == output_datum.params.pool_nft_name && valid_lp_token_change
      DestroyPool { .. } -> {
        let pool_input =
          utils.expect_unique(
            utils.get_inputs_by_payment_credential(
              ctx.transaction.inputs,
              pool_address_spend_key_only,
            ),
          )
        //
        expect InlineDatum(input_datum) = pool_input.output.datum
        expect input_datum: pool.Datum = input_datum
        // // LP token name is the same as pool TN
        let actual_tokens_minted =
          quantity_of(
            from_minted_value(ctx.transaction.mint),
            own_policy,
            input_datum.params.pool_nft_name,
          )
        (actual_tokens_minted == input_datum.total_lp_tokens)?
      }
      CreatePool -> {
        let pool_output =
          utils.expect_unique(
            list.filter(
              ctx.transaction.outputs,
              fn(output) {
                output.address.payment_credential == pool_address_spend_key_only.payment_credential
              },
            ),
          )
        expect InlineDatum(output_datum) = pool_output.datum
        expect output_datum: pool.Datum = output_datum
        let mint = from_minted_value(ctx.transaction.mint)
        let pool_token_name =
          utils.expect_unique(dict.keys(tokens(mint, pool_hash)))
        let lp_tokens_minted = quantity_of(mint, own_policy, pool_token_name)
        let depositing_tokens_count_actual =
          quantity_of(
            pool_output.value,
            output_datum.params.loan_cs.policy_id,
            output_datum.params.loan_cs.asset_name,
          )
        let correct_pooltoken_mint =
          quantity_of(mint, pool_hash, pool_token_name) == 1
        let correct_pooltoken_out =
          quantity_of(pool_output.value, pool_hash, pool_token_name) == 1
        let correct_recorded_lptokens =
          output_datum.total_lp_tokens == lp_tokens_minted
        let depositing_gt_0 = depositing_tokens_count_actual > 0
        let depositing_at_script =
          depositing_tokens_count_actual == output_datum.balance
        let minted_at_discount =
          depositing_tokens_count_actual - 10 == lp_tokens_minted
        [
          correct_pooltoken_mint?,
          correct_pooltoken_out?,
          correct_recorded_lptokens?,
          depositing_gt_0?,
          depositing_at_script?,
          minted_at_discount?,
        ]
          |> list.and
      }
    }
  }
}
