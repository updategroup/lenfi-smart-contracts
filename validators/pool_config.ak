use aada/nft.{NFTAction, check_uniqueness}
use aada/nft_pointers
use aada/types.{AssetClass}
use aada/types/pool
use aiken/transaction.{Mint, ScriptContext, Transaction, WithdrawFrom}

validator(gov_nft: AssetClass, _default_config: pool.Config) {
  fn spend(_datum: pool.Config, _redeemer: Void, ctx: ScriptContext) {
    let AssetClass { policy_id, asset_name } = gov_nft
    let ScriptContext {
      transaction: Transaction {
        reference_inputs,
        withdrawals,
        extra_signatories,
        ..
      },
      ..
    } = ctx
    let gov_approval =
      nft_pointers.nft_validator(
        policy_id,
        asset_name,
        reference_inputs,
        withdrawals,
        extra_signatories,
      )
    gov_approval
  }

  fn other(redeemer: Data, ctx: ScriptContext) -> Bool {
    let ScriptContext { transaction, purpose } = ctx
    when purpose is {
      Mint(this_policy) -> {
        expect redeemer: NFTAction = redeemer
        let Transaction { inputs, mint, .. } = transaction

        // need to enforce output is at this script. 
        check_uniqueness(redeemer, inputs, mint, this_policy)
      }
      WithdrawFrom(_) -> True
      _ -> False
    }
  }
}
