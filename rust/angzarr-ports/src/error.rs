//! One error for every port, with stable codes.
//!
//! In annals_diagnostic's style without depending on it (annals_diagnostic
//! lives in the annals repository, and the ports must not depend on annals):
//! every error has a stable kebab-case [`code`](StoreError::code) starting
//! with this crate's name, named [`args`](StoreError::args) that carry data
//! and never English, and an English `Display` as the fallback. annals'
//! `Diagnostic` impl for its own errors forwards a wrapped `StoreError`'s
//! code and args unchanged (the orphan rule keeps the impl on annals' side,
//! on the type that wraps it); core maps the codes to gRPC statuses.

use std::fmt;

use angzarr_proto::v1::Cover;

/// Why a store refused or failed. A refusal it is sure of and a failure to
/// answer are different variants: a [`Conflict`](StoreError::Conflict)
/// means "re-read and run again"; [`Unavailable`](StoreError::Unavailable)
/// means "the store could not say".
#[derive(Clone, PartialEq, Eq, Debug)]
#[non_exhaustive]
pub enum StoreError {
    /// Someone else appended first: the stream is at `actual`, not
    /// `expected`. Nothing was appended. Core's `SequenceConflict`.
    Conflict {
        stream: Cover,
        expected: u64,
        actual: u64,
    },
    /// The pages do not continue the stream: sequence `found` where
    /// `expected` was due. A caller bug; nothing was appended.
    Discontinuous {
        stream: Cover,
        expected: u64,
        found: u64,
    },
    /// A wire `Cover` that is no stream: no root, a root not 16 bytes, or an
    /// edition set to the empty string (INVALID_ARGUMENT).
    MalformedStream { stream: Cover },
    /// The store failed: I/O, a timeout, a dropped connection, a schema this
    /// build cannot read. A write may or may not have landed.
    Unavailable(Cause),
    /// The store holds event `sequence` of `stream` but cannot give it back:
    /// bytes that do not decode as an `EventPage`, a row with metadata
    /// missing. Upcasting is never the store's: an unknown payload type is
    /// not this.
    Unreadable {
        stream: Cover,
        sequence: u64,
        reason: Cause,
    },
    /// A second unit of work was begun on a handle that cannot serve two
    /// at once (one SQLite connection, already in a unit). Refused at once,
    /// never waited on: the unit already open may belong to the caller.
    UnitBusy,
    /// A stream in an edition the store never created, where only created
    /// editions are accepted (EA-2: NOT_FOUND). Nothing was read or written.
    UnknownEdition { stream: Cover },
    /// An edition create or delete with no name: main is unnamed
    /// (INVALID_ARGUMENT).
    EditionNameRequired,
    /// The edition was already created (ALREADY_EXISTS).
    EditionExists { name: String },
    /// The edition was never created, or is deleted (NOT_FOUND).
    EditionNotFound { name: String },
    /// The edition names a store that is not configured
    /// (FAILED_PRECONDITION).
    EditionStoreUnknown { name: String, store: String },
    /// The divergence point is after the create (INVALID_ARGUMENT).
    EditionDivergesInTheFuture { name: String },
}

/// What a caller does about a [`StoreError`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Recovery {
    /// Run again from the dedup lookup, in a fresh unit: a conflict, the
    /// store unavailable, a busy handle.
    Retry,
    /// The request was malformed or names what does not exist. Fix it.
    Invalid,
    /// A bug or damage: a discontinuous append, an unreadable event. An
    /// operator must act.
    Bug,
}

/// An adapter's own failure, captured as data so [`StoreError`] stays
/// `Clone` and `Eq`: the adapter's stable code (its own crate's prefix,
/// `annals-store-sql-io`) and its English.
#[derive(Clone, PartialEq, Eq, Debug)]
pub struct Cause {
    pub code: &'static str,
    pub message: String,
}

impl Cause {
    pub fn new(code: &'static str, message: impl Into<String>) -> Cause {
        Cause {
            code,
            message: message.into(),
        }
    }
}

/// One named argument of an error's message: data, never English.
#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Arg {
    /// A sequence, a length, a count.
    Uint(u64),
    /// A name, a stream's text form, an id.
    Str(String),
    /// A wrapped cause, rendered in its own right.
    Cause(Cause),
}

/// A stream's text form for args and English: `domain/root`, or
/// `domain/root@edition` (annals' form).
fn stream_text(stream: &Cover) -> String {
    let root = stream
        .root
        .as_ref()
        .map(ToString::to_string)
        .unwrap_or_default();
    match &stream.edition {
        Some(edition) => format!("{}/{root}@{edition}", stream.domain),
        None => format!("{}/{root}", stream.domain),
    }
}

fn stream_arg(stream: &Cover) -> Arg {
    Arg::Str(stream_text(stream))
}

