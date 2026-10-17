//! Boundary helpers for the wire `UUID` type (`types.proto`, the `uuid` and
//! `derived_ids` regions).
//!
//! Operations use [`v1::Uuid`] values: compare, store and pass the 16 bytes.
//! Text appears only at display and input boundaries, through
//! [`Display`](fmt::Display) (canonical lowercase hyphenated text, RFC 9562)
//! and [`FromStr`] (the hyphenated form, either case). Conversions to and
//! from `[u8; 16]` and [`uuid::Uuid`] are lossless.
//!
//! Framework-derived ids are UUIDv5 under two fixed namespaces:
//! [`compute_root`] (`"{domain}:{key}"` under [`ROOT_NAMESPACE`]) and
//! [`fact_correlation`] (`external_id` under [`FACT_CORRELATION_NAMESPACE`]).

use std::fmt;
use std::str::FromStr;

use crate::v1;

/// Namespace for derived roots: `d4741b1a-52cd-43cf-add1-3dbb9615510b`.
/// Generated once as a random UUIDv4; never changes.
pub const ROOT_NAMESPACE: uuid::Uuid = uuid::uuid!("d4741b1a-52cd-43cf-add1-3dbb9615510b");

/// Namespace for a fact's default correlation:
/// `e9ef0ae2-6fc6-4c14-b713-ef03971dd867`. Generated once as a random
/// UUIDv4; never changes. Separate from [`ROOT_NAMESPACE`] so a correlation
/// never equals a root by accident (`"{domain}:{key}"` is also a valid
/// external id).
pub const FACT_CORRELATION_NAMESPACE: uuid::Uuid =
    uuid::uuid!("e9ef0ae2-6fc6-4c14-b713-ef03971dd867");

/// Why a value is not a well-formed UUID.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UuidError {
    /// The wire value is not exactly 16 bytes (the coordinator answers this
    /// INVALID_ARGUMENT); carries the actual length.
    Length(usize),
    /// The text is not a hyphenated 8-4-4-4-12 hex UUID.
    Text,
    /// A domain passed to [`compute_root`] contains `':'`, the separator.
    DomainContainsColon,
}

impl fmt::Display for UuidError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            UuidError::Length(n) => write!(f, "a UUID is 16 bytes, got {n}"),
            UuidError::Text => f.write_str("not a hyphenated 8-4-4-4-12 hex UUID"),
            UuidError::DomainContainsColon => f.write_str("a domain never contains ':'"),
        }
    }
}

impl std::error::Error for UuidError {}

impl v1::Uuid {
    /// The UUID holding these 16 bytes.
    pub fn from_bytes(bytes: [u8; 16]) -> Self {
        Self {
            value: bytes.to_vec(),
        }
    }

    /// The 16 bytes, or [`UuidError::Length`] when the wire value is
    /// malformed.
    pub fn to_bytes(&self) -> Result<[u8; 16], UuidError> {
        <[u8; 16]>::try_from(self.value.as_slice()).map_err(|_| UuidError::Length(self.value.len()))
    }

    /// True iff the value is exactly 16 bytes, the only check the framework
    /// makes on a client-supplied UUID.
    pub fn is_well_formed(&self) -> bool {
        self.value.len() == 16
    }
}

impl From<[u8; 16]> for v1::Uuid {
    fn from(bytes: [u8; 16]) -> Self {
        Self::from_bytes(bytes)
    }
}

impl TryFrom<&v1::Uuid> for [u8; 16] {
    type Error = UuidError;
    fn try_from(id: &v1::Uuid) -> Result<Self, UuidError> {
        id.to_bytes()
    }
}

impl From<uuid::Uuid> for v1::Uuid {
    fn from(id: uuid::Uuid) -> Self {
        Self::from_bytes(id.into_bytes())
    }
}

impl TryFrom<&v1::Uuid> for uuid::Uuid {
    type Error = UuidError;
    fn try_from(id: &v1::Uuid) -> Result<Self, UuidError> {
        id.to_bytes().map(uuid::Uuid::from_bytes)
    }
}

/// Canonical text: 36 lowercase characters, hyphenated 8-4-4-4-12. A
/// malformed wire value (not 16 bytes) cannot be canonical text, so it is
/// shown as `invalid-uuid:` followed by its bytes in lowercase hex, which
/// [`FromStr`] never accepts.
impl fmt::Display for v1::Uuid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.to_bytes() {
            Ok(bytes) => fmt::Display::fmt(&uuid::Uuid::from_bytes(bytes).hyphenated(), f),
            Err(_) => {
                f.write_str("invalid-uuid:")?;
                self.value.iter().try_for_each(|b| write!(f, "{b:02x}"))
            }
        }
    }
}

/// Parses the hyphenated 8-4-4-4-12 form, in either case. Other forms
/// (simple, braced, URN) are refused, so every language accepts the same
/// input.
impl FromStr for v1::Uuid {
    type Err = UuidError;
    fn from_str(s: &str) -> Result<Self, UuidError> {
        if s.len() != 36 {
            return Err(UuidError::Text);
        }
        uuid::Uuid::try_parse(s)
            .map(Self::from)
            .map_err(|_| UuidError::Text)
    }
}

/// A derived root: UUIDv5([`ROOT_NAMESPACE`], `"{domain}:{key}"`), the name
/// being the UTF-8 bytes with no normalisation. Refuses a domain containing
/// `':'`, which would make the name ambiguous.
pub fn compute_root(domain: &str, key: &str) -> Result<v1::Uuid, UuidError> {
    if domain.contains(':') {
        return Err(UuidError::DomainContainsColon);
    }
    let name = format!("{domain}:{key}");
    Ok(uuid::Uuid::new_v5(&ROOT_NAMESPACE, name.as_bytes()).into())
}

/// A fact's correlation when its command supplies none:
/// UUIDv5([`FACT_CORRELATION_NAMESPACE`], `external_id`).
pub fn fact_correlation(external_id: &str) -> v1::Uuid {
    uuid::Uuid::new_v5(&FACT_CORRELATION_NAMESPACE, external_id.as_bytes()).into()
}
