use aada/finance
use aada/nft.{id_from_utxo}
use aada/rats
use aada/types.{AssetClass, Wrapped, WrappedRedeemer}
use aada/types/collateral.{CollateralDatum}
use aada/types/pool
use aada/utils.{expect_by_oref}
use aiken/dict
use aiken/interval.{Finite, Interval, IntervalBound}
use aiken/list
// Collateral is makes sure that loan is repaid fairly before allowing to take collateral.
// Also collateral is a friend of lender since Collateral, not Pool cares about the interest and loan
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, ScriptContext, Spend,
  Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value.{from_minted_value, quantity_of, tokens}

type CollateralRedeemer {
  action: CollateralRedeemerType,
  interest: Int,
}

type CollateralRedeemerType {
  CollateralRepay
  CollateralLiquidate
}

type CollateralMintRedeemer {
  oref: OutputReference,
}

fn get_platform_fee(
  collateral_datum: CollateralDatum,
  pool_input_datum: pool.Datum,
  platform_fee_datum: pool.PlatformFeeDetails,
) -> Int {
  let utilization_rate =
    collateral_datum.loan_amount * 1000000
      |> rats.div_int(pool_input_datum.lent_out + pool_input_datum.balance)

  if
  utilization_rate
    |> rats.lt(rats.from_int(platform_fee_datum.tier_1_threshold)){
  
    platform_fee_datum.tier_1_fee
  } else if utilization_rate
    |> rats.lt(rats.from_int(platform_fee_datum.tier_2_threshold)) {
    platform_fee_datum.tier_2_fee
  } else {
    platform_fee_datum.tier_3_fee
  }
}

fn maybe_process_oracle(
  reference_inputs: List<Input>,
  lower_bound: Int,
  currencysymbol: AssetClass,
  default: Int,
  oracle_nft: AssetClass,
  f: fn(Int, Int) -> Int,
) -> Int {
  if currencysymbol.policy_id == #"" {
    default
  } else {
    let loan_oracle_datum =
      utils.expect_oracle_datum(reference_inputs, oracle_nft)
    utils.do_oracle_calculation(
      lower_bound,
      currencysymbol,
      loan_oracle_datum,
      f(_, _),
    )
  }
}

type CollateralScriptParams {
  pool_script_hash: ByteArray,
  liquidations_pkh: ByteArray,
}

