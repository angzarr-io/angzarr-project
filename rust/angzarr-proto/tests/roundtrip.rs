use angzarr_proto::v1::{
    event_page, page_header, CommandMeta, CommandPage, EventMeta, EventPage, EventRef, PageHeader,
    UpcastRequest, Uuid,
};
use prost::{Message, Name};

fn page() -> EventPage {
    EventPage {
        header: Some(PageHeader {
            // Above u32::MAX: the widened sequence survives the wire.
            sequence_type: Some(page_header::SequenceType::Sequence(u64::from(u32::MAX) + 7)),
            sync_mode: None,
        }),
        created_at: Some(prost_types::Timestamp {
            seconds: 1_700_000_000,
            nanos: 5,
        }),
        payload: Some(event_page::Payload::Event(prost_types::Any {
            type_url: "/orders.v1.OrderPlaced".into(),
            value: vec![1, 2, 3],
        })),
        meta: Some(EventMeta {
            recorded_at: Some(prost_types::Timestamp {
                seconds: 1_700_000_001,
                nanos: 0,
            }),
            actor: "actor:9f2c".into(),
            request_id: "req-1".into(),
            command_index: 2,
            correlation_id: "corr-1".into(),
            cause: Some(EventRef {
                domain: "lists".into(),
                edition: "angzarr".into(),
                root: Some(Uuid {
                    value: vec![0xab; 16],
                }),
                sequence: u64::MAX,
            }),
            rules_version: "rules-3".into(),
        }),
    }
}

#[test]
fn event_page_with_meta_round_trips() {
    let original = page();
    let decoded = EventPage::decode(original.encode_to_vec().as_slice()).expect("decode");
    assert_eq!(decoded, original);
    assert_eq!(decoded.meta.unwrap().cause.unwrap().sequence, u64::MAX);
}

#[test]
fn event_meta_is_field_8_and_appended_after_the_page() {
    let mut p = page();
    let with = p.encode_to_vec();
    p.meta = None;
    let without = p.encode_to_vec();
    assert!(with.starts_with(&without));
    // Field 8, wire type 2 (length-delimited): tag byte 0x42.
    assert_eq!(with[without.len()], 0x42);
}

#[test]
fn command_meta_is_field_5() {
    let cmd = CommandPage {
        meta: Some(CommandMeta {
            actor: "a".into(),
            ..Default::default()
        }),
        ..Default::default()
    };
    // Field 5, wire type 2: tag byte 0x2a.
    assert_eq!(cmd.encode_to_vec()[0], 0x2a);
}

#[test]
fn type_names_are_io_angzarr_v1() {
    assert_eq!(EventPage::full_name(), "io.angzarr.v1.EventPage");
    assert_eq!(EventMeta::full_name(), "io.angzarr.v1.EventMeta");
    assert_eq!(EventRef::full_name(), "io.angzarr.v1.EventRef");
    assert_eq!(CommandMeta::full_name(), "io.angzarr.v1.CommandMeta");
    assert_eq!(UpcastRequest::full_name(), "io.angzarr.v1.UpcastRequest");
    // angzarr's TYPE_URL_PREFIX is "/" (see types.proto), which is prost's
    // default when no type-name domain is configured.
    assert_eq!(EventPage::type_url(), "/io.angzarr.v1.EventPage");
    assert_eq!(
        angzarr_proto::sererr::v1::CapturedError::full_name(),
        "sererr.v1.CapturedError"
    );

    let any = prost_types::Any::from_msg(&page()).expect("pack");
    assert_eq!(any.type_url, "/io.angzarr.v1.EventPage");
    assert_eq!(any.to_msg::<EventPage>().expect("unpack"), page());
}
