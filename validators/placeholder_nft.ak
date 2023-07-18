// placeholder nft for testnet.
use aada/nft.{NFTAction, check_uniqueness}
use aiken/transaction.{Mint, ScriptContext, Transaction}

// 0 - Oracle NFT
// 1 - Delegation NFT
// 2 - Farming NFT
// 3 - Protocol details NFT
validator(_: Int) {
  fn placeholder_nft(r: NFTAction, ctx: ScriptContext) {
    let ScriptContext { transaction: Transaction { inputs, mint, .. }, purpose } =
      ctx
    expect Mint(own_purpose) = purpose
    check_uniqueness(r, inputs, mint, own_purpose)
  }
}
