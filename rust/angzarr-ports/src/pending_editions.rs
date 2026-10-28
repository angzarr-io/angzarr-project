//! The withdrawn edition-registry shapes, kept here only so the pending
//! `Editions` port and its ignored tests keep compiling.
//!
//! The spec's decision 14.32 (owner ruling, 2026-10-28) replaced the
//! administrative registry with per-stream forks: `CreateEditionRequest`
//! and the `Edition` record are deleted from `meta.proto`, so angzarr-proto
//! no longer generates them. These plain structs carry the old fields
//! unchanged until the `Editions` trait and the `editions` and
//! `read_editions` sections are reworked to the fork model (OPEN(C) in
//! `tests/contract.rs`); then this module goes.

use prost_types::Timestamp;

/// The withdrawn `CreateEditionRequest` (meta.proto before decision 14.32).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct CreateEditionRequest {
    pub name: String,
    pub diverge_at: Option<Timestamp>,
    pub store: String,
}

/// The withdrawn `Edition` record (meta.proto before decision 14.32).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Edition {
    pub name: String,
    pub diverged_at: Option<Timestamp>,
    pub store: String,
    pub created_at: Option<Timestamp>,
}
