//! prost types for angzarr's domain-neutral wire contract.
//!
//! Generated from `proto/` in this repository: `io.angzarr.v1` books, pages
//! (the `CommandPage` body: `Command` or `Fact`), covers, `Expectation`,
//! provenance (`Provenance`, `EventMeta`, `EventRef`, the origin messages
//! `RequestOrigin`, `Causation`, `FactOrigin`), the response-only
//! `ResponseMeta`, and the upcaster request/response messages, plus
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
