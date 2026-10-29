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
///
/// Every stream a variant names is boxed (owner ruling, 2026-10-28), so the
/// error stays small (pinned in `tests/error.rs`); build one with the
/// constructors ([`StoreError::conflict`], ...) and read its stream with
/// [`StoreError::stream`], and the box never shows.
#[derive(Clone, PartialEq, Eq, Debug)]
#[non_exhaustive]
pub enum StoreError {
    /// Someone else appended first: the stream is at `actual`, not
    /// `expected`. Nothing was appended. Core's `SequenceConflict`.
    Conflict {
        stream: Box<Cover>,
        expected: u64,
        actual: u64,
    },
    /// The pages do not continue the stream: sequence `found` where
    /// `expected` was due. A caller bug; nothing was appended.
    Discontinuous {
        stream: Box<Cover>,
        expected: u64,
        found: u64,
    },
    /// A wire `Cover` that is no stream: no root, a root not 16 bytes, or an
    /// edition set to the empty string (INVALID_ARGUMENT).
    MalformedStream { stream: Box<Cover> },
    /// An edition creation whose `EditionCreated.parent_sequence` is not
    /// its own page's sequence (14.36: the fork is where it says, so the
    /// two must agree; INVALID_ARGUMENT). Nothing was written.
    MalformedCreation {
        stream: Box<Cover>,
        sequence: u64,
        parent_sequence: u64,
    },
    /// The store failed: I/O, a timeout, a dropped connection, a schema this
    /// build cannot read. A write may or may not have landed.
    Unavailable(Cause),
    /// The store holds event `sequence` of `stream` but cannot give it back:
    /// bytes that do not decode as an `EventPage`, a row with metadata
    /// missing. Upcasting is never the store's: an unknown payload type is
    /// not this.
    Unreadable {
        stream: Box<Cover>,
        sequence: u64,
        reason: Cause,
    },
    /// A read unit was given a stream in an edition that does not exist (no
    /// fork event of it anywhere; 14.32: NOT_FOUND). Nothing was read.
    UnknownEdition { stream: Box<Cover> },
    /// A write to an edition stream with no fork in that edition, other
    /// than its fork: input from outside is refused until the fork reaches
    /// the stream (14.32: FAILED_PRECONDITION, `EDITION_NOT_FORKED`).
    /// Nothing was written.
    EditionNotForked { stream: Box<Cover> },
    /// A fork of a stream already forked in its edition (14.32:
    /// ALREADY_EXISTS), or of main, which is never forked into. Nothing
    /// was written.
    EditionAlreadyForked { stream: Box<Cover> },
    /// A removal of an edition stream whose last event is not its deletion
    /// (14.32: a stream is removed only after recording its deletion).
    /// Nothing was removed.
    EditionNotDeleted { stream: Box<Cover> },
    /// A removal of an edition stream whose deletion has not yet propagated
    /// onward: an outbox entry of the edition, written with the stream or a
    /// position on it, is still pending (14.32). Nothing was removed; remove
    /// it once the entry is delivered.
    EditionNotPropagated { stream: Box<Cover> },
    /// An edition operation with no edition: main is unnamed, and is
    /// neither forked into nor deleted (INVALID_ARGUMENT).
    EditionNameRequired,
    /// The edition does not exist: no fork event of it (NOT_FOUND).
    EditionNotFound { name: String },
}

impl From<crate::stream::StreamRef<'_>> for Cover {
    fn from(stream: crate::stream::StreamRef<'_>) -> Cover {
        stream.to_cover()
    }
}

impl StoreError {
    pub fn conflict(stream: impl Into<Cover>, expected: u64, actual: u64) -> StoreError {
        StoreError::Conflict {
            stream: Box::new(stream.into()),
            expected,
            actual,
        }
    }

    pub fn discontinuous(stream: impl Into<Cover>, expected: u64, found: u64) -> StoreError {
        StoreError::Discontinuous {
            stream: Box::new(stream.into()),
            expected,
            found,
        }
    }

    pub fn malformed_stream(stream: impl Into<Cover>) -> StoreError {
        StoreError::MalformedStream {
            stream: Box::new(stream.into()),
        }
    }

    pub fn malformed_creation(
        stream: impl Into<Cover>,
        sequence: u64,
        parent_sequence: u64,
    ) -> StoreError {
        StoreError::MalformedCreation {
            stream: Box::new(stream.into()),
            sequence,
            parent_sequence,
        }
    }

    pub fn unreadable(stream: impl Into<Cover>, sequence: u64, reason: Cause) -> StoreError {
        StoreError::Unreadable {
            stream: Box::new(stream.into()),
            sequence,
            reason,
        }
    }

    pub fn edition_not_deleted(stream: impl Into<Cover>) -> StoreError {
        StoreError::EditionNotDeleted {
            stream: Box::new(stream.into()),
        }
    }

    pub fn edition_not_propagated(stream: impl Into<Cover>) -> StoreError {
        StoreError::EditionNotPropagated {
            stream: Box::new(stream.into()),
        }
    }

    pub fn unknown_edition(stream: impl Into<Cover>) -> StoreError {
        StoreError::UnknownEdition {
            stream: Box::new(stream.into()),
        }
    }

