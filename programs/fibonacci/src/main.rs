#![no_main]

use std::hint::black_box;

sp1_zkvm::entrypoint!(main);

fn fibonacci(n: u32) -> u32 {
    let mut a = 0;
    let mut b = 1;
    for _ in 0..n {
        let sum = a + b % 7919;
        a = b;
        b = sum;
    }
    b
}

pub fn main() {
    let n: u32 = sp1_zkvm::io::read();
    black_box(fibonacci(black_box(n)));
}
