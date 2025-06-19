//! Succinct Prover Network Verifiable Application Core Library.
//!
//! The system is designed as a verifiable application (vApp), meaning it uses a RISC-V zkVM like
//! SP1 to generate proofs for its state-transition function. It interacts with an Ethereum L1 smart
//! contract to manage balances and maintain system state.

#![warn(clippy::pedantic)]
#![allow(clippy::similar_names)]
#![allow(clippy::cast_possible_wrap)]
#![allow(clippy::cast_possible_truncation)]
#![allow(clippy::cast_sign_loss)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::needless_range_loop)]
#![allow(clippy::cast_lossless)]
#![allow(clippy::bool_to_int_with_if)]
#![allow(clippy::field_reassign_with_default)]
#![allow(clippy::manual_assert)]
#![allow(clippy::unreadable_literal)]
#![allow(clippy::match_wildcard_for_single_variants)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::explicit_iter_loop)]
#![allow(clippy::struct_excessive_bools)]
#![warn(missing_docs)]

pub mod errors;
pub mod fee;
pub mod input;
pub mod merkle;
pub mod receipts;
pub mod signing;
pub mod sol;
pub mod sparse;
pub mod state;
pub mod storage;
pub mod transactions;
pub mod u256;
pub mod utils;
pub mod verifier;
