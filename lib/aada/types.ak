use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{Script}
use aiken/transaction/value.{AssetName, PolicyId}

/// Consider: wrapping this further for safety.
pub type POSIXTime =
  Int

/// There's got to be some functional way to do efficient checks on this.
/// Consider experimenting after testnet.
pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

/// Consider: wrapping this further for safety.
pub type ValidatorHash =
  Hash<Blake2b_224, Script>

/// Consider: wrapping this further for safety.
pub type PaymentHash =
  Hash<Blake2b_224, Script>

/// Task for txpipe team: check this is correct.
/// 0. should never happen
/// 1. should always
pub type WrappedRedeemer<a> {
  BadScriptContext
  Wrapped(a)
}
