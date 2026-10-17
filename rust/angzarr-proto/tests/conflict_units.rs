//! The COMMUTATIVE conflict-unit markers (options.proto, conflict_units
//! region) are readable from descriptors.
//!
//! prost does not generate `extend` declarations, so option VALUES cannot be
//! read through prost's typed options (`prost_types::MessageOptions` drops
//! unknown fields). These tests compile a fixture with protoc, check the
//! extension declarations through `prost_types`, and read the option values
//! off the raw descriptor bytes, decoding the `(conflict)` payload with the
//! generated `ConflictUnit`. A code generator (backlog CR-1) reads them the
//! same way.

use std::path::{Path, PathBuf};
use std::process::Command;

use angzarr_proto::v1::ConflictUnit;
use prost::{Message, Name};
use prost_types::field_descriptor_proto::Type;
use prost_types::FileDescriptorSet;

const COMMUTATIVE_STATE: u32 = 50106;
const CONFLICT: u32 = 50107;

fn proto_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../proto")
}

/// Compiles the fixture (and, with --include_imports, options.proto itself)
/// into a serialized FileDescriptorSet.
fn descriptor_set() -> Vec<u8> {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let out = Path::new(env!("CARGO_TARGET_TMPDIR")).join("list_state.binpb");
    let protoc = std::env::var("PROTOC").unwrap_or_else(|_| "protoc".into());
    let status = Command::new(protoc)
        .arg(format!("-I{}", proto_root().display()))
        .arg(format!("-I{}", manifest.join("tests/fixtures").display()))
        .arg("--include_imports")
        .arg(format!("--descriptor_set_out={}", out.display()))
        .arg("list_state.proto")
        .status()
        .expect("run protoc");
    assert!(status.success(), "protoc failed on the fixture");
    std::fs::read(out).expect("read descriptor set")
}

/// One wire-format field: varints and length-delimited values only (fixed
/// widths are skipped; descriptors use neither for what we read).
enum Val<'a> {
    Varint(u64),
    Bytes(&'a [u8]),
}

fn varint(buf: &mut &[u8]) -> u64 {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let b = buf[0];
        *buf = &buf[1..];
        v |= u64::from(b & 0x7f) << shift;
        if b & 0x80 == 0 {
            return v;
        }
    }
    panic!("varint too long")
}

fn fields(mut buf: &[u8]) -> Vec<(u32, Val<'_>)> {
    let mut out = Vec::new();
    while !buf.is_empty() {
        let key = varint(&mut buf);
        let (num, wire) = ((key >> 3) as u32, key & 7);
        match wire {
            0 => out.push((num, Val::Varint(varint(&mut buf)))),
            2 => {
                let len = varint(&mut buf) as usize;
                out.push((num, Val::Bytes(&buf[..len])));
                buf = &buf[len..];
            }
            1 => buf = &buf[8..],
            5 => buf = &buf[4..],
            w => panic!("unexpected wire type {w}"),
        }
    }
    out
}

fn bytes_of(buf: &[u8], num: u32) -> Vec<&[u8]> {
    fields(buf)
        .into_iter()
        .filter_map(|(n, v)| match v {
            Val::Bytes(b) if n == num => Some(b),
            _ => None,
        })
        .collect()
}

fn name_of(buf: &[u8]) -> String {
    String::from_utf8(bytes_of(buf, 1)[0].to_vec()).unwrap()
}

/// The raw DescriptorProto of `message` in the fixture file.
fn message<'a>(set: &'a [u8], message: &str) -> &'a [u8] {
    let file = bytes_of(set, 1) // FileDescriptorSet.file
        .into_iter()
        .find(|f| name_of(f) == "list_state.proto")
        .expect("fixture file");
    bytes_of(file, 4) // FileDescriptorProto.message_type
        .into_iter()
        .find(|m| name_of(m) == message)
        .unwrap_or_else(|| panic!("message {message}"))
}

/// (commutative_state) on a message: DescriptorProto.options (7), field 50106.
fn commutative_state(set: &[u8], msg: &str) -> Option<bool> {
    let opts = bytes_of(message(set, msg), 7).into_iter().next()?;
    fields(opts).into_iter().find_map(|(n, v)| match v {
        Val::Varint(b) if n == COMMUTATIVE_STATE => Some(b != 0),
        _ => None,
    })
}