    pub fn edition_not_forked(stream: impl Into<Cover>) -> StoreError {
        StoreError::EditionNotForked {
            stream: Box::new(stream.into()),
        }
    }

    pub fn edition_already_forked(stream: impl Into<Cover>) -> StoreError {
        StoreError::EditionAlreadyForked {
            stream: Box::new(stream.into()),
        }
    }

    /// The stream the error is about, if it names one.
    pub fn stream(&self) -> Option<&Cover> {
        match self {
            StoreError::Conflict { stream, .. }
            | StoreError::Discontinuous { stream, .. }
            | StoreError::MalformedStream { stream }
            | StoreError::MalformedCreation { stream, .. }
            | StoreError::Unreadable { stream, .. }
            | StoreError::UnknownEdition { stream }
            | StoreError::EditionNotForked { stream }
            | StoreError::EditionAlreadyForked { stream }
            | StoreError::EditionNotDeleted { stream }
            | StoreError::EditionNotPropagated { stream } => Some(stream),
            StoreError::Unavailable(_)
            | StoreError::EditionNameRequired
            | StoreError::EditionNotFound { .. } => None,
        }
    }
}

/// What a caller does about a [`StoreError`].
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Recovery {
    /// Run again from the dedup lookup, in a fresh unit: a conflict, the
    /// store unavailable.
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
            StoreError::MalformedCreation { .. } => "angzarr-ports-store-malformed-creation",
            StoreError::Unavailable(_) => "angzarr-ports-store-unavailable",
            StoreError::Unreadable { .. } => "angzarr-ports-store-unreadable",
            StoreError::UnknownEdition { .. } => "angzarr-ports-store-unknown-edition",
            StoreError::EditionNameRequired => "angzarr-ports-edition-name-required",
            StoreError::EditionNotFound { .. } => "angzarr-ports-edition-not-found",
            StoreError::EditionNotForked { .. } => "angzarr-ports-store-edition-not-forked",
            StoreError::EditionAlreadyForked { .. } => "angzarr-ports-store-edition-already-forked",
            StoreError::EditionNotDeleted { .. } => "angzarr-ports-store-edition-not-deleted",
            StoreError::EditionNotPropagated { .. } => "angzarr-ports-store-edition-not-propagated",
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
            StoreError::MalformedCreation {
                stream,
                sequence,
                parent_sequence,
            } => vec![
                ("stream", stream_arg(stream)),
                ("sequence", Arg::Uint(*sequence)),
                ("parent_sequence", Arg::Uint(*parent_sequence)),
            ],
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
            StoreError::EditionNameRequired => Vec::new(),
            StoreError::EditionNotFound { name } => vec![("name", Arg::Str(name.clone()))],
            StoreError::EditionNotForked { stream }
            | StoreError::EditionAlreadyForked { stream }
            | StoreError::EditionNotDeleted { stream }
            | StoreError::EditionNotPropagated { stream } => vec![("stream", stream_arg(stream))],
        }
    }

    /// What the caller does about it.
    pub fn recovery(&self) -> Recovery {
        match self {
            StoreError::Conflict { .. } | StoreError::Unavailable(_) => Recovery::Retry,
            StoreError::Discontinuous { .. } | StoreError::Unreadable { .. } => Recovery::Bug,
            StoreError::MalformedStream { .. }
            | StoreError::MalformedCreation { .. }
            | StoreError::UnknownEdition { .. }
            | StoreError::EditionNameRequired
            | StoreError::EditionNotFound { .. } => Recovery::Invalid,
            StoreError::EditionNotForked { .. } | StoreError::EditionAlreadyForked { .. } => {
                Recovery::Invalid
            }
            StoreError::EditionNotDeleted { .. } => Recovery::Bug,
            StoreError::EditionNotPropagated { .. } => Recovery::Retry,
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
            StoreError::MalformedCreation {
                stream,
                sequence,
                parent_sequence,
            } => write!(
                f,
                "the creation of stream {} at sequence {sequence} states parent_sequence {parent_sequence}: a fork is where it says, so they must agree",
                stream_text(stream)
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
            StoreError::UnknownEdition { stream } => write!(
                f,
                "stream {} names an edition that does not exist",
                stream_text(stream)
            ),
            StoreError::EditionNameRequired => f.write_str(
                "an edition operation needs an edition: main is unnamed, and is neither forked into nor deleted",
            ),
            StoreError::EditionNotFound { name } => {
                write!(f, "edition {name} does not exist: no stream is forked in it")
            }
            StoreError::EditionNotForked { stream } => write!(
                f,
                "stream {} is not yet created in its edition: only its creation may be written first",
                stream_text(stream)
            ),
            StoreError::EditionAlreadyForked { stream } => write!(
                f,
                "stream {} is already created in its edition",
                stream_text(stream)
            ),
            StoreError::EditionNotDeleted { stream } => write!(
                f,
                "stream {} has not recorded its edition's deletion, so it is not removed",
                stream_text(stream)
            ),
            StoreError::EditionNotPropagated { stream } => write!(
                f,
                "stream {}'s deletion has not yet propagated onward: an outbox entry of it is pending",
                stream_text(stream)
            ),
        }
    }
}

impl std::error::Error for StoreError {}
