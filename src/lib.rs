//! The angzarr spec as a cargo package.
//!
//! The package's manifest is at the repository root, so the spec stays where
//! it is: `proto/` (the messages and services) and `features/` (the Gherkin
//! contracts). A dependent names the directories through this crate, and so
//! pins the spec by its cargo git revision (`Cargo.lock`) and overrides it
//! with `[patch]` like any other dependency.
//!
//! There is no build script and no dependency: the paths are resolved at
//! compile time from `CARGO_MANIFEST_DIR`, which is the checkout cargo made.

use std::path::Path;

/// The directory holding the spec's `.proto` files (an include root).
pub const PROTO_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/proto");

/// The directory holding the spec's Gherkin features.
pub const FEATURES_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/features");

/// [`PROTO_DIR`] as a path.
#[must_use]
pub fn proto_dir() -> &'static Path {
    Path::new(PROTO_DIR)
}

/// [`FEATURES_DIR`] as a path.
#[must_use]
pub fn features_dir() -> &'static Path {
    Path::new(FEATURES_DIR)
}
