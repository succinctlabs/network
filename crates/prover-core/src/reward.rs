/// Calculate the cost in USDC for a given number of cycles.
pub fn calculate_cycle_cost(gas_price: u64, cycles: u64) -> Result<BigDecimal, String> {
    let usdc_units = (cycles + gas_price - 1) / gas_price;
    BigDecimal::from_str(&usdc_units.to_string())
        .map_err(|e| format!("failed to convert cost to BigDecimal: {}", e))
}