/// (conflict) on a field: FieldDescriptorProto.options (8), field 50107.
fn conflict(set: &[u8], msg: &str, field: &str) -> Option<ConflictUnit> {
    let f = bytes_of(message(set, msg), 2) // DescriptorProto.field
        .into_iter()
        .find(|f| name_of(f) == field)
        .unwrap_or_else(|| panic!("field {msg}.{field}"));
    let opts = bytes_of(f, 8).into_iter().next()?;
    bytes_of(opts, CONFLICT)
        .into_iter()
        .next()
        .map(|b| ConflictUnit::decode(b).expect("decode ConflictUnit"))
}

#[test]
fn extensions_are_declared_with_their_numbers_and_types() {
    let set = FileDescriptorSet::decode(descriptor_set().as_slice()).unwrap();
    let options = set
        .file
        .iter()
        .find(|f| f.name() == "io/angzarr/v1/options.proto")
        .expect("options.proto in the set");
    let ext = |name: &str| {
        options
            .extension
            .iter()
            .find(|e| e.name() == name)
            .unwrap_or_else(|| panic!("extension {name}"))
    };

    let state = ext("commutative_state");
    assert_eq!(state.number(), COMMUTATIVE_STATE as i32);
    assert_eq!(state.extendee(), ".google.protobuf.MessageOptions");
    assert_eq!(state.r#type(), Type::Bool);

    let unit = ext("conflict");
    assert_eq!(unit.number(), CONFLICT as i32);
    assert_eq!(unit.extendee(), ".google.protobuf.FieldOptions");
    assert_eq!(unit.r#type(), Type::Message);
    assert_eq!(unit.type_name(), ".io.angzarr.v1.ConflictUnit");

    // No two MessageOptions extensions share a number, and the retired
    // 50101-50103 stay unused.
    let mut numbers: Vec<i32> = options
        .extension
        .iter()
        .filter(|e| e.extendee() == ".google.protobuf.MessageOptions")
        .map(|e| e.number())
        .collect();
    numbers.sort_unstable();
    assert_eq!(numbers, [50100, 50104, 50105, 50106]);
}

#[test]
fn worked_example_list_state_marks_every_field_at_its_natural_unit() {
    let set = descriptor_set();
    assert_eq!(commutative_state(&set, "ListState"), Some(true));
    // `= {}` is a present, empty ConflictUnit: marked, not unmarked.
    for field in ["items", "columns", "settings"] {
        assert_eq!(
            conflict(&set, "ListState", field),
            Some(ConflictUnit::default()),
            "ListState.{field}"
        );
    }
}

#[test]
fn finer_markers_carry_descend_element_key_and_ordered() {
    let set = descriptor_set();
    assert_eq!(commutative_state(&set, "FinerListState"), Some(true));
    assert_eq!(
        conflict(&set, "FinerListState", "items"),
        Some(ConflictUnit {
            descend: true,
            ..Default::default()
        })
    );
    assert_eq!(
        conflict(&set, "FinerListState", "columns"),
        Some(ConflictUnit {
            element_key: "id".into(),
            ordered: true,
            ..Default::default()
        })
    );
    // Unmarked: conflicts with everything.
    assert_eq!(conflict(&set, "FinerListState", "settings"), None);
}

#[test]
fn unmarked_messages_carry_no_options() {
    let set = descriptor_set();
    assert_eq!(commutative_state(&set, "Item"), None);
    assert_eq!(conflict(&set, "Item", "weight"), None);
}

#[test]
fn conflict_unit_round_trips() {
    let unit = ConflictUnit {
        descend: true,
        element_key: "id".into(),
        ordered: true,
    };
    let back = ConflictUnit::decode(unit.encode_to_vec().as_slice()).unwrap();
    assert_eq!(back, unit);
    assert!(ConflictUnit::default().encode_to_vec().is_empty());
    assert_eq!(ConflictUnit::full_name(), "io.angzarr.v1.ConflictUnit");
}
