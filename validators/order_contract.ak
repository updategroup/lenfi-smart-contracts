//// 1. Supply/Deposit - Lender deposits tokens - receives LP tokens
//// 2. Withdraw - Lender burns LP tokens - receives deposit tokens
//// 3. Borrow - Borrower deposits collateral - receives borrower NFT + loan
//// 4. Repay - Borrower deposits Loan + NFT - receives collateral
//// 5. Liquidate - Someone deposits Loan tokens, receives a piece of collateral

use aada/types.{Wrapped, WrappedRedeemer}
use aada/types/collateral
use aada/types/order
use aada/types/pool
use aada/utils.{expect_by_oref}
use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction,
}
use aiken/transaction/value.{from_minted_value, quantity_of}

fn order_wrapper(
  lambda: fn(b, pool.Action) -> Bool,
  datum: order.Datum<a>,
  redeemer: order.Redeemer<b>,
  ctx: ScriptContext,
) {
  let ScriptContext {
    transaction: Transaction {
      inputs,
      redeemers,
      extra_signatories,
      withdrawals,
      ..
    },
    purpose,
  } = ctx
  expect Spend(this_oref) = purpose
  when redeemer is {
    order.Cancel ->
      utils.authorized_by_credential(
        extra_signatories,
        withdrawals,
        datum.control_credential,
      )
    order.Process { pool_oref, additional_data } -> {
      let Input { output: Output { value: pool_output_value, .. }, .. } =
        expect_by_oref(inputs, pool_oref)
      expect Some(raw_pool_redeemer): Option<Data> =
        dict.get(redeemers, Spend(pool_oref))
      expect Wrapped(pool.Redeemer { action, order, .. }): WrappedRedeemer<
        pool.Redeemer,
      > = raw_pool_redeemer
      trace @"Will seach for NFT"
      let pool_nft_found =
        quantity_of(
          pool_output_value,
          datum.pool_nft_cs.policy_id,
          datum.pool_nft_cs.asset_name,
        ) == 1
      trace @"Will checkt tag"
      let pool_tagged_this = order == Some(this_oref)
      trace @"Will do last thing"
      pool_nft_found? && pool_tagged_this? && lambda(additional_data, action)
    }
  }
}

validator {
  fn deposit_order_contract(
    datum: order.Datum<order.DepositRequest>,
    redeemer: order.Redeemer<Void>,
    ctx: ScriptContext,
  ) -> Bool {
    fn(_: Void, pool_action: pool.Action) -> Bool {
      when pool_action is {
        pool.Transition { .. } -> True
        _ -> False
      }
    }
      |> order_wrapper(datum, redeemer, ctx)
  }
}

validator {
  fn withdraw_order_contract(
    datum: order.Datum<order.WithdrawRequest>,
    redeemer: order.Redeemer<Void>,
    ctx: ScriptContext,
  ) -> Bool {
    fn(_: Void, pool_action: pool.Action) -> Bool {
      when pool_action is {
        pool.Transition { value_delta } -> {
          let order.WithdrawRequest {
            lp_tokens_burn,
            partial_output: order.PartialOutput { address, value, datum },
            receive_asset,
            lp_asset,
          } = datum.order
          let burnt_asset =
            quantity_of(
              from_minted_value(ctx.transaction.mint),
              lp_asset.policy_id,
              lp_asset.asset_name,
            ) == -lp_tokens_burn
          let real_output =
            Output {
              address,
              value: value.add(
                value,
                receive_asset.policy_id,
                receive_asset.asset_name,
                -value_delta,
              ),
              datum,
              reference_script: None,
            }
          let user_received_value =
            ctx.transaction.outputs |> list.any(fn(out) { out == real_output })
          [user_received_value?, burnt_asset?] |> list.and
        }
        _ -> False
      }
    }
      |> order_wrapper(datum, redeemer, ctx)
  }
}

