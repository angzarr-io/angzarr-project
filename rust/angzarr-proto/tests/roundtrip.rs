use angzarr_proto::v1::{
    command, command_page, event_meta, Causation, Command, CommandBook, CommandPage, Cover,
    DeliveryOutcome, EventMeta, EventPage, EventRef, Expectation, Fact, FactOrigin, MergeStrategy,
    Provenance, RequestOrigin, ResponseMeta, UpcastRequest, Uuid,
};
use prost::{Message, Name};

fn uuid(byte: u8) -> Uuid {
    Uuid {
        value: vec![byte; 16],
    }
}

fn any(type_url: &str, value: &[u8]) -> prost_types::Any {
    prost_types::Any {
        type_url: type_url.into(),
        value: value.to_vec(),
    }
}

fn provenance() -> Provenance {
    Provenance {
        actor: "actor:9f2c".into(),
        correlation_id: "corr-1".into(),
    }
}

/// An event in a non-main edition, so the nested Cover's edition is on the wire.
fn cause() -> EventRef {
    EventRef {
        stream: Some(Cover {
            domain: "lists".into(),
            root: Some(uuid(0xab)),
            edition: "what-if".into(),
        }),
        sequence: u64::MAX,
    }
}

fn causation() -> Causation {
    Causation {
        event: Some(cause()),
        component: "list-to-draw".into(),
        index: 2,
    }
}

fn request() -> RequestOrigin {
    RequestOrigin {
        request_id: "req-1".into(),
        index: 3,
    }
}

fn fact_origin() -> FactOrigin {
    FactOrigin {
        external_id: "pi_1234".into(),
        description: "Stripe webhook".into(),
    }
}

fn meta(origin: event_meta::Origin) -> EventMeta {
    EventMeta {
        provenance: Some(provenance()),
        origin: Some(origin),
        recorded_at: Some(prost_types::Timestamp {
            seconds: 1_700_000_001,
            nanos: 0,
        }),
        decided_at: u64::from(u32::MAX) + 7,
        rules_version: "rules-3".into(),
    }
}

fn page(origin: event_meta::Origin) -> EventPage {
    EventPage {
        // Above u32::MAX: the widened sequence survives the wire.
        sequence: u64::from(u32::MAX) + 7,
        payload: Some(any("/orders.v1.OrderPlaced", &[1, 2, 3])),
        meta: Some(meta(origin)),
    }
}

fn event_origins() -> [event_meta::Origin; 3] {
    [
        event_meta::Origin::Request(request()),
        event_meta::Origin::Causation(causation()),
        event_meta::Origin::Fact(fact_origin()),
    ]
}

fn book(body: command_page::Body, expect: Option<Expectation>) -> CommandBook {
    CommandBook {
        cover: Some(Cover {
            domain: "draws".into(),
            root: Some(uuid(0xcd)),
            edition: String::new(), // main timeline
        }),
        page: Some(CommandPage {
            expect,
            provenance: Some(provenance()),
            body: Some(body),
        }),
    }
}

fn command_body(origin: command::Origin) -> command_page::Body {
    command_page::Body::Command(Command {
        payload: Some(any("/draws.v1.Draw", &[9])),
        origin: Some(origin),
    })
}

fn fact_body() -> command_page::Body {
    command_page::Body::Fact(Fact {
        payload: Some(any("/payments.v1.PaymentReceived", &[7])),
        source: Some(fact_origin()),
    })
}

fn expect() -> Option<Expectation> {
    Some(Expectation {
        sequence: u64::from(u32::MAX) + 1,
        strategy: MergeStrategy::MergeAggregateHandles as i32,
    })
}

fn bodies() -> [command_page::Body; 3] {
    [
        command_body(command::Origin::Request(request())),
        command_body(command::Origin::Causation(causation())),
        fact_body(),
    ]
}

fn round_trip<M: Message + Default>(m: &M) -> M {
    M::decode(m.encode_to_vec().as_slice()).expect("decode")
}

#[test]
fn command_page_round_trips_for_every_body_arm() {
    for body in bodies() {
        let original = book(body.clone(), expect());
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        let page = decoded.page.expect("single page");
        assert_eq!(page.provenance, Some(provenance()));
        assert_eq!(page.body, Some(body));
    }
}

#[test]
fn fact_arm_carries_its_fact_origin() {
    let decoded = round_trip(&book(fact_body(), None));
    match decoded.page.unwrap().body {
        Some(command_page::Body::Fact(f)) => {
            assert_eq!(f.source.unwrap().external_id, "pi_1234");
            assert_eq!(f.payload.unwrap().type_url, "/payments.v1.PaymentReceived");
        }
        other => panic!("expected fact arm, got {other:?}"),
    }
}

#[test]
fn command_arm_carries_its_causation() {
    let decoded = round_trip(&book(
        command_body(command::Origin::Causation(causation())),
        None,
    ));
    match decoded.page.unwrap().body {
        Some(command_page::Body::Command(Command {
            origin: Some(command::Origin::Causation(c)),
            ..
        })) => {
            assert_eq!(c.component, "list-to-draw");
            assert_eq!(c.index, 2);
            assert_eq!(c.event, Some(cause()));
        }
        other => panic!("expected command arm with causation, got {other:?}"),
    }
}

