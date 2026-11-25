//! The package's directories hold the spec it ships.

#[test]
fn test_proto_dir_holds_the_angzarr_v1_protos() {
    assert!(angzarr_project::proto_dir().join("io/angzarr/v1").is_dir());
}

#[test]
fn test_features_dir_holds_the_handler_contract() {
    assert!(angzarr_project::features_dir()
        .join("handler-contract")
        .is_dir());
}

#[test]
fn test_dir_constants_name_the_same_paths_as_the_functions() {
    assert_eq!(
        angzarr_project::proto_dir(),
        std::path::Path::new(angzarr_project::PROTO_DIR)
    );
    assert_eq!(
        angzarr_project::features_dir(),
        std::path::Path::new(angzarr_project::FEATURES_DIR)
    );
}
