//// Utils 

use aada/types.{AssetClass}
use aada/types/oracle
use aiken/builtin
use aiken/cbor
use aiken/dict
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/string
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext,
}
use aiken/transaction/credential.{
  Address, Credential, Inline, StakeCredential, VerificationKey,
  VerificationKeyCredential,
}
use aiken/transaction/value.{
  AssetName, MintedValue, PolicyId, Value, from_minted_value, quantity_of,
}

/// These are aada/plutus specific utility functions. They mostly take ctx/inputs/other transaction data.
/// Other utils can be found in finance.ak

pub type DatumOrc {
  oracle_parameters: OracleParametersd,
  token_a_amount: Int,
  // if we turn this into a list (for medians), we should fix size for safety.
  token_b_amount: Int,
  // similarly.
  expiration_time: Int,
  maturity_time: Int,
}

pub type OracleParametersd {
  pool_nft_cs: AssetClass,
  oracle_nft_cs: AssetClass,
  token_a_cs: AssetClass,
  token_b_cs: AssetClass,
}

// Get all inputs
pub fn get_inputs(inputs: List<Input>, address: Address) -> List<Input> {
  list.filter(inputs, fn(input) { input.output.address == address })
}

/// Get all outputs
pub fn get_outputs(ctx: ScriptContext, address: Address) -> List<Output> {
  list.filter(ctx.transaction.outputs, fn(output) { output.address == address })
}

// Get all inputs by payment credential
pub fn get_inputs_by_payment_credential(
  inputs: List<Input>,
  address: Address,
) -> List<Input> {
  list.filter(
    inputs,
    fn(input) {
      input.output.address.payment_credential == address.payment_credential
    },
  )
}


/// Checks that an NFT, and only that NFT, was minted from policy.
pub fn validate_mint_nft(
  mints: MintedValue,
  expected_minting_policy: ByteArray,
  expected_minting_name: ByteArray,
  expected_minting_amt: Int,
) -> Bool {
  let mints_policy =
    dict.to_list(
      value.tokens(from_minted_value(mints), expected_minting_policy),
    )
  mints_policy == [(expected_minting_name, expected_minting_amt)]
}

/// Checks that a value contains 1 of a token
pub fn value_has_nft(value: Value, policy_id: PolicyId, token_name: AssetName) {
  quantity_of(value, policy_id, token_name) == 1
}

/// Checks an output has a minimum quantity of an asset
/// Uses aiken/value.{quantity_of}
pub fn output_has_quantity(
  output: Output,
  policy_id: PolicyId,
  token_name: AssetName,
  amount: Int,
) {
  quantity_of(output.value, policy_id, token_name) >= amount
}

/// Checks an output has a minimum quantity and is also at an address
pub fn output_has_quantity_with_address(
  output: Output,
  address: Address,
  policy_id: PolicyId,
  token_name: AssetName,
  amount: Int,
) {
  let Output { address: output_address, value: output_value, .. } = output
  output_address == address && quantity_of(output_value, policy_id, token_name) >= amount
}

/// Checks the input set has an input which value holds the oracle nft, returns its datum
pub fn expect_oracle_datum(
  inputs: List<Input>,
  oracle_nft: AssetClass,
) -> DatumOrc {
  let Input { output: Output { datum, .. }, .. } =
    get_input_by_nft(inputs, oracle_nft.policy_id, oracle_nft.asset_name)
  expect InlineDatum(oracle_datum) = datum
  expect oracle_datum_typed: DatumOrc = oracle_datum
  oracle_datum_typed
}

/// Runs calculations using oracle feeds (datums).
/// Automatically flips the order if e.g your fetching ADA/USD from a USD/ADA oracle or vice versa.
pub fn do_oracle_calculation(
  lower_bound: Int,
  asset_to_sell: AssetClass,
  oracle_datum: DatumOrc,
  oracle_calculation: fn(Int, Int) -> a,
) -> a {
  let params = oracle_datum.oracle_parameters
  if oracle_datum.expiration_time > lower_bound {
    if
    asset_to_sell == params.token_a_cs && params.token_b_cs == AssetClass(
      "",
      "",
    ){
    
      oracle_calculation(
        oracle_datum.token_b_amount,
        oracle_datum.token_a_amount,
      )
    } else if asset_to_sell == params.token_b_cs && params.token_a_cs == AssetClass(
      "",
      "",
    ) {
      oracle_calculation(
        oracle_datum.token_a_amount,
        oracle_datum.token_b_amount,
      )
    } else {
      error @"Bad oracle data"
    }
  } else {
    error @"Oracle data is expired "
  }
}

/// Get outputs that contains any token of given policy and name
pub fn get_outputs_by_nft(
  outputs: List<Output>,
  token_policy: PolicyId,
  token_name: AssetName,
) -> List<Output> {
  list.filter(
    outputs,
    fn(output) { quantity_of(output.value, token_policy, token_name) > 0 },
  )
}

// Get inputs that contains exactly 1 token of given policy and name
pub fn get_input_by_nft(
  inputs: List<Input>,
  token_policy: PolicyId,
  token_name: AssetName,
) -> Input {
  expect Some(x) =
    list.find(
      inputs,
      fn(input) {
        quantity_of(input.output.value, token_policy, token_name) == 1
      },
    )
  x
}

/// Transaction authorized by credential.
/// If verification key, check it is contained within extra_signatories
/// If script, check it is in stake withdrawals (programmable by stake scripts)
pub fn authorized_by_credential(
  extra_signatories: List<Hash<Blake2b_224, VerificationKey>>,
  withdrawals: dict.Dict<StakeCredential, Int>,
  payment_key: Credential,
) -> Bool {
  // todo: consider supporting all script types.
  when payment_key is {
    // either credential is a spending key, or script using stake-withdraw-0
    VerificationKeyCredential(payment_key_hash) ->
      list.has(extra_signatories, payment_key_hash)
    script_credential -> dict.has_key(withdrawals, Inline(script_credential))
  }
}

/// Throws an error if list isn't [x]
/// More efficient than expect until Microproofs fixes the traces in expect
pub fn expect_unique(list: List<x>) -> x {
  if builtin.null_list(builtin.tail_list(list)) {
    builtin.head_list(list)
  } else {
    error
  }
}

/// Similar reasoning to expect_unique
/// Safe, should never throw. If unsafe, please fix.
pub fn is_unique(list: List<x>) -> Bool {
  !builtin.null_list(list) && builtin.null_list(builtin.tail_list(list))
}

/// Return input with the output reference.
/// Throw if some output reference is not resolvable from input list.
pub fn expect_by_oref(inputs: List<Input>, output_ref: OutputReference) -> Input {
  expect Some(x) =
    list.find(inputs, fn(inp) -> Bool { inp.output_reference == output_ref })
  x
}
