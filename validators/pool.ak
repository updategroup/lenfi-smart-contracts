use aada/finance
use aada/nft.{BurnNFT, MintNFT, NFTRedeemer, id_from_utxo}
use aada/rats
use aada/types/pool
use aada/utils.{expect_by_oref}
use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{
  PolicyId, from_asset, from_minted_value, merge, quantity_of, tokens,
}

// Must attach stake key to the contract when creating the pool (off-chain)
validator(delegator_nft_policy: PolicyId, pool_config_scripthash: PolicyId) {
  fn pool(datum: pool.Datum, redeemer: pool.Redeemer, ctx: ScriptContext) {
    let pool.Datum { params, balance, lent_out, total_lp_tokens } = datum
    // ignore warning
    let ScriptContext {
      transaction: Transaction { inputs, mint, reference_inputs, .. },
      purpose,
    } = ctx
    expect Spend(output_ref) = purpose
    let pool_input = expect_by_oref(inputs, output_ref)
    let Input { output: Output { address: this_address, .. }, .. } = pool_input
    expect ScriptCredential(this_script_hash) = this_address.payment_credential
    let pool_nft_policy: PolicyId = this_script_hash
    // Validates that pool receives right amount and correct datum is assigned
    // Validate if pool token is in transaction
    let validate_transition =
      fn(f_delta: fn(Int, Int, Int) -> Bool) -> Bool {
        let pool_output =
          utils.expect_unique(
            list.filter(
              ctx.transaction.outputs,
              fn(out) { out.address == this_address },
            ),
          )
        // lost here, count number of inputs from this address == 1
        expect InlineDatum(contract_datum) = pool_output.datum
        expect pool.Datum {
          params: output_params,
          balance: output_balance,
          lent_out: output_lent_out,
          total_lp_tokens: output_total_lp_tokens,
        }: pool.Datum = contract_datum
        let expected_change_value =
          from_asset(
            params.loan_cs.policy_id,
            params.loan_cs.asset_name,
            output_balance - balance,
          )
        // let expected_value_with_input =
        //   add(
        //     pool_input.output.value,
        //     params.loan_cs.policy_id,
        //     params.loan_cs.asset_name,
        //     balance_change,
        //   )
        let expected_value_with_input =
          merge(pool_input.output.value, expected_change_value)
        let value_change_check =
          quantity_of(
            expected_value_with_input,
            params.loan_cs.policy_id,
            params.loan_cs.asset_name,
          ) == quantity_of(
            pool_output.value,
            params.loan_cs.policy_id,
            params.loan_cs.asset_name,
          )
        let pool_input_nft_check =
          utils.value_has_nft(
            pool_input.output.value,
            pool_nft_policy,
            params.pool_nft_name,
          )
        let pool_output_nft_check =
          utils.value_has_nft(
            pool_output.value,
            pool_nft_policy,
            params.pool_nft_name,
          )
        let valid_pool_token_tx =
          pool_input_nft_check? && pool_output_nft_check?
        let params_check = output_params == params
        let f_delta_check =
          f_delta(
            output_balance - balance,
            output_lent_out - lent_out,
            output_total_lp_tokens - total_lp_tokens,
          )?
        valid_pool_token_tx? && value_change_check? && f_delta_check && params_check
      }
    let pool.Redeemer { action, config_ref, .. } = redeemer
    let config_input = expect_by_oref(reference_inputs, config_ref)
    expect True =
      utils.value_has_nft(
        config_input.output.value,
        pool_config_scripthash,
        params.pool_config_assetname,
      )?
    expect InlineDatum(raw_config_input_datum) = config_input.output.datum
    expect pool.Config { pool_fee, .. }: pool.Config = raw_config_input_datum
    // let only_one_pool_input =
    //   list.length(utils.get_own_validator_hash_inputs(ctx, output_ref)) == 1
    when action is {
      pool.Destroy -> {
        let no_remaining_lp =
          quantity_of(
            from_minted_value(mint),
            params.lp_token.policy_id,
            params.lp_token.asset_name,
          ) + total_lp_tokens == 0
        let burnt_pool_nft =
          utils.validate_mint_nft(
            mint,
            pool_nft_policy,
            params.pool_nft_name,
            -1,
          )
        let burnt_delegator_nft =
          utils.validate_mint_nft(
            mint,
            delegator_nft_policy,
            params.pool_nft_name,
            -1,
          )
        no_remaining_lp? && burnt_pool_nft? && burnt_delegator_nft?
      }
      pool.Transition { value_delta } -> {
        let lp_token_delta =
          quantity_of(
            from_minted_value(mint),
            params.lp_token.policy_id,
            params.lp_token.asset_name,
          )
        let expected_change_amount =
          lp_token_delta * ( datum.balance + datum.lent_out )
            |> rats.div_int(datum.total_lp_tokens)

        // need to stop this and assert sign
        let check_withdrawal_amount =
          if rats.lt(expected_change_amount, rats.from_int(0)) {
            ( expected_change_amount |> rats.neq(rats.from_int(0)) ) && rats.le(
              expected_change_amount,
              rats.from_int(value_delta),
            )
          } else {
            ( expected_change_amount |> rats.neq(rats.from_int(0)) ) && rats.ge(
              expected_change_amount,
              rats.from_int(value_delta),
            )
          }

        let pool_changed_correctly =
          validate_transition(
            fn(balance_delta, lent_delta, tokens_delta) {
              pool_fee + value_delta == balance_delta && 0 == lent_delta && tokens_delta == lp_token_delta
            },
          )
        //lp_tokens_burned * ( balance + lent_out ) / total_lp_tokens
        check_withdrawal_amount? && pool_changed_correctly?
      }
      pool.Borrow { loan_amount, interest_rate, .. } -> {
        let loan_is_positive = loan_amount > 0
        let valid_pool_change =
          validate_transition(
            fn(balance_delta, lent_delta, tokens_delta) {
              pool_fee - loan_amount == balance_delta && loan_amount == lent_delta && tokens_delta == 0
            },
          )
        let valid_interest_rates =
          interest_rate
            |> rats.from_int
            |> rats.ge(finance.get_interest_rates(loan_amount, lent_out, balance))
        expect ScriptCredential(collateral_policy) =
          params.collateral_address.payment_credential
        // let (_, token_amount) =
        //   utils.expect_unique(
        //     dict.to_list(tokens(from_minted_value(mint), collateral_policy)),
        //   )
        expect [(_, token_amount)] =
          dict.to_list(tokens(from_minted_value(mint), collateral_policy))
        let valid_collateral_exists = token_amount == 1
        loan_is_positive? && valid_collateral_exists? && valid_pool_change? && valid_interest_rates?
      }
      pool.CloseLoan { loan_amount, interest_amount } -> {
        let amount_check = loan_amount > 0
        let interest_check = interest_amount > 0
        let transition_check =
          validate_transition(
            fn(balance_delta, lent_delta, tokens_delta) {
              pool_fee + loan_amount + interest_amount == balance_delta && -loan_amount == lent_delta && 0 == tokens_delta
            },
          )
        amount_check? && interest_check? && transition_check?
      }
      pool.PayFee { fee } -> {
        let valid_minimum_amount = fee > pool_fee
        let valid_transition =
          validate_transition(
            fn(balance_delta, lent_delta, tokens_delta) {
              balance_delta == fee && lent_delta == 0 && tokens_delta == 0
            },
          )
        valid_minimum_amount? && valid_transition?
      }
    }
  }

  fn pool_mint(r: NFTRedeemer<Void>, ctx: ScriptContext) -> Bool {
    let ScriptContext {
      transaction: Transaction { outputs, inputs, mint, .. },
      purpose,
    } = ctx
    expect Mint(own_policy) = purpose
    let pool_control_credential = ScriptCredential(own_policy)
    when r.action is {
      MintNFT(output_reference) -> {
        let nft_name = id_from_utxo(output_reference)
        let valid_nft_check =
          utils.validate_mint_nft(mint, own_policy, nft_name, 1)
        let consumed_utxo_check =
          list.any(
            inputs,
            fn(input) { input.output_reference == output_reference },
          )
        let output_found =
          outputs
            |> list.any(
                 fn(output) {
                   let Output { address: Address(out_credential, _), value, .. } =
                     output
                   let correct_credential =
                     out_credential == pool_control_credential
                   let correct_quantity =
                     quantity_of(value, own_policy, nft_name) == 1
                   correct_credential? && correct_quantity?
                 },
               )
        [valid_nft_check, consumed_utxo_check, output_found] |> list.and
      }
      BurnNFT(burn_tn) -> utils.validate_mint_nft(mint, own_policy, burn_tn, -1)
    }
  }
}
