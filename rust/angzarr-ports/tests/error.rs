//! One error, stable codes (RULED(14) in contract.rs). The codes, args,
//! recovery and English, and its size.

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

fn other() -> Cover {
    Cover {
        root: Some(v1::Uuid::from_bytes([8; 16])),
        ..stream()
    }
}

fn stream_in(edition: &str) -> Cover {
    Cover {
        edition: Some(edition.to_string()),
        ..stream()
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
            StoreError::conflict(stream(), 1, 2),
            "angzarr-ports-store-conflict",
            Retry,
        ),
        (
            StoreError::discontinuous(stream(), 2, 3),
            "angzarr-ports-store-discontinuous",
            Bug,
        ),
        (
            StoreError::malformed_stream(stream()),
            "angzarr-ports-store-malformed-stream",
            Invalid,
        ),
        (
            StoreError::Unavailable(io()),
            "angzarr-ports-store-unavailable",
            Retry,
        ),
        (
            StoreError::unreadable(stream(), 4, io()),
            "angzarr-ports-store-unreadable",
            Bug,
        ),
        (
            StoreError::unknown_edition(stream()),
            "angzarr-ports-store-unknown-edition",
            Invalid,
        ),
        (
            StoreError::EditionNameRequired,
            "angzarr-ports-edition-name-required",
            Invalid,
        ),
        (
            StoreError::EditionNotFound { name: name() },
            "angzarr-ports-edition-not-found",
            Invalid,
        ),
        (
            StoreError::edition_not_deleted(stream_in("what-if")),
            "angzarr-ports-store-edition-not-deleted",
            Bug,
        ),
        (
            StoreError::edition_not_propagated(stream_in("what-if")),
            "angzarr-ports-store-edition-not-propagated",
            Retry,
        ),
        (
            StoreError::edition_not_forked(stream_in("what-if")),
            "angzarr-ports-store-edition-not-forked",
            Invalid,
        ),
        (
            StoreError::edition_already_forked(stream_in("what-if")),
            "angzarr-ports-store-edition-already-forked",
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
    let conflict = StoreError::conflict(stream(), 1, 2);
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
    let text = StoreError::conflict(stream(), 1, 2).to_string();
    for part in ["account/07070707-0707-0707-0707-070707070707", "1", "2"] {
        assert!(text.contains(part), "{text:?} names {part}");
    }
}

/// The editions' refusals carry their streams, as args and in the
/// English.
#[test]
fn the_new_refusals_name_their_streams() {
    let root = |n: u8| format!("{n:02x}").repeat(4);
    let text = |n: u8| {
        let r = root(n);
        format!(
            "{}-{}-{}-{}-{}",
            r,
            &r[..4],
            &r[..4],
            &r[..4],
            r.clone() + &r[..4]
        )
    };
    let s = format!("account/{}", text(7));
    let e = format!("{s}@what-if");
    for refusal in [
        StoreError::edition_not_forked(stream_in("what-if")),
        StoreError::edition_already_forked(stream_in("what-if")),
        StoreError::edition_not_deleted(stream_in("what-if")),
        StoreError::edition_not_propagated(stream_in("what-if")),
    ] {
        assert_eq!(refusal.args(), vec![("stream", Arg::Str(e.clone()))]);
        assert!(refusal.to_string().contains(&e), "{refusal}");
    }
}

/// The streams are boxed (owner ruling, 2026-10-28) so the error stays
/// small: every `Result<_, StoreError>` carries it. The bound is the boxed
/// layout's: the largest variant is `Unreadable` (a box, a sequence and a
/// `Cause` of a `&'static str` and a `String`: 8 + 8 + 16 + 24 = 56 bytes),
/// whose niche holds the discriminant, so 56; 64 leaves a word to spare and
/// stops it silently growing back.
#[test]
fn the_error_stays_small() {
    assert!(
        std::mem::size_of::<StoreError>() <= 64,
        "StoreError is {} bytes",
        std::mem::size_of::<StoreError>()
    );
}

/// The constructors and the accessor hide the box.
#[test]
fn the_stream_is_read_without_the_box() {
    assert_eq!(
        StoreError::conflict(stream(), 1, 2).stream(),
        Some(&stream())
    );
    assert_eq!(
        StoreError::edition_not_propagated(other()).stream(),
        Some(&other())
    );
    assert_eq!(StoreError::EditionNameRequired.stream(), None);
}