validator {
  fn borrow_order_contract(
    datum: order.Datum<order.BorrowRequest>,
    redeemer: order.Redeemer<order.ProcessBorrow>,
    ctx: ScriptContext,
  ) -> Bool {
    expect Spend(this_oref) = ctx.purpose
    fn(borrow_redeemer, pool_action: pool.Action) -> Bool {
      when pool_action is {
        pool.Borrow { interest_rate, collateral_amount, .. } -> {
          let order.BorrowRequest {
            borrower_nft_policy,
            expected_output,
            max_interest_rate,
            min_collateral_amount,
            collateral_address,
          } = datum.order
          let order.ProcessBorrow(borrower_token_name) = borrow_redeemer
          let borrower_nft_policy = borrower_nft_policy
          // Lender must receive the LPs
          // we enforce two outputs:
          // -> Borrower receives loan & nft
          // -> Collateral is sent to collateral address
          // loan received
          let user_received_value =
            list.any(
              ctx.transaction.outputs,
              fn(out) { out == expected_output },
            )
          // because the nft policy only mints one at a time, we know this is unique.
          // possibly can optimise by just checking the dict for the policy id, and grabbing the (only) name value
          let borrower_token_minted =
            quantity_of(
              from_minted_value(ctx.transaction.mint),
              borrower_nft_policy,
              borrower_token_name,
            ) == 1
          // nft received
          let recipient_got_borrow_nft =
            list.any(
              ctx.transaction.outputs,
              utils.output_has_quantity_with_address(
                _,
                datum.recipient_address,
                borrower_nft_policy,
                borrower_token_name,
                1,
              ),
            )
          let collateral_was_tagged =
            utils.is_unique(
              list.filter(
                ctx.transaction.outputs,
                fn(out) {
                  let Output { address: addr, datum: the_datum, .. } = out
                  when the_datum is {
                    InlineDatum(col_datum) ->
                      if addr == collateral_address {
                        expect collateral_datum: collateral.CollateralDatum =
                          col_datum
                        collateral_datum.tag == Some(this_oref)
                      } else {
                        False
                      }
                    _ -> False
                  }
                },
              ),
            )
          let valid_interest_rate = interest_rate <= max_interest_rate
          let valid_pool_collateral_amount =
            collateral_amount >= min_collateral_amount
          [
            valid_interest_rate?,
            valid_pool_collateral_amount?,
            borrower_token_minted?,
            recipient_got_borrow_nft?,
            user_received_value?,
            collateral_was_tagged?,
          ]
            |> list.and
        }
        _ -> False
      }
    }
      |> order_wrapper(datum, redeemer, ctx)
  }
}

validator {
  fn repay_order_contract(
    datum: order.Datum<order.RepayRequest>,
    redeemer: order.Redeemer<Void>,
    ctx: ScriptContext,
  ) -> Bool {
    fn(_: Void, pool_action: pool.Action) -> Bool {
      when pool_action is {
        pool.CloseLoan { .. } -> {
          let order.RepayRequest { expected_output, order, burn_asset } =
            datum.order
          let received_expected_output =
            list.any(
              ctx.transaction.outputs,
              fn(out) { out == expected_output },
            )
          let consumed_order =
            list.any(
              ctx.transaction.inputs,
              fn(input) { input.output_reference == order },
            )
          let burnt_enough =
            quantity_of(
              from_minted_value(ctx.transaction.mint),
              burn_asset.policy_id,
              burn_asset.asset_name,
            ) == -1
          [received_expected_output?, consumed_order?, burnt_enough?]
            |> list.and
        }
        _ -> False
      }
    }
      |> order_wrapper(datum, redeemer, ctx)
  }
}

validator {
  fn liquidate_order_contract(
    datum: order.Datum<order.LiquidateRequest>,
    redeemer: order.Redeemer<Void>,
    ctx: ScriptContext,
  ) -> Bool {
    fn(_: Void, pool_action: pool.Action) -> Bool {
      when pool_action is {
        pool.CloseLoan { .. } -> True
        _ -> False
      }
    }
      |> order_wrapper(datum, redeemer, ctx)
  }
}
