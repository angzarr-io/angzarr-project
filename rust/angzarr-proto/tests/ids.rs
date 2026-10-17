//! The wire `UUID` boundary helpers and the UUIDv5 derivations
//! (types.proto, `uuid` and `derived_ids` regions). Expected derived values
//! were computed independently with Python's `uuid.uuid5`, and match the
//! examples documented in the proto.

use angzarr_proto::ids::{
    compute_root, fact_correlation, UuidError, FACT_CORRELATION_NAMESPACE, ROOT_NAMESPACE,
};
use angzarr_proto::uuid::Uuid as RustUuid;
use angzarr_proto::v1::Uuid;

const TEXT: &str = "01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f";
const BYTES: [u8; 16] = [
    0x01, 0x92, 0x0c, 0x8e, 0x7b, 0x3a, 0x7c, 0xc2, 0x9f, 0x4e, 0x5a, 0x1b, 0x2c, 0x3d, 0x4e, 0x5f,
];

#[test]
fn the_namespaces_are_the_documented_values() {
    assert_eq!(
        ROOT_NAMESPACE.to_string(),
        "d4741b1a-52cd-43cf-add1-3dbb9615510b"
    );
    assert_eq!(
        FACT_CORRELATION_NAMESPACE.to_string(),
        "e9ef0ae2-6fc6-4c14-b713-ef03971dd867"
    );
    assert_ne!(ROOT_NAMESPACE, FACT_CORRELATION_NAMESPACE);
}

#[test]
fn text_round_trips_through_canonical_lowercase() {
    let id: Uuid = TEXT.parse().unwrap();
    assert_eq!(id.value, BYTES);
    assert_eq!(id.to_string(), TEXT);

    // Input accepts either case; output is always lowercase.
    let upper: Uuid = TEXT.to_uppercase().parse().unwrap();
    assert_eq!(upper, id);
    assert_eq!(upper.to_string(), TEXT);
}

#[test]
fn only_the_hyphenated_form_parses() {
    for bad in [
        "",
        "01920c8e7b3a7cc29f4e5a1b2c3d4e5f",              // simple
        "{01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f}",        // braced
        "urn:uuid:01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f", // URN
        "01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5g",          // not hex
        "01920c8e7-b3a-7cc2-9f4e-5a1b2c3d4e5f",          // misplaced hyphen
        "invalid-uuid:00",                               // the malformed display
    ] {
        assert_eq!(bad.parse::<Uuid>(), Err(UuidError::Text), "{bad:?}");
    }
}

#[test]
fn bytes_and_uuid_crate_conversions_are_lossless() {
    let id = Uuid::from(BYTES);
    assert_eq!(id, Uuid::from_bytes(BYTES));
    assert_eq!(<[u8; 16]>::try_from(&id), Ok(BYTES));
    assert!(id.is_well_formed());

    let rust = RustUuid::try_from(&id).unwrap();
    assert_eq!(rust.as_bytes(), &BYTES);
    assert_eq!(Uuid::from(rust), id);
}

#[test]
fn a_malformed_wire_value_is_reported_and_never_canonical() {
    for len in [0usize, 15, 17] {
        let id = Uuid {
            value: vec![0xab; len],
        };
        assert!(!id.is_well_formed());
        assert_eq!(id.to_bytes(), Err(UuidError::Length(len)));
        assert_eq!(RustUuid::try_from(&id), Err(UuidError::Length(len)));
        let shown = id.to_string();
        assert_eq!(shown, format!("invalid-uuid:{}", "ab".repeat(len)));
        assert!(shown.parse::<Uuid>().is_err());
    }
}

#[test]
fn compute_root_is_uuidv5_of_domain_colon_key() {
    let root = compute_root("player", "alice@example.com").unwrap();
    assert_eq!(root.to_string(), "cfe936c0-2912-5ca9-96e6-f37c0b441759");
    // Version 5, RFC 9562 variant.
    assert_eq!(root.value[6] >> 4, 5);
    assert_eq!(root.value[8] >> 6, 0b10);

    // The key may hold ':'; the domain may not.
    assert_eq!(
        compute_root("orders", "a:b").unwrap().to_string(),
        "83100d05-781b-57aa-810f-d03c4de94c2a"
    );
    assert_eq!(
        compute_root("orders:a", "b"),
        Err(UuidError::DomainContainsColon)
    );

    // Deterministic, and the domain separates keys.
    assert_eq!(compute_root("player", "x"), compute_root("player", "x"));
    assert_ne!(compute_root("player", "x"), compute_root("table", "x"));
}

#[test]
fn fact_correlation_is_uuidv5_of_external_id_in_its_own_namespace() {
    let corr = fact_correlation("pi_1234");
    assert_eq!(corr.to_string(), "917f26ae-ea2e-58af-86de-77013a69617e");
    assert_eq!(corr.value[6] >> 4, 5);

    // The same name never yields a root: the namespaces differ.
    let name_also_a_root = fact_correlation("player:alice@example.com");
    assert_eq!(
        name_also_a_root.to_string(),
        "2ec2813e-ec7f-5921-8931-a86b44493ffc"
    );
    assert_ne!(
        Some(name_also_a_root),
        compute_root("player", "alice@example.com").ok()
    );
}
