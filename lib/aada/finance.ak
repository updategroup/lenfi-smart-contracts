use aada/rats.{Rational}

/// Calculate interest amount 
pub fn calculate_interest_amount(
  interest_rate: Int,
  loan_amount: Int,
  loan_start_ts: Int,
  current_ts: Int,
) -> Rational {
  loan_amount * interest_rate * ( current_ts - loan_start_ts )
    |> rats.div_int(31536000000 * 1000000)
}

/// Get amount of expected deposit when LP tokens are present
pub fn get_expected_deposit_amount(
  lp_tokens_amount: Int,
  balance: Int,
  lent_out: Int,
  total_lp_tokens: Int,
) -> Rational {
  lp_tokens_amount * ( balance + lent_out )
    |> rats.div_int(total_lp_tokens)
}

/// Calculate the return from selling tokens
pub fn calculate_sale(
  sell_amount: Rational,
  token_1_amount: Int,
  token_2_amount: Int,
) -> Int {
  sell_amount
    |> rats.mul(997 * token_1_amount |> rats.from_int)
    |> rats.div(
         token_2_amount * 1000
           |> rats.from_int
           |> rats.add(997 |> rats.from_int |> rats.mul(sell_amount)),
       )
    |> rats.truncate
}

/// Calculate the ada required to purchase tokens
pub fn ada_for_purchase(
  buy_amount: Rational,
  token_1_amount: Int,
  token_2_amount: Int,
) -> Int {
  buy_amount
    |> rats.mul(1000 * token_1_amount |> rats.from_int)
    |> rats.div(
         token_2_amount
           |> rats.from_int
           |> rats.sub(buy_amount)
           |> rats.mul(997 |> rats.from_int),
       )
    |> rats.truncate
}

/// Calculate the asset you'd get for selling ada
pub fn asset_gain_adasale(
  ada_sell_amount: Int,
  token_1_amount: Int,
  token_2_amount: Int,
) {
  ada_sell_amount * 997 * token_2_amount
    |> rats.div_int(token_1_amount * 1000 + ada_sell_amount * 997)
    |> rats.truncate
}

/// Calculate health from debt,collat,threshold
pub fn calculate_health_factor(debt: Int, collateral: Int, threshold: Int) {
  collateral * 1000000000000
    |> rats.div_int(threshold * debt)
}

/// Health factor >= 100%
pub fn check_is_overcollaterized(
  value_in_debt: Int,
  collateral_value: Int,
  liquidation_threshold: Int,
) -> Bool {
  // Check if loan is overcollaterized. Meaning 'value' in debt is large enought compared to collateral factor.
  let over_collateralized =
    calculate_health_factor(
      value_in_debt,
      collateral_value,
      liquidation_threshold,
    )
      |> rats.ge(1000000 |> rats.from_int)
  over_collateralized?
}

/// Health factor < 100%
pub fn check_is_undercollaterized(
  value_in_debt: Int,
  collateral_value: Int,
  liquidation_threshold: Int,
) {
  let under_collateralized =
    calculate_health_factor(
      value_in_debt,
      collateral_value,
      liquidation_threshold,
    )
      |> rats.lt(1000000 |> rats.from_int)
  under_collateralized?
}

/// Calculate interest rates for a loan
pub fn get_interest_rates(
  loan_amount: Int,
  lent_out: Int,
  balance: Int,
) -> Rational {
  // These are parameters hardcoded into contract. It can be moved to referencable UTXO 
  // in order to be updatable, but with the same validator hash
  let optimal_utilization = 450000
  let base_interest_rate = 30000
  let rslope1 = 75000
  let rslope2 = 300000
  let utilization_rate =
    rats.div_int(( lent_out + loan_amount ) * 1000000, balance + lent_out)
  if utilization_rate |> rats.le(rats.from_int(optimal_utilization)) {
    let utilization_charge =
      utilization_rate
        |> rats.mul(rats.div_int(rslope1, optimal_utilization))
    base_interest_rate
      |> rats.from_int
      |> rats.add(utilization_charge)
  } else {
    let base_rate = base_interest_rate + rslope1
    let optimal_rate =
      utilization_rate
        |> rats.sub(optimal_utilization |> rats.from_int)
        |> rats.mul(rslope2 |> rats.div_int(1000000 - optimal_utilization))
        |> rats.mul(1000000 |> rats.from_int)
    let interest_rate =
      optimal_rate
        |> rats.div(1000000 |> rats.from_int)
        |> rats.add(base_rate |> rats.from_int)
    interest_rate
  }
}

/// Calculate the discount someone gets for swapping ada stake profits for the pool deposit asset.
/// This is to incentivise bots to execute trades for us.
pub fn calculate_tokenswap_discount(expected_deposit_amount: Int) -> Rational {
  expected_deposit_amount
    |> rats.from_int
    |> rats.mul(rats.div_int(1000000 - 7500, 1000000))
}
