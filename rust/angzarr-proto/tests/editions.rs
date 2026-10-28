//! Editions as per-stream forks (decision 14.32): the fork event in
//! types.proto, and meta.proto's EditionAdminService messages (generated;
//! messages only, no service).

use angzarr_proto::protos::FILES;
use angzarr_proto::v1::{
    Cover, DeleteEditionRequest, EditionForked, EditionSummary, EventRef, ForkStreamRequest,
    ListEditionsResponse, Uuid,
};
use prost::{Message, Name};

/// The first byte of an encoding: the first field's tag, as
/// `(number << 3) | wire type`.
fn first_tag<M: Message>(m: &M) -> u8 {
    m.encode_to_vec()[0]
}

fn stream(edition: &str) -> Cover {
    Cover {
        domain: "player".into(),
        root: Some(Uuid {
            value: vec![7; 16].into(),
        }),
        edition: Some(edition.into()),
    }
}

#[test]
fn the_fork_event_round_trips_with_its_field_numbers() {
    let fork = EditionForked {
        edition: "what-if".into(),
        parent_sequence: 12,
        commit_position: 0,
        propagated_from: Some(EventRef {
            stream: Some(stream("what-if")),
            sequence: 3,
        }),
        on_demand: false,
    };
    assert_eq!(EditionForked::decode(&*fork.encode_to_vec()).unwrap(), fork);
    let tag = |f: EditionForked| first_tag(&f);
    assert_eq!(
        tag(EditionForked {
            edition: "e".into(),
            ..Default::default()
        }),
        (1 << 3) | 2
    );
    assert_eq!(
        tag(EditionForked {
            parent_sequence: 1,
            ..Default::default()
        }),
        2 << 3
    );
    assert_eq!(
        tag(EditionForked {
            commit_position: 1,
            ..Default::default()
        }),
        3 << 3
    );
    assert_eq!(
        tag(EditionForked {
            propagated_from: Some(EventRef::default()),
            ..Default::default()
        }),
        (4 << 3) | 2
    );
    assert_eq!(
        tag(EditionForked {
            on_demand: true,
            ..Default::default()
        }),
        5 << 3
    );
}

#[test]
fn fork_stream_request_names_the_stream_and_the_optional_commit_position() {
    let per_stream = ForkStreamRequest {
        stream: Some(stream("what-if")),
        commit_position: 0,
    };
    assert_eq!(
        ForkStreamRequest::decode(&*per_stream.encode_to_vec()).unwrap(),
        per_stream
    );
    assert_eq!(first_tag(&per_stream), (1 << 3) | 2);
    let time_based = ForkStreamRequest {
        commit_position: 42,
        ..Default::default()
    };
    assert_eq!(first_tag(&time_based), 2 << 3);
}

#[test]
fn editions_are_listed_as_summaries_derived_from_fork_events() {
    let response = ListEditionsResponse {
        editions: vec![EditionSummary {
            name: "what-if".into(),
            origins: vec![EventRef {
                stream: Some(stream("what-if")),
                sequence: 12,
            }],
            forked_streams: 4,
            commit_position: 0,
        }],
    };
    assert_eq!(
        ListEditionsResponse::decode(&*response.encode_to_vec()).unwrap(),
        response
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
    assert_eq!(EditionForked::type_url(), "/io.angzarr.v1.EditionForked");
    assert_eq!(
        ForkStreamRequest::type_url(),
        "/io.angzarr.v1.ForkStreamRequest"
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
