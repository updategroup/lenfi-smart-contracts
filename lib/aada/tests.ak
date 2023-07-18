use aada/finance
use aada/rats

/// We could do with more of these
test test_interest_amount() {
  let interest_rate = 400000
  let loan_amount = 100000000
  let current_ts = 1681098024000
  let loan_start_ts = 1680925224000
  (rats.truncate(
    finance.calculate_interest_amount(
      interest_rate,
      loan_amount,
      loan_start_ts,
      current_ts,
    ),
  ) == 219178)?
}

test health_factor() {
  let liquidation_threshold = 1600000
  let collateral_value = 1300000
  let value_in_debt = 1000000
  rats.div_int(
    collateral_value * 1000000000000,
    liquidation_threshold * value_in_debt,
  )
    |> rats.eq(rats.from_int(812500))
}
