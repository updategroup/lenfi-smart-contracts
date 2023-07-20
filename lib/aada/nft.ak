use aada/utils
use aiken/bytearray.{push}
use aiken/hash
use aiken/list
use aiken/transaction.{Input, OutputReference, TransactionId}
use aiken/transaction/value.{MintedValue}

pub type NFTAction {
  MintNFT(OutputReference)
  BurnNFT(ByteArray)
}

pub type NFTRedeemer<a> {
  action: NFTAction,
  inner: a,
}

pub fn id_from_utxo(consumed_utxo: OutputReference) -> ByteArray {
  let OutputReference(TransactionId(consumed_tx_hash), consumed_utxo_index) =
    consumed_utxo
  hash.blake2b_256(push(consumed_tx_hash, consumed_utxo_index))
}

// I think NFTs are a moderate security vector right now
// Bc if we want to make simplifications, we need to enforce
// certain contexts (e.g that pool is called in certain way)

// NFT types:
// 0 - Pool NFT // moved into pool.ak
// 1 - Borrower NFT // moving into collateral.ak
// 2 - Oracle NFT
// 3 - Delegation NFT
// 4 - Farming NFT
// 5 - Protocol details NFT
pub fn check_uniqueness(
  nft_action: NFTAction,
  inputs: List<Input>,
  mint: MintedValue,
  own_policy: ByteArray,
) -> Bool {
  when nft_action is {
    MintNFT(consumed_utxo) -> {
      let nft_name = id_from_utxo(consumed_utxo)
      utils.validate_mint_nft(mint, own_policy, nft_name, 1) && list.any(
        inputs,
        fn(input) { input.output_reference == consumed_utxo },
      )
    }
    BurnNFT(burn_tn) -> utils.validate_mint_nft(mint, own_policy, burn_tn, -1)
  }
}
