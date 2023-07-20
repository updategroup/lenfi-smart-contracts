use aada/finance
use aada/rats
use aada/types.{Wrapped, WrappedRedeemer}
use aada/types/pool
use aada/utils
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{
  InlineDatum, OutputReference, Publish, ScriptContext, Spend, Transaction,
  WithdrawFrom,
}
use aiken/transaction/certificate.{
  CredentialDelegation, CredentialDeregistration, CredentialRegistration,
}
use aiken/transaction/value.{AssetName, PolicyId, quantity_of}

type PublishRedeemer {
  nft_oref: OutputReference,
}

type WithdrawalRedeemer {
  action: WithdrawalAction,
  pool_oref: OutputReference,
  nft_oref: OutputReference,
}

type WithdrawalAction {
  ExactWithdrawal
  SwapWithdrawal
}

validator(
  pool_nft_policy: PolicyId,
  delegation_nft_policy: PolicyId,
  pool_nft_name: AssetName,
) {
  fn pool_stake(redeemer: Data, ctx: ScriptContext) {
    let ScriptContext {
      transaction: Transaction { inputs, withdrawals, redeemers, .. },
      purpose,
    } = ctx
    when purpose is {
      Publish(certificate) -> {
        expect PublishRedeemer { nft_oref }: PublishRedeemer = redeemer
        when certificate is {
          CredentialRegistration { .. } | CredentialDelegation { .. } | CredentialDeregistration { .. } -> {
            expect Some(inp) =
              inputs |> list.find(fn(out) { out.output_reference == nft_oref })
            let nft_check =
              quantity_of(
                inp.output.value,
                delegation_nft_policy,
                pool_nft_name,
              ) == 1
            nft_check?
          }
          _ -> False?
        }
      }
      WithdrawFrom(withdraw_credentials) -> {
        expect WithdrawalRedeemer { action, pool_oref, nft_oref }: WithdrawalRedeemer =
          redeemer
        //expect DepositToPool(withdrawal_type, pool_oref) = redeemer
        // validate that withdrawal happens to pool token
        expect Some(pool_input) =
          inputs |> list.find(fn(out) { out.output_reference == nft_oref })
        let nft_check =
          quantity_of(pool_input.output.value, pool_nft_policy, pool_nft_name) == 1
        // let pool_input =
        //   utils.get_input_by_nft(inputs, pool_nft_policy, pool_nft_name)
        expect InlineDatum(pool_datum) = pool_input.output.datum
        expect pool_datum: pool.Datum = pool_datum
        let (withdrawing_stake_hash, current_withdrawal_amount) =
          withdrawals |> dict.to_list |> utils.expect_unique
        expect Some(raw_pool_redeemer): Option<Data> =
          redeemers |> dict.get(Spend(pool_oref))
        expect Wrapped(pool.Redeemer { action: pool.PayFee(fee_amount), .. }): WrappedRedeemer<
          pool.Redeemer,
        > = raw_pool_redeemer
        // may need nft check
        // amount paid into pool is `ge` expected fee
        let withdrawal_check = withdrawing_stake_hash == withdraw_credentials
        when action is {
          ExactWithdrawal -> {
            let amount_check = current_withdrawal_amount >= fee_amount
            withdrawal_check? && amount_check? && nft_check?
          }
          SwapWithdrawal -> {
            expect Finite(lower_bound) =
              ctx.transaction.validity_range.lower_bound.bound_type
            let expected_deposit_amount =
              if pool_datum.params.loan_cs.policy_id == #"" {
                current_withdrawal_amount
              } else {
                let loan_oracle_datum =
                  utils.expect_oracle_datum(
                    inputs,
                    pool_datum.params.oracle_loan_nft,
                  )
                utils.do_oracle_calculation(
                  lower_bound,
                  pool_datum.params.loan_cs,
                  loan_oracle_datum,
                  finance.asset_gain_adasale(current_withdrawal_amount, _, _),
                )
              }
            let amount_check =
              expected_deposit_amount
                |> finance.calculate_tokenswap_discount
                |> rats.ge(rats.from_int(fee_amount))
            withdrawal_check? && amount_check? && nft_check?
          }
        }
      }
      _ -> False
    }
  }
}
