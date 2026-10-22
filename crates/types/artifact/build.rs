fn main() {
    println!("cargo:rerun-if-changed=../../../proto");
    let config = tonic_prost_build::configure();
    config
        .protoc_arg("--experimental_allow_proto3_optional")
        .out_dir("src")
        .type_attribute(".", "#[derive(serde::Serialize,serde::Deserialize)]")
        .compile_protos(&["../../../proto/artifact.proto"], &["../../../proto"])
        .unwrap();
}
