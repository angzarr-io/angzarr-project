//! One error, stable codes (OPEN(14) in contract.rs). Red because the codes,
//! args, recovery and English are stubbed.

use std::collections::BTreeSet;

use angzarr_ports::angzarr_proto::v1::{self, Cover};
use angzarr_ports::{Arg, Cause, Recovery, StoreError};

fn stream() -> Cover {
    Cover {
        domain: "account".to_string(),
        root: Some(v1::Uuid::from_bytes([7; 16])),
        edition: None,
    }
}

fn io() -> Cause {
    Cause::new("annals-store-sql-io", "disk I/O error")
}

/// One of every variant, with its pinned code and recovery.
fn every() -> Vec<(StoreError, &'static str, Recovery)> {
    use Recovery::*;
    let name = || "what-if".to_string();
    vec![
        (
            StoreError::Conflict {
                stream: stream(),
                expected: 1,
                actual: 2,
            },
            "angzarr-ports-store-conflict",
            Retry,
        ),
        (
            StoreError::Discontinuous {
                stream: stream(),
                expected: 2,
                found: 3,
            },
            "angzarr-ports-store-discontinuous",
            Bug,
        ),
        (
            StoreError::MalformedStream { stream: stream() },
            "angzarr-ports-store-malformed-stream",
            Invalid,
        ),
        (
            StoreError::Unavailable(io()),
            "angzarr-ports-store-unavailable",
            Retry,
        ),
        (
            StoreError::Unreadable {
                stream: stream(),
                sequence: 4,
                reason: io(),
            },
            "angzarr-ports-store-unreadable",
            Bug,
        ),
        (
            StoreError::UnknownEdition { stream: stream() },
            "angzarr-ports-store-unknown-edition",
            Invalid,
        ),
        (
            StoreError::EditionNameRequired,
            "angzarr-ports-edition-name-required",
            Invalid,
        ),
        (
            StoreError::EditionExists { name: name() },
            "angzarr-ports-edition-exists",
            Invalid,
        ),
        (
            StoreError::EditionNotFound { name: name() },
            "angzarr-ports-edition-not-found",
            Invalid,
        ),
        (
            StoreError::EditionStoreUnknown {
                name: name(),
                store: "redis".to_string(),
            },
            "angzarr-ports-edition-store-unknown",
            Invalid,
        ),
        (
            StoreError::EditionDivergesInTheFuture { name: name() },
            "angzarr-ports-edition-diverges-in-the-future",
            Invalid,
        ),
    ]
}

/// A code is stable: these exact strings, kebab-case, prefixed with the
/// crate's name, each used once. A code whose meaning changes gets a new one.
#[test]
fn every_error_has_its_stable_code() {
    let mut seen = BTreeSet::new();
    for (error, code, _) in every() {
        assert_eq!(error.code(), code, "{error:?}");
        assert!(code.starts_with("angzarr-ports-"), "{code}");
        assert!(
            code.chars().all(|c| c.is_ascii_lowercase() || c == '-'),
            "{code} is kebab-case"
        );
        assert!(seen.insert(code), "{code} used twice");
    }
}

/// A conflict and an outage are retried; a gap and an unreadable event
/// are bugs; a bad name or stream is the caller's to fix.
#[test]
fn every_error_says_how_to_recover() {
    for (error, _, recovery) in every() {
        assert_eq!(error.recovery(), recovery, "{error:?}");
    }
}

/// Args carry data, never English: the numbers as numbers, the stream as
/// its text form, a cause nested whole.
#[test]
fn args_carry_the_data_by_name() {
    let conflict = StoreError::Conflict {
        stream: stream(),
        expected: 1,
        actual: 2,
    };
    assert_eq!(
        conflict.args(),
        vec![
            (
                "stream",
                Arg::Str("account/07070707-0707-0707-0707-070707070707".to_string())
            ),
            ("expected", Arg::Uint(1)),
            ("actual", Arg::Uint(2)),
        ]
    );
    assert_eq!(
        StoreError::Unavailable(io()).args(),
        vec![("cause", Arg::Cause(io()))]
    );
    assert_eq!(StoreError::EditionNameRequired.args(), vec![]);
}

/// The English fallback names what the args name, for logs.
#[test]
fn the_english_names_the_stream_and_the_numbers() {
    let text = StoreError::Conflict {
        stream: stream(),
        expected: 1,
        actual: 2,
    }
    .to_string();
    for part in ["account/07070707-0707-0707-0707-070707070707", "1", "2"] {
        assert!(text.contains(part), "{text:?} names {part}");
    }
}
