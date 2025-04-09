use benchmark::{benchmark_hardware, calculate_cost_per_cycle};

fn main() {
    let throughput = benchmark_hardware();
    let electricity_rate = 0.10; // Example rate, could be user input
    let cost_per_cycle = calculate_cost_per_cycle(throughput, electricity_rate);

    println!("Cost per cycle: {}", cost_per_cycle);
    // Integrate cost_per_cycle into bidding logic
}