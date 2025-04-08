use lazy_static::lazy_static;
use spn_network_types::ProofMode;
use sqlx::types::BigDecimal;
use std::str::FromStr;

lazy_static! {
    /// Base fee for core proof mode (0.01 USDC = 10_000).
    pub static ref CORE_BASE_FEE: BigDecimal = BigDecimal::new(10_000.into(), 0);
    /// Base fee for compressed proof mode (0.03 USDC = 30_000).
    pub static ref COMPRESSED_BASE_FEE: BigDecimal = BigDecimal::new(30_000.into(), 0);
    /// Base fee for groth16/plonk proof modes (0.05 USDC = 50_000).
    pub static ref EVM_BASE_FEE: BigDecimal = BigDecimal::new(50_000.into(), 0);
}

/// Get the base fee for the proof mode.
pub fn get_base_fee(mode: i32) -> &'static BigDecimal {
    match ProofMode::try_from(mode).unwrap_or(ProofMode::Core) {
        ProofMode::Core => &CORE_BASE_FEE,
        ProofMode::Compressed => &COMPRESSED_BASE_FEE,
        ProofMode::Groth16 | ProofMode::Plonk => &EVM_BASE_FEE,
        _ => &CORE_BASE_FEE,
    }
}

/// Calculate the cost in USDC for a given number of cycles or gas without the base fee.
///
/// In older versions of SP1, we only passed in cycles. So we fall back to using cycles for unit
/// pricing. If *everyone* updated SP1 to latest, technically we could remove this behavior and only
/// every need to worry about gas.
pub fn calculate_gas_cost(price: u64, cycles: u64, _gas: u64) -> Result<BigDecimal, String> {
    // // If gas is not provided, use cycles instead.
    // let units = if gas == 0 { cycles } else { gas };

    // TODO: switch to pricing based on gas
    let units = cycles;
    if price == 0 || units == 0 {
        return Ok(BigDecimal::from(0));
    }

    let usdc_units = (units + price - 1) / price;
    BigDecimal::from_str(&usdc_units.to_string())
        .map_err(|e| format!("failed to convert cost to BigDecimal: {}", e))
}

/// Calculate the cost of a request in USDC units.
pub fn calculate_request_cost(
    price: u64,
    cycles: u64,
    gas: u64,
    proof_mode: i32,
) -> Result<BigDecimal, String> {
    let base_fee = get_base_fee(proof_mode);
    let cycle_cost = calculate_gas_cost(price, cycles, gas)?;
    Ok(base_fee + cycle_cost)
}

/// Formats a USDC amount (with 6 decimals) as a USD string with 2 decimal places.
pub fn format_usdc_as_credits(usdc_amount: &BigDecimal) -> String {
    // Convert from USDC (6 decimals) to USD by dividing by 1_000_000.
    let credits = usdc_amount.to_string().parse::<f64>().unwrap_or(0.0) / 1_000_000.0;
    // Handle negative values (should never happen).
    if credits < 0.0 {
        format!("-{:.2}", credits.abs())
    } else {
        format!("{:.2}", credits)
    }
}

// #[cfg(test)]
// mod tests {
//     use super::*;

//     /// Number of gas that can be executed per USDC unit.
//     ///
//     /// For 1M gas to cost $0.01:
//     /// - Need 10_000 USDC units (0.01 with 6 decimal precision)
//     /// - Therefore 1M gas costs 10_000 USDC units
//     /// - So 100 gas costs 1 USDC unit.
//     const GAS_PRICE: u64 = 100;

//     /// Test gas cost calculation with both gas and cycles parameters.
//     #[test]
//     fn test_gas_cost_calculation() {
//         let test_cases = vec![
//             // gas_used, expected_usdc_units (6 decimals), expected_display
//             (1_000_000, "10000", "$0.01"), // 1M gas should cost $0.01
//             (2_000_000, "20000", "$0.02"), // 2M gas should cost $0.02
//             (500_000, "5000", "$0.01"),    // 500k gas should cost $0.005, displays as $0.01
//             (100_000_000, "1000000", "$1.00"), // 100M gas should cost $1.00
//         ];

//         for (gas_used, expected_usdc_units, expected_display) in test_cases {
//             // Test gas cost calculation when gas is provided
//             let cost = calculate_gas_cost(GAS_PRICE, 0, gas_used).unwrap();
//             let expected_cost = BigDecimal::from_str(expected_usdc_units).unwrap();

//             assert_eq!(
//                 cost, expected_cost,
//                 "Incorrect USDC units for {} gas. Expected {}, got {}.",
//                 gas_used, expected_usdc_units, cost
//             );

