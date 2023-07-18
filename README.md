# Aada finance



## Building

```
python3 deploy.py
```
Deploy parameterized contracts.

## Generating Credentials

```
deno run --A generate-credentials.ts
```

Fund the wallet with ADA. Loans and collateral is ADA so no other tokens are needed. You can always mint new oracle UTXOs+NFT for reference

## Creating pool
```
deno run -A pool_create.ts  5000000 2
```
Will lock 5 ADA to pool. Where `2` is a consumed UTXO index. If you are doing it first time - update latest_borrow_tx.txt with your wallet latest utxo ref.

## Borrowing
```
deno run -A pool_borrow.ts 2000000 2100000
```
Will take a loan of 2 ADA and leave collateral of 2.1 ADA

## Repaying
```
deno run -A pool_repay.ts
```
Will repay the latest loan

## Deposit
```
deno run -A pool_deposit.ts 5000000
```
Will deposit 5 ADA to already existing pool


## Liquidating
```
deno run -A pool_liquidate.ts
```
Will liquidate the latest loan. Will work only if loan is undercollaterized. Which means you need to mint new NFTs to 'decrease' collateral value over loan. You have to mint them after took the loan since otherwise you can't take the undercollaterized loan.