// Must attach stake key to the contract
validator(collateral_script_params: CollateralScriptParams) {
  fn collateral_spend(
    datum: CollateralDatum,
    redeemer: CollateralRedeemer,
    ctx: ScriptContext,
  ) {
    let CollateralScriptParams { pool_script_hash, liquidations_pkh } =
      collateral_script_params
    // ignore lsp
    let ScriptContext {
      transaction: Transaction {
        validity_range,
        inputs,
        reference_inputs,
        outputs,
        ..
      },
      purpose,
    } = ctx
    // expect spend
    expect Spend(output_reference) = purpose
    // Get validity bounds, ignore lsp
    let Interval {
      lower_bound: IntervalBound { bound_type: l_bound_type, .. },
      upper_bound: IntervalBound { bound_type: u_bound_type, .. },
    } = validity_range
    expect Finite(lower_bound) = l_bound_type
    expect Finite(upper_bound) = u_bound_type
    let CollateralDatum { pool_nft_name, .. } = datum
    // find pool
    let pool_input =
      utils.get_input_by_nft(inputs, pool_script_hash, pool_nft_name)
    expect InlineDatum(pool_input_datum) = pool_input.output.datum
    expect pool_input_datum: pool.Datum = pool_input_datum
    // Get interest amount to be paid
    let pool.Config {
      loan_fee_details: platform_fee_details,
      liquidation_threshold,
      ..
    }: pool.Config = datum.pool_config
    let platform_fee_rate =
      get_platform_fee(datum, pool_input_datum, platform_fee_details)
    let CollateralRedeemer { action, interest: interest_amount } = redeemer
    let calculated_interest_amount =
      finance.calculate_interest_amount(
        datum.interest_rate,
        datum.loan_amount,
        datum.deposit_time,
        upper_bound,
      )
    expect True =
      rats.from_int(interest_amount) |> rats.ge(calculated_interest_amount)
    let platform_fee_amount =
      interest_amount * platform_fee_rate |> rats.div_int(1000000)
    let platform_fee_amount_int = platform_fee_amount |> rats.truncate
    let amount_to_repay =
      calculated_interest_amount
        |> rats.add(platform_fee_amount)
        |> rats.add(rats.from_int(datum.loan_amount))
    let platform_fee_sent =
      list.any(
        outputs,
        utils.output_has_quantity_with_address(
          _,
          platform_fee_details.platform_fee_collector_address,
          datum.loan_cs.policy_id,
          datum.loan_cs.asset_name,
          platform_fee_amount_int,
        ),
      )
    let platform_fee_paid =
      (platform_fee_amount_int == 0)? || platform_fee_sent?

    let Input {
      output: Output {
        address: Address(
          ScriptCredential(collateral_script_hash),
          own_stake_key,
        ),
        ..
      },
      ..
    } = expect_by_oref(inputs, output_reference)
    // add redeemer check for pool
    when action is {
      CollateralRepay -> {
        let nft_check =
          utils.validate_mint_nft(
            ctx.transaction.mint,
            collateral_script_hash,
            datum.borrower_tn,
            -1,
          )

        platform_fee_paid? && nft_check?
      }
      CollateralLiquidate -> {
        let value_to_repay =
          maybe_process_oracle(
            reference_inputs,
            lower_bound,
            datum.loan_cs,
            amount_to_repay |> rats.truncate,
            datum.oracle_loan_nft,
            finance.ada_for_purchase(amount_to_repay, _, _),
          )
        let collateral_amount_rat = datum.collateral_amount |> rats.from_int()
        let collateral_value =
          maybe_process_oracle(
            reference_inputs,
            lower_bound,
            datum.collateral_cs,
            collateral_amount_rat |> rats.truncate,
            datum.oracle_collateral_nft,
            finance.calculate_sale(collateral_amount_rat, _, _),
          )

        let liquidation_address =
          Address(ScriptCredential(liquidations_pkh), own_stake_key)
        // Borrower should receive 97.5% of collateral-loan value
        let borrower_compensation_in_ada =
          rats.div_int(( collateral_value - value_to_repay ) * 975000, 1000000)
        let borrower_compensation_in_collateral_amount =
          borrower_compensation_in_ada
            |> rats.mul(rats.from_int(collateral_value))
            |> rats.div(rats.from_int(datum.collateral_amount))
        let collateral_check =
          finance.check_is_undercollaterized(
            value_to_repay,
            collateral_value,
            liquidation_threshold,
          )
        let borrower_compensation =
          borrower_compensation_in_collateral_amount
            |> rats.truncate()
        let liquidation_output_check =
          if borrower_compensation > 0 {
            let AssetClass { policy_id, asset_name } = datum.collateral_cs
            // ignore the LSP
            let Output { value, datum: wrapped_datum, .. } =
              utils.expect_unique(
                list.filter(
                  outputs,
                  fn(output) { output.address == liquidation_address },
                ),
              )
            expect InlineDatum(raw_datum) = wrapped_datum
            let constructed_datum: LeftoversDatum =
              AssetClass {
                policy_id: collateral_script_hash,
                asset_name: datum.borrower_tn,
              }
            let expected_datum: Data = constructed_datum
            let quantity_check =
              quantity_of(value, policy_id, asset_name) >= borrower_compensation
            let datum_check = raw_datum == expected_datum
            quantity_check? && datum_check?
          } else {
            True
          }
        platform_fee_paid? && collateral_check? && liquidation_output_check?
      }
    }
  }

  // todo: all that fancy pool enforce crap
  fn collateral_policy(r: CollateralMintRedeemer, ctx: ScriptContext) -> Bool {
    // Slightly inefficient logical separation here
    // Makes it easier to understand the pool.ak script.
    // Will enforce collateral nfts are unique later
    let CollateralScriptParams { pool_script_hash, .. } =
      collateral_script_params
    let ScriptContext {
      transaction: Transaction {
        inputs,
        outputs,
        validity_range,
        mint,
        reference_inputs,
        ..
      },
      purpose,
    } = ctx
    let mint = from_minted_value(mint)
    expect Mint(this_address) = purpose
    // let (token_name, token_minted_amount) =
    //   utils.expect_unique(dict.to_list(tokens(mint, this_address)))
    expect [(token_name, token_minted_amount)] =
      dict.to_list(tokens(mint, this_address))
    if token_minted_amount == 1 {
      let Output {
        datum: InlineDatum(actual_datum_output),
        value: collateral_value,
        address: collateral_address,
        ..
      } =
        utils.expect_unique(
          list.filter(
            outputs,
            fn(out) {
              when out.address.payment_credential is {
                ScriptCredential(addr) -> addr == this_address
                _ -> False
              }
            },
          ),
        )
      expect CollateralDatum { pool_nft_name, tag, .. }: CollateralDatum =
        actual_datum_output
      let Input(
        pool_oref,
        Output { datum: InlineDatum(raw_pool_datum), address: pool_address, .. },
      ) =
        utils.expect_unique(
          list.filter(
            inputs,
            fn(in) {
              quantity_of(in.output.value, pool_script_hash, pool_nft_name) == 1
            },
          ),
        )
      expect Some(raw_pool_redeemer): Option<Data> =
        dict.get(ctx.transaction.redeemers, Spend(pool_oref))
      expect Wrapped(pool.Redeemer {
        action: pool.Borrow {
          loan_amount,
          collateral_amount: borrowed_collateral_amount,
          interest_rate,
          borrower_tn,
        },
        config_ref,
        ..
      }): WrappedRedeemer<pool.Redeemer> = raw_pool_redeemer
      let Input {
        output: Output { datum: InlineDatum(pool_config_datum), .. },
        ..
      } = expect_by_oref(reference_inputs, config_ref)
      expect pool_config: pool.Config = pool_config_datum
      expect pool.Datum {
        params: pool.Constants {
          pool_nft_name,
          loan_cs,
          collateral_cs,
          oracle_collateral_nft,
          oracle_loan_nft,
          ..
        },
        ..
      }: pool.Datum = raw_pool_datum
      expect Finite(lower_bound) = validity_range.lower_bound.bound_type
      let expected_collateral_datum: Data =
        CollateralDatum {
          pool_nft_name,
          loan_cs,
          loan_amount,
          pool_config,
          collateral_cs,
          collateral_amount: borrowed_collateral_amount,
          interest_rate,
          deposit_time: lower_bound,
          borrower_tn,
          oracle_collateral_nft,
          oracle_loan_nft,
          tag,
        }
      let collateral_amount =
        quantity_of(
          collateral_value,
          collateral_cs.policy_id,
          collateral_cs.asset_name,
        )
      expect True = collateral_amount >= borrowed_collateral_amount

      let loan_value =
        maybe_process_oracle(
          reference_inputs,
          lower_bound,
          loan_cs,
          rats.from_int(loan_amount) |> rats.truncate,
          oracle_loan_nft,
          finance.ada_for_purchase(rats.from_int(loan_amount), _, _),
        )

      let collateral_tokens_value =
        maybe_process_oracle(
          reference_inputs,
          lower_bound,
          collateral_cs,
          rats.from_int(collateral_amount) |> rats.truncate,
          oracle_collateral_nft,
          finance.calculate_sale(rats.from_int(collateral_amount), _, _),
        )
      let tag_check =
        when tag is {
          Some(oref) -> list.any(inputs, fn(in) { in.output_reference == oref })
          None -> True
        }
      let CollateralMintRedeemer { oref: collateral_nft_oref } = r
      let token_name_check = token_name == id_from_utxo(collateral_nft_oref)
      let token_name_oref_consumed_check =
        list.any(inputs, fn(in) { in.output_reference == collateral_nft_oref })
      actual_datum_output == expected_collateral_datum && finance.check_is_overcollaterized(
        loan_value,
        collateral_tokens_value,
        pool_config.initial_collateral_ratio,
      )? && (pool_address.stake_credential == collateral_address.stake_credential)? && token_name_check? && tag_check? && token_name_oref_consumed_check?
    } else if
    token_minted_amount == -1{
    
      let CollateralMintRedeemer { oref } = r
      // expect _: WrappedRedeemer<CollateralRedeemer> =
      //   raw_collateral_redeemer
      dict.get(ctx.transaction.redeemers, Spend(oref)) != None && list.any(
        ctx.transaction.inputs,
        fn(inp) {
          inp.output_reference == oref && inp.output.address.payment_credential == ScriptCredential(
            this_address,
          )
        },
      )
    } else {
      False
    }
  }
}

type LeftoversDatum =
  AssetClass

// old 'liquidate', think it makes more sense to generalise it than specify.
validator {
  fn leftovers(datum: LeftoversDatum, _r: Void, ctx: ScriptContext) {
    let AssetClass { policy_id, asset_name } = datum
    utils.validate_mint_nft(ctx.transaction.mint, policy_id, asset_name, -1)
  }
}
