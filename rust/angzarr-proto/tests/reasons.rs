//! The framework's reason keys are the enums of `reasons.proto` (decision
//! 14.44): a key travels as its value's bare name, and every enum reserves
//! every retired key, so none is answered or reused again.

use std::collections::BTreeSet;
use std::path::Path;
use std::process::Command;

use angzarr_proto::v1::{CoordinatorReason, HostReason, RouterReason};
use prost::Message;
use prost_types::FileDescriptorSet;

/// The keys decisions 14.37, 14.39 and 14.42 retired.
const RETIRED: &[&str] = &[
    // 14.37
    "MALFORMED_REFUSAL_FACT",
    "DUPLICATE_REGISTRATION",
    "NO_HANDLER_REGISTERED",
    // 14.39
    "DUPLICATE_UPCASTER_CHAIN",
    "DUPLICATE_COMMAND_HANDLER",
    // 14.42
    "MISSING_COMMAND_BOOK",
    "MISSING_COMMAND_PAGE",
    "MISSING_COMMAND_PAYLOAD",
    "MISSING_EVENT_BOOK_COVER",
    "EMPTY_POLICY_SOURCE",
    "POLICY_SOURCE_OUTSIDE_INPUT_DOMAIN",
    "REFUSAL_FACT_MISSING",
    "REFUSAL_WITHOUT_COMMAND",
    "REFUSAL_WITHOUT_EVENT",
    "REFUSAL_WITHOUT_REFUSED_COMMAND",
    "REFUSED_COMMAND_WITHOUT_ID",
    "REFUSAL_WITHOUT_TRIGGER_STREAM",
    "HOST_STATUS_UNDECODABLE",
    "NULL_ABI_POINTER",
];

/// Every live key of an enum, by name: its values from 1 up, until a
/// number has none (the numbers are dense).
fn names<E>(name: fn(E) -> &'static str) -> Vec<&'static str>
where
    E: TryFrom<i32>,
{
    (1..).map_while(|n| E::try_from(n).ok()).map(name).collect()
}

fn router() -> Vec<&'static str> {
    names::<RouterReason>(|r| r.as_str_name())
}
fn host() -> Vec<&'static str> {
    names::<HostReason>(|r| r.as_str_name())
}
fn coordinator() -> Vec<&'static str> {
    names::<CoordinatorReason>(|r| r.as_str_name())
}

#[test]
fn a_key_travels_as_its_bare_name() {
    assert_eq!(
        RouterReason::DuplicateComponent.as_str_name(),
        "DUPLICATE_COMPONENT"
    );
    assert_eq!(
        HostReason::NoComponentsRegistered.as_str_name(),
        "NO_COMPONENTS_REGISTERED"
    );
    assert_eq!(
        CoordinatorReason::ConflictOverlap.as_str_name(),
        "CONFLICT_OVERLAP"
    );
    assert_eq!(
        RouterReason::from_str_name("UNKNOWN_COMMAND_TYPE"),
        Some(RouterReason::UnknownCommandType)
    );
}

#[test]
fn no_key_carries_its_enums_prefix() {
    for (prefix, keys) in [
        ("ROUTER_REASON_", router()),
        ("HOST_REASON_", host()),
        ("COORDINATOR_REASON_", coordinator()),
    ] {
        assert!(!keys.is_empty(), "{prefix}: no keys");
        for key in keys {
            assert!(!key.starts_with(prefix), "{key}");
            assert!(
                key.chars()
                    .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_'),
                "{key} is not SCREAMING_SNAKE"
            );
        }
    }
}

#[test]
fn the_owners_keys_are_these() {
    assert_eq!(
        host(),
        ["UPCASTER_WITH_COMPONENT", "NO_COMPONENTS_REGISTERED"]
    );
    assert!(router().contains(&"DUPLICATE_COMPONENT"));
    assert!(coordinator().contains(&"PM_NO_INSTANCE"));
    let all: Vec<_> = [router(), host(), coordinator()].concat();
    let distinct: BTreeSet<_> = all.iter().collect();
    assert_eq!(all.len(), distinct.len(), "a key in two enums");
}

/// reasons.proto compiled by protoc into a FileDescriptorSet.
fn descriptor() -> FileDescriptorSet {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../proto");
    let out = Path::new(env!("CARGO_TARGET_TMPDIR")).join("reasons.binpb");
    let protoc = std::env::var("PROTOC").unwrap_or_else(|_| "protoc".into());
    let status = Command::new(protoc)
        .arg(format!("-I{}", root.display()))
        .arg(format!("--descriptor_set_out={}", out.display()))
        .arg("io/angzarr/v1/reasons.proto")
        .status()
        .expect("run protoc");
    assert!(status.success(), "protoc failed on reasons.proto");
    FileDescriptorSet::decode(&*std::fs::read(out).expect("read descriptor set"))
        .expect("a descriptor set")
}

#[test]
fn every_enum_reserves_every_retired_key() {
    let set = descriptor();
    let file = &set.file[0];
    let retired: BTreeSet<&str> = RETIRED.iter().copied().collect();
    let enums: BTreeSet<&str> = file.enum_type.iter().map(|e| e.name()).collect();
    assert_eq!(
        enums,
        ["CoordinatorReason", "HostReason", "RouterReason"].into()
    );
    for e in &file.enum_type {
        let reserved: BTreeSet<&str> = e.reserved_name.iter().map(String::as_str).collect();
        assert_eq!(reserved, retired, "{}", e.name());
        assert!(
            e.reserved_range.is_empty(),
            "{}: numbers are bookkeeping",
            e.name()
        );
        for v in &e.value {
            assert!(!retired.contains(v.name()), "{} is retired", v.name());
        }
    }
}