impl StoreError {
    /// The message id: kebab-case, starting `angzarr-ports-`, stable, never
    /// reused.
    pub fn code(&self) -> &'static str {
        match self {
            StoreError::Conflict { .. } => "angzarr-ports-store-conflict",
            StoreError::Discontinuous { .. } => "angzarr-ports-store-discontinuous",
            StoreError::MalformedStream { .. } => "angzarr-ports-store-malformed-stream",
            StoreError::Unavailable(_) => "angzarr-ports-store-unavailable",
            StoreError::Unreadable { .. } => "angzarr-ports-store-unreadable",
            StoreError::UnitBusy => "angzarr-ports-store-unit-busy",
            StoreError::UnknownEdition { .. } => "angzarr-ports-store-unknown-edition",
            StoreError::EditionNameRequired => "angzarr-ports-edition-name-required",
            StoreError::EditionExists { .. } => "angzarr-ports-edition-exists",
            StoreError::EditionNotFound { .. } => "angzarr-ports-edition-not-found",
            StoreError::EditionStoreUnknown { .. } => "angzarr-ports-edition-store-unknown",
            StoreError::EditionDivergesInTheFuture { .. } => {
                "angzarr-ports-edition-diverges-in-the-future"
            }
        }
    }

    /// The message's arguments, by name: the same names every time for a
    /// given code.
    pub fn args(&self) -> Vec<(&'static str, Arg)> {
        match self {
            StoreError::Conflict {
                stream,
                expected,
                actual,
            } => vec![
                ("stream", stream_arg(stream)),
                ("expected", Arg::Uint(*expected)),
                ("actual", Arg::Uint(*actual)),
            ],
            StoreError::Discontinuous {
                stream,
                expected,
                found,
            } => vec![
                ("stream", stream_arg(stream)),
                ("expected", Arg::Uint(*expected)),
                ("found", Arg::Uint(*found)),
            ],
            StoreError::MalformedStream { stream } | StoreError::UnknownEdition { stream } => {
                vec![("stream", stream_arg(stream))]
            }
            StoreError::Unavailable(cause) => vec![("cause", Arg::Cause(cause.clone()))],
            StoreError::Unreadable {
                stream,
                sequence,
                reason,
            } => vec![
                ("stream", stream_arg(stream)),
                ("sequence", Arg::Uint(*sequence)),
                ("cause", Arg::Cause(reason.clone())),
            ],
            StoreError::UnitBusy | StoreError::EditionNameRequired => Vec::new(),
            StoreError::EditionExists { name }
            | StoreError::EditionNotFound { name }
            | StoreError::EditionDivergesInTheFuture { name } => {
                vec![("name", Arg::Str(name.clone()))]
            }
            StoreError::EditionStoreUnknown { name, store } => vec![
                ("name", Arg::Str(name.clone())),
                ("store", Arg::Str(store.clone())),
            ],
        }
    }

    /// What the caller does about it.
    pub fn recovery(&self) -> Recovery {
        match self {
            StoreError::Conflict { .. } | StoreError::Unavailable(_) | StoreError::UnitBusy => {
                Recovery::Retry
            }
            StoreError::Discontinuous { .. } | StoreError::Unreadable { .. } => Recovery::Bug,
            StoreError::MalformedStream { .. }
            | StoreError::UnknownEdition { .. }
            | StoreError::EditionNameRequired
            | StoreError::EditionExists { .. }
            | StoreError::EditionNotFound { .. }
            | StoreError::EditionStoreUnknown { .. }
            | StoreError::EditionDivergesInTheFuture { .. } => Recovery::Invalid,
        }
    }
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::Conflict {
                stream,
                expected,
                actual,
            } => write!(
                f,
                "stream {} holds {actual} events, not the {expected} expected: someone else appended first",
                stream_text(stream)
            ),
            StoreError::Discontinuous {
                stream,
                expected,
                found,
            } => write!(
                f,
                "an append to stream {} gives sequence {found} where {expected} was due",
                stream_text(stream)
            ),
            StoreError::MalformedStream { stream } => write!(
                f,
                "cover {stream:?} is no stream: it needs a 16-byte root and, if it names an edition, a non-empty one"
            ),
            StoreError::Unavailable(cause) => {
                write!(f, "the store is unavailable: {}", cause.message)
            }
            StoreError::Unreadable {
                stream,
                sequence,
                reason,
            } => write!(
                f,
                "event {sequence} of stream {} cannot be read: {}",
                stream_text(stream),
                reason.message
            ),
            StoreError::UnitBusy => f.write_str(
                "a unit of work is already open on this handle, which serves one at a time",
            ),
            StoreError::UnknownEdition { stream } => write!(
                f,
                "stream {} names an edition that was never created",
                stream_text(stream)
            ),
            StoreError::EditionNameRequired => {
                f.write_str("an edition needs a name: main is unnamed, and always exists")
            }
            StoreError::EditionExists { name } => write!(f, "edition {name} already exists"),
            StoreError::EditionNotFound { name } => write!(f, "edition {name} was never created"),
            StoreError::EditionStoreUnknown { name, store } => write!(
                f,
                "edition {name} names the edition store {store}, which is not configured"
            ),
            StoreError::EditionDivergesInTheFuture { name } => {
                write!(f, "edition {name} would diverge after it is created")
            }
        }
    }
}

impl std::error::Error for StoreError {}
