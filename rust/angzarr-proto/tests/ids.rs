//! The wire `UUID` boundary helpers and the UUIDv5 derivations
//! (types.proto, `uuid` and `derived_ids` regions). Expected derived values
//! were computed independently with Python's `uuid.uuid5`, and match the
//! examples documented in the proto.

use angzarr_proto::ids::{
    compute_root, fact_correlation, fingerprint, UuidError, FACT_CORRELATION_NAMESPACE,
    FINGERPRINT_NAMESPACE, ROOT_NAMESPACE,
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
    assert_eq!(
        FINGERPRINT_NAMESPACE.to_string(),
        "a749bd8c-7bf0-47e6-a5c9-dc54ebde74aa"
    );
    assert_ne!(ROOT_NAMESPACE, FACT_CORRELATION_NAMESPACE);
    assert_ne!(ROOT_NAMESPACE, FINGERPRINT_NAMESPACE);
    assert_ne!(FACT_CORRELATION_NAMESPACE, FINGERPRINT_NAMESPACE);
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

const DEPOSIT: &str = "type.googleapis.com/examples.Deposit";

#[test]
fn fingerprint_matches_the_documented_worked_example() {
    // Name: 00000024 (36, big-endian) ++ the type URL ++ 08 2a.
    let fp = fingerprint(DEPOSIT, &[0x08, 0x2a]);
    assert_eq!(fp.to_string(), "6d42fa9e-0dca-5047-94b1-0ae371532630");
    assert_eq!(fp.value[6] >> 4, 5);
    assert_eq!(fp.value[8] >> 6, 0b10);

    // It is UUIDv5 of exactly that name under the fingerprint namespace.
    let mut name = vec![0, 0, 0, 0x24];
    name.extend_from_slice(DEPOSIT.as_bytes());
    name.extend_from_slice(&[0x08, 0x2a]);
    assert_eq!(
        fp,
        Uuid::from(RustUuid::new_v5(&FINGERPRINT_NAMESPACE, &name))
    );

    // The other documented values: an empty value, and an empty Any.
    assert_eq!(
        fingerprint(DEPOSIT, &[]).to_string(),
        "838a6be3-ad9d-5945-be34-61ec4c3d6432"
    );
    assert_eq!(
        fingerprint("", &[]).to_string(),
        "d0be6173-febd-50a7-a4fe-d083d14497ca"
    );
}

#[test]
fn fingerprint_separates_payloads_and_the_type_url_boundary() {
    // A changed payload changes the fingerprint.
    assert_eq!(
        fingerprint(DEPOSIT, &[0x08, 0x2b]).to_string(),
        "680f6433-0548-5517-8ff5-7388f094bdbd"
    );
    // Moving a byte across the type URL / value boundary changes the name
    // (the length prefix), so it changes the fingerprint.
    let shifted = fingerprint("type.googleapis.com/examples.Deposi", b"t\x08\x2a");
    assert_eq!(shifted.to_string(), "c1f6b1e1-204d-5278-b6b8-b10f092ccd3f");
    assert_ne!(shifted, fingerprint(DEPOSIT, &[0x08, 0x2a]));
    // A fingerprint lives in its own namespace: never a root or correlation
    // of the same text.
    assert_ne!(fingerprint(DEPOSIT, &[]), fact_correlation(DEPOSIT));
}
