use angzarr_proto::v1::{
    command_meta, command_page, event_meta, event_page, CommandBook, CommandMeta, CommandPage,
    Cover, Edition, EventMeta, EventPage, EventRef, ExternalOrigin, MergeStrategy, ReactionOrigin,
    RequestOrigin, UpcastRequest, Uuid,
};
use prost::{Message, Name};

fn uuid(byte: u8) -> Uuid {
    Uuid {
        value: vec![byte; 16],
    }
}

fn cause() -> EventRef {
    EventRef {
        domain: "lists".into(),
        edition: String::new(), // main timeline
        root: Some(uuid(0xab)),
        sequence: u64::MAX,
    }
}

fn page() -> EventPage {
    EventPage {
        // Above u32::MAX: the widened sequence survives the wire.
        sequence: u64::from(u32::MAX) + 7,
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
            correlation_id: "corr-1".into(),
            rules_version: "rules-3".into(),
            decided_at: u64::from(u32::MAX) + 7,
            origin: Some(event_meta::Origin::Reaction(ReactionOrigin {
                cause: Some(cause()),
                component: "list-to-draw".into(),
                index: 2,
            })),
        }),
    }
}

fn command(origin: command_meta::Origin) -> CommandBook {
    CommandBook {
        cover: Some(Cover {
            domain: "draws".into(),
            root: Some(uuid(0xcd)),
            edition: Some(Edition {
                name: "what-if".into(),
                divergences: vec![],
            }),
        }),
        page: Some(CommandPage {
            merge_strategy: MergeStrategy::MergeAggregateHandles as i32,
            payload: Some(command_page::Payload::Command(prost_types::Any {
                type_url: "/draws.v1.Draw".into(),
                value: vec![9],
            })),
            meta: Some(CommandMeta {
                actor: "actor:9f2c".into(),
                correlation_id: "corr-1".into(),
                origin: Some(origin),
            }),
            sequence: Some(u64::from(u32::MAX) + 1),
        }),
    }
}

fn origins() -> [command_meta::Origin; 3] {
    [
        command_meta::Origin::Request(RequestOrigin {
            request_id: "req-1".into(),
            index: 3,
        }),
        command_meta::Origin::Reaction(ReactionOrigin {
            cause: Some(cause()),
            component: "list-to-draw".into(),
            index: 1,
        }),
        command_meta::Origin::External(ExternalOrigin {
            external_id: "pi_1234".into(),
            description: "Stripe webhook".into(),
        }),
    ]
}

#[test]
fn command_book_with_one_page_round_trips_for_every_origin() {
    for origin in origins() {
        let original = command(origin.clone());
        let decoded = CommandBook::decode(original.encode_to_vec().as_slice()).expect("decode");
        assert_eq!(decoded, original);
        let page = decoded.page.expect("single page");
        assert_eq!(page.sequence, Some(u64::from(u32::MAX) + 1));
        assert_eq!(page.meta.unwrap().origin, Some(origin));
    }
}

#[test]
fn absent_command_sequence_is_distinct_from_zero() {
    let mut book = command(origins()[0].clone());
    book.page.as_mut().unwrap().sequence = None;
    let absent = CommandBook::decode(book.encode_to_vec().as_slice()).expect("decode");
    assert_eq!(absent.page.unwrap().sequence, None);

    book.page.as_mut().unwrap().sequence = Some(0);
    let zero = CommandBook::decode(book.encode_to_vec().as_slice()).expect("decode");
    assert_eq!(zero.page.unwrap().sequence, Some(0));
}

#[test]
fn event_page_with_meta_round_trips() {
    let original = page();
    let decoded = EventPage::decode(original.encode_to_vec().as_slice()).expect("decode");
    assert_eq!(decoded, original);
    let meta = decoded.meta.unwrap();
    assert_eq!(meta.decided_at, u64::from(u32::MAX) + 7);
    assert_eq!(meta.correlation_id, "corr-1");
    match meta.origin {
        Some(event_meta::Origin::Reaction(r)) => assert_eq!(r.cause.unwrap().sequence, u64::MAX),
        other => panic!("expected reaction origin, got {other:?}"),
    }
}

#[test]
fn event_meta_is_field_8_and_appended_after_the_page_body() {
    let mut p = page();
    p.sequence = 0; // default: not encoded, so meta is the last field written
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
    assert_eq!(CommandBook::full_name(), "io.angzarr.v1.CommandBook");
    assert_eq!(RequestOrigin::full_name(), "io.angzarr.v1.RequestOrigin");
    assert_eq!(ReactionOrigin::full_name(), "io.angzarr.v1.ReactionOrigin");
    assert_eq!(ExternalOrigin::full_name(), "io.angzarr.v1.ExternalOrigin");
    assert_eq!(UpcastRequest::full_name(), "io.angzarr.v1.UpcastRequest");
    // angzarr's TYPE_URL_PREFIX is "/" (see types.proto), which is prost's
    // default when no type-name domain is configured.
    assert_eq!(EventPage::type_url(), "/io.angzarr.v1.EventPage");
    assert_eq!(CommandBook::type_url(), "/io.angzarr.v1.CommandBook");
    assert_eq!(
        angzarr_proto::sererr::v1::CapturedError::full_name(),
        "sererr.v1.CapturedError"
    );

    let any = prost_types::Any::from_msg(&page()).expect("pack");
    assert_eq!(any.type_url, "/io.angzarr.v1.EventPage");
    assert_eq!(any.to_msg::<EventPage>().expect("unpack"), page());

    let book = command(origins()[2].clone());
    let any = prost_types::Any::from_msg(&book).expect("pack");
    assert_eq!(any.type_url, "/io.angzarr.v1.CommandBook");
    assert_eq!(any.to_msg::<CommandBook>().expect("unpack"), book);
}