#[test]
fn absent_expectation_is_distinct_from_zero() {
    let body = bodies()[0].clone();
    let absent = round_trip(&book(body.clone(), None));
    assert_eq!(absent.page.unwrap().expect, None);

    let zero = Some(Expectation::default());
    let decoded = round_trip(&book(body, zero));
    assert_eq!(decoded.page.unwrap().expect, zero);
}

#[test]
fn expectation_round_trips_sequence_and_strategy() {
    let decoded = round_trip(&book(bodies()[0].clone(), expect()));
    let e = decoded.page.unwrap().expect.expect("expectation");
    assert_eq!(e.sequence, u64::from(u32::MAX) + 1);
    assert_eq!(e.strategy(), MergeStrategy::MergeAggregateHandles);
}

#[test]
fn event_meta_round_trips_every_origin_with_decided_at_and_provenance() {
    for origin in event_origins() {
        let original = page(origin.clone());
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        let meta = decoded.meta.unwrap();
        assert_eq!(meta.origin, Some(origin));
        assert_eq!(meta.decided_at, u64::from(u32::MAX) + 7);
        assert_eq!(meta.provenance, Some(provenance()));
        assert_eq!(meta.rules_version, "rules-3");
        assert!(meta.recorded_at.is_some());
    }
}

#[test]
fn event_ref_nests_a_cover_with_its_edition() {
    let decoded = round_trip(&cause());
    let stream = decoded.stream.expect("stream");
    assert_eq!(stream.domain, "lists");
    assert_eq!(stream.edition, "what-if");
    assert_eq!(stream.root, Some(uuid(0xab)));
    assert_eq!(decoded.sequence, u64::MAX);

    // Nested deeper: event meta -> causation -> event ref -> cover.
    let p = round_trip(&page(event_meta::Origin::Causation(causation())));
    match p.meta.unwrap().origin {
        Some(event_meta::Origin::Causation(c)) => {
            assert_eq!(c.event.unwrap().stream.unwrap().edition, "what-if")
        }
        other => panic!("expected causation, got {other:?}"),
    }
}

#[test]
fn event_meta_is_field_8_and_appended_after_the_page_body() {
    let mut p = page(event_origins()[0].clone());
    p.sequence = 0; // default: not encoded, so meta is the last field written
    let with = p.encode_to_vec();
    p.meta = None;
    let without = p.encode_to_vec();
    assert!(with.starts_with(&without));
    // Field 8, wire type 2 (length-delimited): tag byte 0x42.
    assert_eq!(with[without.len()], 0x42);
}

#[test]
fn response_meta_round_trips_each_outcome() {
    for outcome in [
        DeliveryOutcome::Unspecified,
        DeliveryOutcome::Applied,
        DeliveryOutcome::Duplicate,
    ] {
        let original = ResponseMeta {
            outcome: outcome as i32,
        };
        let decoded = round_trip(&original);
        assert_eq!(decoded.outcome(), outcome);
    }
    assert_eq!(
        DeliveryOutcome::Duplicate.as_str_name(),
        "DELIVERY_OUTCOME_DUPLICATE"
    );
}

#[test]
fn type_names_are_io_angzarr_v1() {
    assert_eq!(EventPage::full_name(), "io.angzarr.v1.EventPage");
    assert_eq!(EventMeta::full_name(), "io.angzarr.v1.EventMeta");
    assert_eq!(EventRef::full_name(), "io.angzarr.v1.EventRef");
    assert_eq!(Provenance::full_name(), "io.angzarr.v1.Provenance");
    assert_eq!(Expectation::full_name(), "io.angzarr.v1.Expectation");
    assert_eq!(CommandPage::full_name(), "io.angzarr.v1.CommandPage");
    assert_eq!(Command::full_name(), "io.angzarr.v1.Command");
    assert_eq!(Fact::full_name(), "io.angzarr.v1.Fact");
    assert_eq!(CommandBook::full_name(), "io.angzarr.v1.CommandBook");
    assert_eq!(RequestOrigin::full_name(), "io.angzarr.v1.RequestOrigin");
    assert_eq!(Causation::full_name(), "io.angzarr.v1.Causation");
    assert_eq!(FactOrigin::full_name(), "io.angzarr.v1.FactOrigin");
    assert_eq!(ResponseMeta::full_name(), "io.angzarr.v1.ResponseMeta");
    assert_eq!(UpcastRequest::full_name(), "io.angzarr.v1.UpcastRequest");
    // angzarr's TYPE_URL_PREFIX is "/" (see types.proto), which is prost's
    // default when no type-name domain is configured.
    assert_eq!(EventPage::type_url(), "/io.angzarr.v1.EventPage");
    assert_eq!(CommandBook::type_url(), "/io.angzarr.v1.CommandBook");
    assert_eq!(Fact::type_url(), "/io.angzarr.v1.Fact");
    assert_eq!(Causation::type_url(), "/io.angzarr.v1.Causation");
    assert_eq!(
        angzarr_proto::sererr::v1::CapturedError::full_name(),
        "sererr.v1.CapturedError"
    );

    let p = page(event_origins()[1].clone());
    let packed = prost_types::Any::from_msg(&p).expect("pack");
    assert_eq!(packed.type_url, "/io.angzarr.v1.EventPage");
    assert_eq!(packed.to_msg::<EventPage>().expect("unpack"), p);

    let b = book(fact_body(), None);
    let packed = prost_types::Any::from_msg(&b).expect("pack");
    assert_eq!(packed.type_url, "/io.angzarr.v1.CommandBook");
    assert_eq!(packed.to_msg::<CommandBook>().expect("unpack"), b);
}
