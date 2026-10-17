//! prost types for angzarr's domain-neutral wire contract.
//!
//! Generated from `proto/` in this repository: `io.angzarr.v1` books, pages
//! (the `CommandPage` body: `Command` or `Fact`), covers, `Handling` (on
//! `CommandBook`, with `ConflictResolution`), `ContextualCommand` (with the
//! conflict nonce), provenance (`Provenance`, `EventMeta`, `EventRef`, and
//! the one `Origin` message over `RequestOrigin`, `Causation` and
//! `FactOrigin`, shared by the page, the event meta and the claim key),
//! snapshots (with their `rules_version`), the response-only `Outcome`, the
//! storage-only `IdempotencyClaim` schema, `ComponentDescriptor` and
//! `ComponentKind`, and the upcaster request/response messages, plus
//! `sererr.v1`, which `types.proto` imports. Every message implements [`prost::Name`] with no type-name domain,
//! so `prost_types::Any::from_msg` yields type URLs of the form
//! `/io.angzarr.v1.EventPage`, matching angzarr's TYPE_URL_PREFIX ("/").
//!
//! No gRPC services, tonic, or `google.api` annotations: this crate is a
//! dependency leaf and builds for `wasm32-unknown-unknown`.
//!
//! Module nesting mirrors proto package segments exactly so prost's
//! cross-package `super::` references resolve.

pub mod sererr {
    pub mod v1 {
        include!(concat!(env!("OUT_DIR"), "/sererr.v1.rs"));
    }
}

pub mod io {
    pub mod angzarr {
        // The spec's proto comments are prose, not rustdoc lists.
        #[allow(clippy::doc_overindented_list_items, clippy::doc_lazy_continuation)]
        pub mod v1 {
            include!(concat!(env!("OUT_DIR"), "/io.angzarr.v1.rs"));
        }
    }
}

pub use io::angzarr::v1;
