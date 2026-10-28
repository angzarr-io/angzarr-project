//! meta.proto's EditionAdminService messages: the edition registry's
//! request and record types, generated (messages only; no service).

use angzarr_proto::protos::FILES;
use angzarr_proto::v1::{CreateEditionRequest, DeleteEditionRequest, Edition};
use prost::{Message, Name};

fn at(seconds: i64) -> Option<prost_types::Timestamp> {
    Some(prost_types::Timestamp { seconds, nanos: 7 })
}

/// The first byte of an encoding: the first field's tag, as
/// `(number << 3) | wire type` (2, length-delimited, for every field here).
fn first_tag<M: Message>(m: &M) -> u8 {
    m.encode_to_vec()[0]
}

#[test]
fn create_edition_request_round_trips_with_its_field_numbers() {
    let request = CreateEditionRequest {
        name: "what-if".into(),
        diverge_at: at(1_700_000_000),
        store: "archive".into(),
    };
    assert_eq!(
        CreateEditionRequest::decode(&*request.encode_to_vec()).unwrap(),
        request
    );
    let name = CreateEditionRequest {
        name: "e".into(),
        ..Default::default()
    };
    let diverge_at = CreateEditionRequest {
        diverge_at: at(1),
        ..Default::default()
    };
    let store = CreateEditionRequest {
        store: "s".into(),
        ..Default::default()
    };
    assert_eq!(first_tag(&name), (1 << 3) | 2);
    assert_eq!(first_tag(&diverge_at), (2 << 3) | 2);
    assert_eq!(first_tag(&store), (3 << 3) | 2);
}

#[test]
fn an_unset_divergence_point_is_distinct_from_the_epoch() {
    let unset = CreateEditionRequest {
        name: "e".into(),
        ..Default::default()
    };
    let epoch = CreateEditionRequest {
        diverge_at: Some(prost_types::Timestamp::default()),
        ..unset.clone()
    };
    let decode = |m: &CreateEditionRequest| {
        CreateEditionRequest::decode(&*m.encode_to_vec())
            .unwrap()
            .diverge_at
    };
    assert_eq!(decode(&unset), None);
    assert_eq!(decode(&epoch), Some(prost_types::Timestamp::default()));
}

#[test]
fn edition_record_round_trips_with_its_field_numbers() {
    let edition = Edition {
        name: "what-if".into(),
        diverged_at: at(10),
        store: "default".into(),
        created_at: at(20),
    };
    assert_eq!(Edition::decode(&*edition.encode_to_vec()).unwrap(), edition);
    let field = |e: Edition| first_tag(&e);
    assert_eq!(
        field(Edition {
            name: "e".into(),
            ..Default::default()
        }),
        (1 << 3) | 2
    );
    assert_eq!(
        field(Edition {
            diverged_at: at(1),
            ..Default::default()
        }),
        (2 << 3) | 2
    );
    assert_eq!(
        field(Edition {
            store: "s".into(),
            ..Default::default()
        }),
        (3 << 3) | 2
    );
    assert_eq!(
        field(Edition {
            created_at: at(1),
            ..Default::default()
        }),
        (4 << 3) | 2
    );
}

#[test]
fn delete_edition_request_carries_the_name_as_field_one() {
    let request = DeleteEditionRequest {
        name: "what-if".into(),
    };
    assert_eq!(first_tag(&request), (1 << 3) | 2);
    assert_eq!(
        DeleteEditionRequest::decode(&*request.encode_to_vec()).unwrap(),
        request
    );
}

#[test]
fn edition_messages_have_angzarr_type_urls() {
    assert_eq!(Edition::type_url(), "/io.angzarr.v1.Edition");
    assert_eq!(
        CreateEditionRequest::type_url(),
        "/io.angzarr.v1.CreateEditionRequest"
    );
    assert_eq!(
        DeleteEditionRequest::type_url(),
        "/io.angzarr.v1.DeleteEditionRequest"
    );
}

#[test]
fn meta_proto_and_its_google_api_imports_are_embedded() {
    let paths: Vec<_> = FILES.iter().map(|f| f.path).collect();
    for path in [
        "io/angzarr/v1/meta.proto",
        "google/api/annotations.proto",
        "google/api/http.proto",
    ] {
        assert!(paths.contains(&path), "{path} not embedded");
    }
}
