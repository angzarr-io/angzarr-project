use angzarr_proto::v1::{
    angzarr_dead_letter, command_page, origin, AngzarrDeadLetter, Causation, Command, CommandBook,
    CommandPage, ComponentDescriptor, ComponentKind, ConflictResolution, ContextualCommand,
    CorrelationQuery, Cover, DeliveryOutcome, EventBook, EventMeta, EventPage, EventRef, Fact,
    FactOrigin, Handling, IdempotencyClaim, Origin, Outcome, Projection, ProjectorFailure,
    Provenance, RequestOrigin, Snapshot, UpcastRequest, Uuid,
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
        correlation_id: Some(uuid(0xc0)),
    }
}

/// An event in a non-main edition, so the nested Cover's edition is on the wire.
fn cause() -> EventRef {
    EventRef {
        stream: Some(Cover {
            domain: "lists".into(),
            root: Some(uuid(0xab)),
            edition: Some("what-if".into()),
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
        request_id: Some(uuid(0x5e)),
        index: 3,
        minted: false,
    }
}

fn fact_origin() -> FactOrigin {
    FactOrigin {
        external_id: "pi_1234".into(),
        description: "Stripe webhook".into(),
    }
}

fn meta(kind: origin::Kind) -> EventMeta {
    EventMeta {
        provenance: Some(provenance()),
        origin: Some(Origin { kind: Some(kind) }),
        recorded_at: Some(prost_types::Timestamp {
            seconds: 1_700_000_001,
            nanos: 0,
        }),
        base_sequence: u64::from(u32::MAX) + 7,
        rules_version: "rules-3".into(),
    }
}

fn page(origin: origin::Kind) -> EventPage {
    EventPage {
        // Above u32::MAX: the widened sequence survives the wire.
        sequence: u64::from(u32::MAX) + 7,
        payload: Some(any("/orders.v1.OrderPlaced", &[1, 2, 3])),
        meta: Some(meta(origin)),
    }
}

fn origins() -> [origin::Kind; 3] {
    [
        origin::Kind::Request(request()),
        origin::Kind::Causation(causation()),
        origin::Kind::Fact(fact_origin()),
    ]
}

/// A command page: the body arm says what the payload is, the shared Origin
/// says why it exists.
fn book(body: command_page::Body, kind: origin::Kind, handling: Option<Handling>) -> CommandBook {
    CommandBook {
        cover: Some(Cover {
            domain: "draws".into(),
            root: Some(uuid(0xcd)),
            edition: None, // main timeline (unset)
        }),
        page: Some(CommandPage {
            provenance: Some(provenance()),
            body: Some(body),
            origin: Some(Origin { kind: Some(kind) }),
        }),
        handling,
    }
}

fn command_body() -> command_page::Body {
    command_page::Body::Command(Command {
        payload: Some(any("/draws.v1.Draw", &[9])),
    })
}

fn fact_body() -> command_page::Body {
    command_page::Body::Fact(Fact {
        payload: Some(any("/payments.v1.PaymentReceived", &[7])),
    })
}

fn handling() -> Option<Handling> {
    Some(Handling {
        expected_sequence: Some(u64::from(u32::MAX) + 1),
        conflict_resolution: ConflictResolution::AggregateHandles as i32,
    })
}

/// The valid (arm, origin) pairs: a Command with a request or causation
/// origin, a Fact with a fact origin.
fn pages() -> [(command_page::Body, origin::Kind); 3] {
    [
        (command_body(), origin::Kind::Request(request())),
        (command_body(), origin::Kind::Causation(causation())),
        (fact_body(), origin::Kind::Fact(fact_origin())),
    ]
}

fn request_book(handling: Option<Handling>) -> CommandBook {
    book(command_body(), origin::Kind::Request(request()), handling)
}

fn round_trip<M: Message + Default>(m: &M) -> M {
    M::decode(m.encode_to_vec().as_slice()).expect("decode")
}

#[test]
fn command_page_round_trips_every_arm_with_its_origin() {
    for (body, kind) in pages() {
        let original = book(body.clone(), kind.clone(), handling());
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        let page = decoded.page.expect("single page");
        assert_eq!(page.provenance, Some(provenance()));
        assert_eq!(page.body, Some(body));
        assert_eq!(page.origin, Some(Origin { kind: Some(kind) }));
    }
}

#[test]
fn fact_origin_rides_the_page_not_the_fact_arm() {
    let decoded = round_trip(&book(fact_body(), origin::Kind::Fact(fact_origin()), None));
    let page = decoded.page.unwrap();
    match (page.body, page.origin.and_then(|o| o.kind)) {
        (Some(command_page::Body::Fact(f)), Some(origin::Kind::Fact(o))) => {
            assert_eq!(o.external_id, "pi_1234");
            assert_eq!(f.payload.unwrap().type_url, "/payments.v1.PaymentReceived");
        }
        other => panic!("expected fact arm with fact origin, got {other:?}"),
    }
}

#[test]
fn command_page_origin_carries_its_causation() {
    let decoded = round_trip(&book(
        command_body(),
        origin::Kind::Causation(causation()),
        None,
    ));
    match decoded.page.unwrap().origin.and_then(|o| o.kind) {
        Some(origin::Kind::Causation(c)) => {
            assert_eq!(c.component, "list-to-draw");
            assert_eq!(c.index, 2);
            assert_eq!(c.event, Some(cause()));
        }
        other => panic!("expected causation origin, got {other:?}"),
    }
}

#[test]
fn one_origin_message_is_shared_by_page_meta_and_claim() {
    // The page's origin is copied unchanged onto the event meta and used as
    // the claim key: one type, byte-identical, no mapping.
    for (body, kind) in pages() {
        let page_origin = book(body, kind.clone(), None).page.unwrap().origin.unwrap();
        let meta_origin = meta(kind.clone()).origin.unwrap();
        let claim = IdempotencyClaim {
            key: Some(page_origin.clone()),
            ..IdempotencyClaim::default()
        };
        assert_eq!(page_origin, meta_origin);
        assert_eq!(
            round_trip(&claim).key.unwrap().encode_to_vec(),
            meta_origin.encode_to_vec()
        );
    }
}

#[test]
fn request_origin_records_whether_its_request_id_was_minted() {
    // Client-supplied: minted unset, the default, so it costs no bytes on
    // the wire and a client never has to set anything.
    let client = request();
    assert!(!client.minted);
    assert_eq!(
        client.encode_to_vec(),
        RequestOrigin {
            request_id: Some(uuid(0x5e)),
            index: 3,
            ..Default::default()
        }
        .encode_to_vec()
    );

    // Minted by the coordinator: a UUIDv7 (its 16 bytes), flagged, and
    // recorded on the event meta exactly as on the page.
    let minted = RequestOrigin {
        request_id: Some("01920c8e-7b3a-7cc2-9f4e-5a1b2c3d4e5f".parse().unwrap()),
        index: 0,
        minted: true,
    };
    let kind = origin::Kind::Request(minted.clone());
    let decoded = round_trip(&meta(kind));
    match decoded.origin.and_then(|o| o.kind) {
        Some(origin::Kind::Request(r)) => {
            assert!(r.minted);
            assert_eq!(r, minted);
            // Version nibble 7 (RFC 9562): the high nibble of byte 6.
            assert_eq!(r.request_id.unwrap().value[6] >> 4, 7);
        }
        other => panic!("expected request origin, got {other:?}"),
    }
    assert_ne!(minted.encode_to_vec(), {
        let mut m = minted.clone();
        m.minted = false;
        m.encode_to_vec()
    });
}

#[test]
fn absent_expected_sequence_is_distinct_from_zero() {
    let absent = round_trip(&request_book(Some(Handling::default())));
    assert_eq!(absent.handling.unwrap().expected_sequence, None);

    let zero = Some(Handling {
        expected_sequence: Some(0),
        ..Handling::default()
    });
    let decoded = round_trip(&request_book(zero));
    assert_eq!(decoded.handling, zero);
    assert_eq!(decoded.handling.unwrap().expected_sequence, Some(0));
}

#[test]
fn handling_rides_the_command_book_not_the_page() {
    let decoded = round_trip(&request_book(handling()));
    let h = decoded.handling.expect("handling");
    assert_eq!(h.expected_sequence, Some(u64::from(u32::MAX) + 1));
    assert_eq!(
        h.conflict_resolution(),
        ConflictResolution::AggregateHandles
    );

    // The page is provenance + body + origin only: encoding it with and
    // without the book's handling yields the same page bytes.
    let with = request_book(handling());
    let without = request_book(None);
    assert_eq!(
        with.page.unwrap().encode_to_vec(),
        without.page.unwrap().encode_to_vec()
    );
}

#[test]
fn unset_handling_reads_as_unspecified_defaults() {
    // Unspecified conflict resolution means "use configuration", not STRICT.
    let h = round_trip(&request_book(None)).handling.unwrap_or_default();
    assert_eq!(h.expected_sequence, None);
    assert_eq!(h.conflict_resolution(), ConflictResolution::Unspecified);
}

#[test]
fn conflict_resolution_values_are_lint_conformant_and_keep_their_numbers() {
    // Renamed from MergeStrategy; the numbers are unchanged, and COMMUTATIVE
    // is restored (opt-in, resolved in the client library) at its old 1.
    for (value, number, name) in [
        (
            ConflictResolution::Unspecified,
            0,
            "CONFLICT_RESOLUTION_UNSPECIFIED",
        ),
        (
            ConflictResolution::Commutative,
            1,
            "CONFLICT_RESOLUTION_COMMUTATIVE",
        ),
        (ConflictResolution::Strict, 2, "CONFLICT_RESOLUTION_STRICT"),
        (
            ConflictResolution::AggregateHandles,
            3,
            "CONFLICT_RESOLUTION_AGGREGATE_HANDLES",
        ),
    ] {
        assert_eq!(value as i32, number);
        assert_eq!(value.as_str_name(), name);
        assert_eq!(ConflictResolution::from_str_name(name), Some(value));
        let h = Handling {
            expected_sequence: Some(4),
            conflict_resolution: value as i32,
        };
        assert_eq!(round_trip(&h).conflict_resolution(), value);
    }
}

#[test]
fn contextual_command_carries_the_conflict_nonce() {
    let nonce = vec![0x9e; 16];
    let original = ContextualCommand {
        events: Some(EventBook {
            next_sequence: 12,
            ..EventBook::default()
        }),
        command: Some(request_book(handling())),
        conflict_nonce: nonce.clone(),
    };
    let decoded = round_trip(&original);
    assert_eq!(decoded, original);
    assert_eq!(decoded.conflict_nonce, nonce);

    // Under STRICT there is no nonce: empty, and absent from the wire. The
    // nonce is field 3 (tag 0x1a), written after the book and the command.
    let strict = ContextualCommand {
        conflict_nonce: vec![],
        ..original.clone()
    };
    let with = original.encode_to_vec();
    let without = strict.encode_to_vec();
    assert!(with.starts_with(&without));
    assert_eq!(
        &with[without.len()..],
        &[&[0x1a, 16][..], &nonce[..]].concat()[..]
    );
    assert!(round_trip(&strict).conflict_nonce.is_empty());
}

#[test]
fn snapshot_records_state_type_and_rules_version() {
    let original = Snapshot {
        sequence: u64::from(u32::MAX) + 9,
        state: Some(any("/draws.v1.DrawState", &[1, 1])),
        rules_version: "rules-3".into(),
    };
    let decoded = round_trip(&original);
    assert_eq!(decoded, original);
    // Both halves of the load-time validity check survive the wire: the
    // state type (the Any's type URL) and the rules version.
    assert_eq!(decoded.state.unwrap().type_url, "/draws.v1.DrawState");
    assert_eq!(decoded.rules_version, "rules-3");
    // Field 5: a fresh number (4 was the pass-2 retention field).
    let bare = Snapshot {
        rules_version: "r".into(),
        ..Snapshot::default()
    };
    assert_eq!(bare.encode_to_vec(), vec![0x2a, 1, b'r']);
}

#[test]
fn handling_carries_no_sync_mode() {
    // Sync is a call-level choice (which coordinator RPC), not handling. A
    // pre-pass-4 sender's field 3 (sync = DECISION) is not part of Handling:
    // it decodes to nothing and does not survive re-encoding.
    let current = Handling {
        expected_sequence: Some(5),
        conflict_resolution: ConflictResolution::Strict as i32,
    };
    let mut legacy = current.encode_to_vec();
    legacy.extend_from_slice(&[0x18, 0x04]); // field 3, varint 4
    let decoded = Handling::decode(legacy.as_slice()).expect("decode");
    assert_eq!(decoded, current);
    assert_eq!(decoded.encode_to_vec(), current.encode_to_vec());
}

#[test]
fn event_meta_round_trips_every_origin_with_base_sequence_and_provenance() {
    for kind in origins() {
        let original = page(kind.clone());
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        let meta = decoded.meta.unwrap();
        assert_eq!(meta.origin, Some(Origin { kind: Some(kind) }));
        assert_eq!(meta.base_sequence, u64::from(u32::MAX) + 7);
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
    assert_eq!(stream.edition.as_deref(), Some("what-if"));
    assert_eq!(stream.root, Some(uuid(0xab)));
    assert_eq!(decoded.sequence, u64::MAX);

    // Nested deeper: event meta -> causation -> event ref -> cover.
    let p = round_trip(&page(origin::Kind::Causation(causation())));
    match p.meta.unwrap().origin.and_then(|o| o.kind) {
        Some(origin::Kind::Causation(c)) => {
            assert_eq!(
                c.event.unwrap().stream.unwrap().edition.as_deref(),
                Some("what-if")
            )
        }
        other => panic!("expected causation, got {other:?}"),
    }
}

/// Main is unset, not a magic name: an unset edition is absent from the wire
/// and decodes as None (main); a set empty string is a different value on the
/// wire (explicit presence), so a server can refuse it as malformed rather
/// than read it as main; a named edition round-trips.
#[test]
fn edition_unset_is_main_and_a_set_empty_string_is_distinguishable() {
    let cover = |edition: Option<&str>| Cover {
        domain: "draws".into(),
        root: Some(uuid(0xcd)),
        edition: edition.map(Into::into),
    };

    let main = cover(None);
    let main_bytes = main.encode_to_vec();
    assert_eq!(round_trip(&main).edition, None);
    assert_eq!(Cover::default().edition, None, "the default cover is main");

    let empty = cover(Some(""));
    let empty_bytes = empty.encode_to_vec();
    // Field 4, wire type 2, length 0: present on the wire though empty.
    assert!(empty_bytes.ends_with(&[0x22, 0x00]));
    assert_ne!(empty_bytes, main_bytes);
    assert_eq!(round_trip(&empty).edition.as_deref(), Some(""));

    let named = cover(Some("what-if"));
    assert_eq!(round_trip(&named), named);
    assert_eq!(round_trip(&named).edition.as_deref(), Some("what-if"));

    // CorrelationQuery.edition follows the same convention.
    for edition in [None, Some(String::new()), Some("what-if".to_string())] {
        let q = CorrelationQuery {
            correlation_id: Some(uuid(0xc0)),
            edition: edition.clone(),
        };
        assert_eq!(round_trip(&q).edition, edition);
    }
    assert_ne!(
        CorrelationQuery {
            correlation_id: Some(uuid(0xc0)),
            edition: None,
        }
        .encode_to_vec(),
        CorrelationQuery {
            correlation_id: Some(uuid(0xc0)),
            edition: Some(String::new()),
        }
        .encode_to_vec()
    );
}

#[test]
fn event_meta_is_field_8_and_appended_after_the_page_body() {
    let mut p = page(origins()[0].clone());
    p.sequence = 0; // default: not encoded, so meta is the last field written
    let with = p.encode_to_vec();
    p.meta = None;
    let without = p.encode_to_vec();
    assert!(with.starts_with(&without));
    // Field 8, wire type 2 (length-delimited): tag byte 0x42.
    assert_eq!(with[without.len()], 0x42);
}

#[test]
fn outcome_round_trips_each_delivery_with_projections_and_failures() {
    let projection = Projection {
        cover: Some(Cover {
            domain: "draws".into(),
            root: Some(uuid(0xcd)),
            edition: None,
        }),
        projector: "draw-history".into(),
        // The stream's next_sequence after the projected events.
        next_sequence: u64::from(u32::MAX) + 2,
        projection: Some(any("/draws.v1.DrawHistory", &[4])),
    };
    // HandleSync answers OK with the successful projections beside the
    // failed ones; a failure never replaces the events.
    let failure = ProjectorFailure {
        projector: "draw-stats".into(),
        code: 14, // UNAVAILABLE
        message: "stats store down".into(),
    };
    for delivery in [
        DeliveryOutcome::Unspecified,
        DeliveryOutcome::Applied,
        DeliveryOutcome::Duplicate,
        DeliveryOutcome::Parked,
    ] {
        let original = Outcome {
            delivery: delivery as i32,
            projections: vec![projection.clone()],
            projector_failures: vec![failure.clone()],
        };
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        assert_eq!(decoded.delivery(), delivery);
        assert_eq!(decoded.projections, vec![projection.clone()]);
        assert_eq!(decoded.projector_failures, vec![failure.clone()]);
    }
    assert_eq!(
        DeliveryOutcome::Duplicate.as_str_name(),
        "DELIVERY_OUTCOME_DUPLICATE"
    );
    // A failed fact ingest is "accepted, parked": its own outcome, neither a
    // rejection nor APPLIED.
    assert_eq!(DeliveryOutcome::Parked as i32, 3);
    assert_eq!(
        DeliveryOutcome::Parked.as_str_name(),
        "DELIVERY_OUTCOME_PARKED"
    );
}

#[test]
fn idempotency_claim_round_trips_each_key_kind_with_an_empty_range() {
    for kind in origins() {
        let key = Origin { kind: Some(kind) };
        // Zero events is a valid applied outcome, and it is claimed too.
        let original = IdempotencyClaim {
            stream: Some(Cover {
                domain: "draws".into(),
                root: Some(uuid(0xcd)),
                edition: None,
            }),
            key: Some(key.clone()),
            fingerprint: vec![0x5a; 32],
            first_sequence: u64::from(u32::MAX) + 3,
            event_count: 0,
            claimed_at: Some(prost_types::Timestamp {
                seconds: 1_700_000_001,
                nanos: 0,
            }),
            expires_at: Some(prost_types::Timestamp {
                seconds: 1_700_086_401,
                nanos: 0,
            }),
        };
        let decoded = round_trip(&original);
        assert_eq!(decoded, original);
        assert_eq!(decoded.key, Some(key));
        assert_eq!(decoded.first_sequence, u64::from(u32::MAX) + 3);
        assert_eq!(decoded.event_count, 0);
    }
}

#[test]
fn component_descriptor_declares_rules_version() {
    let original = ComponentDescriptor {
        name: "draw-system".into(),
        kind: ComponentKind::Aggregate as i32,
        inputs: vec![],
        rules_version: "rules-3".into(),
    };
    let decoded = round_trip(&original);
    assert_eq!(decoded, original);
    assert_eq!(decoded.rules_version, "rules-3");
    assert_eq!(decoded.kind(), ComponentKind::Aggregate);
}

#[test]
fn dead_letter_names_its_component_kind_and_takes_the_cover_from_its_payload() {
    let rejected = request_book(handling());
    let original = AngzarrDeadLetter {
        payload: Some(angzarr_dead_letter::Payload::RejectedCommand(
            rejected.clone(),
        )),
        source_component: "list-to-draw".into(),
        source_component_kind: ComponentKind::Saga as i32,
        ..AngzarrDeadLetter::default()
    };
    let decoded = round_trip(&original);
    assert_eq!(decoded, original);
    assert_eq!(decoded.source_component_kind(), ComponentKind::Saga);
    match decoded.payload {
        Some(angzarr_dead_letter::Payload::RejectedCommand(b)) => {
            assert_eq!(b.cover, rejected.cover)
        }
        other => panic!("expected rejected command, got {other:?}"),
    }
}

#[test]
fn type_names_are_io_angzarr_v1() {
    assert_eq!(EventPage::full_name(), "io.angzarr.v1.EventPage");
    assert_eq!(EventMeta::full_name(), "io.angzarr.v1.EventMeta");
    assert_eq!(EventRef::full_name(), "io.angzarr.v1.EventRef");
    assert_eq!(Provenance::full_name(), "io.angzarr.v1.Provenance");
    assert_eq!(Handling::full_name(), "io.angzarr.v1.Handling");
    assert_eq!(CommandPage::full_name(), "io.angzarr.v1.CommandPage");
    assert_eq!(Command::full_name(), "io.angzarr.v1.Command");
    assert_eq!(Fact::full_name(), "io.angzarr.v1.Fact");
    assert_eq!(CommandBook::full_name(), "io.angzarr.v1.CommandBook");
    assert_eq!(RequestOrigin::full_name(), "io.angzarr.v1.RequestOrigin");
    assert_eq!(Causation::full_name(), "io.angzarr.v1.Causation");
    assert_eq!(FactOrigin::full_name(), "io.angzarr.v1.FactOrigin");
    assert_eq!(Origin::full_name(), "io.angzarr.v1.Origin");
    assert_eq!(Outcome::full_name(), "io.angzarr.v1.Outcome");
    assert_eq!(
        IdempotencyClaim::full_name(),
        "io.angzarr.v1.IdempotencyClaim"
    );
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

    let p = page(origins()[1].clone());
    let packed = prost_types::Any::from_msg(&p).expect("pack");
    assert_eq!(packed.type_url, "/io.angzarr.v1.EventPage");
    assert_eq!(packed.to_msg::<EventPage>().expect("unpack"), p);

    let b = book(fact_body(), origin::Kind::Fact(fact_origin()), None);
    let packed = prost_types::Any::from_msg(&b).expect("pack");
    assert_eq!(packed.type_url, "/io.angzarr.v1.CommandBook");
    assert_eq!(packed.to_msg::<CommandBook>().expect("unpack"), b);
}