//             // Test gas cost calculation when cycles is provided but gas is 0
//             let cycle_cost = calculate_gas_cost(GAS_PRICE, gas_used, 0).unwrap();

//             assert_eq!(
//                 cycle_cost, expected_cost,
//                 "Incorrect USDC units for {} cycles with gas=0. Expected {}, got {}.",
//                 gas_used, expected_usdc_units, cycle_cost
//             );

//             // Test display formatting
//             let formatted = format_usdc_as_credits(&cost);
//             assert_eq!(
//                 formatted, expected_display,
//                 "Incorrect display format for {} gas. Expected {}, got {}.",
//                 gas_used, expected_display, formatted
//             );
//         }

//         // Test when both gas and cycles are provided - gas should be used
//         let gas_cost = calculate_gas_cost(GAS_PRICE, 500_000, 1_000_000).unwrap();
//         let expected_gas_cost = BigDecimal::from_str("10000").unwrap(); // Based on 1M gas

//         assert_eq!(
//             gas_cost, expected_gas_cost,
//             "When both gas and cycles are provided, gas should be used. Expected {}, got {}.",
//             expected_gas_cost, gas_cost
//         );

//         // Test when price is 0
//         let zero_price_cost = calculate_gas_cost(0, 1_000_000, 1_000_000).unwrap();
//         assert_eq!(
//             zero_price_cost,
//             BigDecimal::from(0),
//             "When price is 0, cost should be 0. Got {}.",
//             zero_price_cost
//         );

//         // Test when both gas and cycles are 0
//         let zero_units_cost = calculate_gas_cost(GAS_PRICE, 0, 0).unwrap();
//         assert_eq!(
//             zero_units_cost,
//             BigDecimal::from(0),
//             "When both gas and cycles are 0, cost should be 0. Got {}.",
//             zero_units_cost
//         );
//     }

//     /// Test the request cost calculation combining base fee and gas cost.
//     #[test]
//     fn test_request_cost_calculation() {
//         // Test with different proof modes
//         let test_cases = vec![
//             // price, cycles, gas, proof_mode, expected_total_cost
//             (GAS_PRICE, 0, 1_000_000, ProofMode::Core as i32, "20000"), /* 10000 (base) + 10000
//                                                                          * (gas) */
//             (GAS_PRICE, 0, 1_000_000, ProofMode::Compressed as i32, "40000"), /* 30000 (base) +
//                                                                                * 10000 (gas) */
//             (GAS_PRICE, 0, 1_000_000, ProofMode::Groth16 as i32, "60000"), /* 50000 (base) +
//                                                                             * 10000 (gas) */
//             (GAS_PRICE, 1_000_000, 0, ProofMode::Core as i32, "20000"), /* 10000 (base) + 10000
//                                                                          * (cycles) */
//             (GAS_PRICE, 2_000_000, 0, ProofMode::Plonk as i32, "70000"), /* 50000 (base) + 20000
//                                                                           * (cycles) */
//         ];

//         for (price, cycles, gas, proof_mode, expected_total) in test_cases {
//             let cost = calculate_request_cost(price, cycles, gas, proof_mode).unwrap();
//             let expected = BigDecimal::from_str(expected_total).unwrap();

//             assert_eq!(
//                 cost, expected,
//                 "Incorrect total cost for proof_mode={}, price={}, cycles={}, gas={}. Expected
// {}, got {}.",                 proof_mode, price, cycles, gas, expected_total, cost
//             );
//         }
//     }

//     #[test]
//     fn test_format_usdc_as_credits() {
//         let test_cases = vec![
//             // USDC units (6 decimals), expected display
//             ("10000", "$0.01"),     // $0.01 (1 cent)
//             ("100000", "$0.10"),    // $0.10 (10 cents)
//             ("1000000", "$1.00"),   // $1.00
//             ("1500000", "$1.50"),   // $1.50
//             ("500", "$0.00"),       // Should round to $0.00
//             ("0", "$0.00"),         // Zero
//             ("-1000000", "-$1.00"), // Negative values should work too
//         ];

//         for (usdc_units, expected) in test_cases {
//             let amount = BigDecimal::from_str(usdc_units).unwrap();
//             let formatted = format_usdc_as_credits(&amount);
//             assert_eq!(
//                 formatted, expected,
//                 "Incorrect formatting for {} USDC units. Expected {}, got {}",
//                 usdc_units, expected, formatted
//             );
//         }
//     }
// }
