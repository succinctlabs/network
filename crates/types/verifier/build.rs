extern crate prost_build;
extern crate tonic_build;

fn main() {
    println!("cargo:rerun-if-changed=../../../proto");
    let config = tonic_build::configure();
    config
        .protoc_arg("--experimental_allow_proto3_optional")
        .out_dir("src")
        .type_attribute(".", "#[derive(serde::Serialize,serde::Deserialize)]")
        .compile(&["../../../proto/verifier.proto"], &["../../../proto"])
        .unwrap();
}
