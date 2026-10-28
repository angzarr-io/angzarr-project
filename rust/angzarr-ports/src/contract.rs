//! The conformance suite: what every backend must do, as checks a backend's
//! own tests run, one test per check. annals' `store_contract!` /
//! `async_store_contract!`, moved here, reshaped to the shared ports, and
//! joined by core's cases (bounded reads, the head, positions, the stale
//! first sequence).
//!
//! **Shape.**
//! - Each check is a `pub async fn` taking a fresh, EMPTY store and
//!   panicking, naming what failed. The pages are opaque to a store, so the
//!   checks write their own and never decode a payload.
//! - The checks are generic over the [`local`](crate::local) ports, so one
//!   suite runs on a `Send` backend (through the blanket impls), a
//!   single-threaded wasm backend, and `Arc<dyn DynStore>` alike.
//! - The checks assume no runtime: the caller's test attribute supplies one.
//! - [`store_contract!`](crate::store_contract) stamps one test per check:
//!
//! ```ignore
//! angzarr_ports::store_contract!(#[tokio::test], MyStore::fresh().await);
//! angzarr_ports::store_contract!(purge, #[tokio::test], MyStore::fresh().await);
//! angzarr_ports::store_contract!(editions, #[tokio::test], MyStore::fresh().await);
//! angzarr_ports::store_contract!(pair, #[tokio::test], MyStore::fresh_pair().await);
//! ```
//!
//! **Sections.** The base section is every store's. `purge` and `editions`
//! are opt-in, for a store implementing [`Purge`](crate::Purge) (with
//! [`UnitPurge`](crate::UnitPurge) on its unit) or
//! [`Editions`](crate::Editions). `pair` takes two handles on one fresh
//! store (`(a, b)`: two connections to one database, which a test makes on
//! a file) and writes through one while the other reads, so a store whose
//! answer is the handle's rather than the store's is caught.

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::event_meta::Causation;
use angzarr_proto::v1::{Cover, CreateEditionRequest, EventMeta, EventPage, EventRef, Snapshot};
use prost_types::{Any, Timestamp};

use crate::error::StoreError;
use crate::local::{LocalEditions, LocalPurge, LocalStore, LocalUnit, LocalUnitPurge};
use crate::store::DEFAULT_EDITION_STORE;
use crate::stream::{PositionKey, StreamRef};

// ------------------------------------------------------------- the fixtures

/// The instant `page(sequence, _)` records.
pub fn at(sequence: u64) -> Timestamp {
    Timestamp {
        seconds: sequence as i64,
        nanos: 0,
    }
}

/// Command `n`'s id.
pub fn command(n: u8) -> Uuid {
    Uuid::from_bytes([n; 16])
}

/// `domain`'s stream `n` on the main timeline.
pub fn main_stream(domain: &'static str, n: u8) -> StreamRef<'static> {
    StreamRef::main(domain, Uuid::from_bytes([n; 16]))
}

/// `domain`'s stream `n` in `edition`.
pub fn edition_stream(domain: &'static str, n: u8, edition: &'static str) -> StreamRef<'static> {
    StreamRef::in_edition(domain, edition, Uuid::from_bytes([n; 16]))
}

/// The event at `sequence`, produced by command `n`.
pub fn page(sequence: u64, n: u8) -> EventPage {
    stamped(sequence, Causation::CommandId(command(n).into()))
}

/// A process manager's event at `sequence`, written in reaction to
/// `trigger`: no command (spec 13.2).
pub fn triggered(sequence: u64, trigger: &EventRef) -> EventPage {
    stamped(sequence, Causation::TriggeringEvent(trigger.clone()))
}

/// The event at `sequence` of `stream`, as a trigger.
pub fn event_ref(stream: StreamRef<'_>, sequence: u64) -> EventRef {
    EventRef {
        stream: Some(stream.to_cover()),
        sequence,
    }
}

/// A snapshot after event `sequence`, under `rules`.
pub fn snapshot(sequence: u64, rules: &str) -> Snapshot {
    Snapshot {
        sequence,
        state: Some(Any {
            type_url: "/angzarr.contract.v1.State".to_string(),
            value: sequence.to_be_bytes().to_vec(),
        }),
        rules_version: rules.to_string(),
    }
}

fn stamped(sequence: u64, causation: Causation) -> EventPage {
    EventPage {
        payload: Some(Any {
            type_url: "/angzarr.contract.v1.Page".to_string(),
            value: sequence.to_be_bytes().to_vec(),
        }),
        meta: Some(EventMeta {
            causation: Some(causation),
            correlation_id: Some(command(0xC0).into()),
            recorded_at: Some(at(sequence)),
            rules_version: "v1".to_string(),
            ..EventMeta::default()
        }),
        sequence,
    }
}

fn covers(streams: &[StreamRef<'_>]) -> Vec<Cover> {
    streams.iter().map(StreamRef::to_cover).collect()
}

fn conflict(stream: StreamRef<'_>, expected: u64, actual: u64) -> StoreError {
    StoreError::Conflict {
        stream: stream.to_cover(),
        expected,
        actual,
    }
}

fn key<'a>(handler: &'a str, stream: StreamRef<'a>) -> PositionKey<'a> {
    PositionKey { handler, stream }
}

// --------------------------------------------------------- base: appends

pub async fn append_checks_the_expected_length_and_continuity<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    assert_eq!(store.append(s, 0, &[page(0, 1), page(1, 1)]).await, Ok(2));
    assert_eq!(
        store.append(s, 1, &[page(1, 2)]).await,
        Err(conflict(s, 1, 2)),
        "a stream not at expected"
    );
    assert_eq!(
        store.append(s, 2, &[page(3, 2)]).await,
        Err(StoreError::Discontinuous {
            stream: s.to_cover(),
            expected: 2,
            found: 3
        }),
        "a page that does not run on"
    );
    assert_eq!(store.append(s, 2, &[page(2, 2)]).await, Ok(3));
    let all = store.read(s, 0, None).await.unwrap();
    assert_eq!(
        all.pages,
        [page(0, 1), page(1, 1), page(2, 2)],
        "nothing refused landed"
    );
}

/// Core's rule, "the first page must be the head", is `expected =
/// pages[0].sequence`: a writer whose stamped pages are stale is refused,
/// as a conflict, not a gap.
pub async fn append_refuses_a_stale_first_sequence<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let stale = [page(0, 2), page(1, 2)];
    store.append(s, 0, &[page(0, 1)]).await.unwrap();
    assert_eq!(
        store.append(s, stale[0].sequence, &stale).await,
        Err(conflict(s, 0, 1))
    );
    let fresh = [page(1, 2), page(2, 2)];
    assert_eq!(store.append(s, fresh[0].sequence, &fresh).await, Ok(3));
}

pub async fn an_empty_append_checks_and_creates_nothing<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    assert_eq!(store.append(s, 0, &[]).await, Ok(0));
    assert_eq!(store.covers("account").await, Ok(vec![]), "no stream made");
    assert_eq!(store.append(s, 1, &[]).await, Err(conflict(s, 1, 0)));
    let before = store.commit_position().await.unwrap();
    let mut unit = store.begin().await.unwrap();
    assert_eq!(unit.append(s, 0, &[]).await, Ok(0));
    assert_eq!(unit.covers("account").await, Ok(vec![]));
    unit.commit().await.unwrap();
    assert_eq!(store.covers("account").await, Ok(vec![]));
    assert_eq!(
        store.commit_position().await,
        Ok(before),
        "nothing appended, nothing committed"
    );
}

// ----------------------------------------------------------- base: reads

pub async fn read_is_bounded_by_from_and_to<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let pages: Vec<_> = (0..5).map(|n| page(n, 1)).collect();
    store.append(s, 0, &pages).await.unwrap();
    let mid = store.read(s, 1, Some(3)).await.unwrap();
    assert_eq!(mid.pages, pages[1..3], "from inclusive, to exclusive");
    assert_eq!(mid.next_sequence, 5, "the stream's end, not the range's");
    assert_eq!(mid.last_recorded_at, Some(at(4)));
    assert_eq!(store.read(s, 3, None).await.unwrap().pages, pages[3..]);
    assert_eq!(store.read(s, 2, Some(2)).await.unwrap().pages, []);
    assert_eq!(
        store.read(s, 4, Some(99)).await.unwrap().pages,
        pages[4..],
        "a `to` past the end stops at the end"
    );
}

/// "No such stream" is an empty slice at 0: the same answer as a stream
/// never written, so no backend has to tell the two apart.
pub async fn a_read_of_no_such_stream_is_empty_at_zero<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let slice = store.read(s, 0, None).await.unwrap();
    assert_eq!(slice.pages, []);
    assert_eq!(slice.next_sequence, 0);
    assert_eq!(slice.last_recorded_at, None);
}

pub async fn a_read_past_the_end_is_empty_but_knows_the_end<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    let slice = store.read(s, 7, None).await.unwrap();
    assert_eq!(slice.pages, []);
    assert_eq!(slice.next_sequence, 2);
    assert_eq!(slice.last_recorded_at, Some(at(1)));
}

pub async fn head_is_the_next_sequence_and_the_last_recorded_at<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let head = store.head(s).await.unwrap();
    assert_eq!((head.next_sequence, head.last_recorded_at), (0, None));
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    let head = store.head(s).await.unwrap();
    assert_eq!(
        (head.next_sequence, head.last_recorded_at),
        (2, Some(at(1)))
    );
    assert_eq!(
        head,
        store.read(s, 0, None).await.unwrap().head(),
        "an overridden head agrees with a read"
    );
}

// --------------------------------------------------------- base: streams

pub async fn a_stream_is_domain_edition_and_root<S: LocalStore>(store: S) {
    let streams = [
        main_stream("account", 1),
        main_stream("ledger", 1),
        edition_stream("account", 1, "what-if"),
        main_stream("account", 2),
    ];
    for (n, s) in streams.iter().enumerate() {
        store.append(*s, 0, &[page(0, n as u8)]).await.unwrap();
    }
    for (n, s) in streams.iter().enumerate() {
        assert_eq!(
            store.read(*s, 0, None).await.unwrap().pages,
            [page(0, n as u8)],
            "{s:?} holds its own page only"
        );
    }
    assert_eq!(
        store.covers("account").await,
        Ok(covers(&[streams[0], streams[3], streams[2]]))
    );
    assert_eq!(store.covers("ledger").await, Ok(covers(&[streams[1]])));
    assert_eq!(store.covers("nowhere").await, Ok(vec![]));
}

pub async fn covers_orders_main_first_then_by_edition_and_root<S: LocalStore>(store: S) {
    for s in [
        edition_stream("account", 1, "b"),
        main_stream("account", 2),
        edition_stream("account", 2, "a"),
        main_stream("account", 1),
        edition_stream("account", 1, "a"),
    ] {
        store.append(s, 0, &[page(0, 1)]).await.unwrap();
    }
    assert_eq!(
        store.covers("account").await,
        Ok(covers(&[
            main_stream("account", 1),
            main_stream("account", 2),
            edition_stream("account", 1, "a"),
            edition_stream("account", 2, "a"),
            edition_stream("account", 1, "b"),
        ]))
    );
}

// ----------------------------------------------------------- base: dedup

pub async fn find_command_finds_a_commands_events_on_its_stream<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    store
        .append(s, 0, &[page(0, 1), page(1, 2), page(2, 2)])
        .await
        .unwrap();
    assert_eq!(
        store.find_command(s, command(2)).await,
        Ok(vec![page(1, 2), page(2, 2)]),
        "every event of the command, in order: the index is not unique"
    );
    assert_eq!(store.find_command(s, command(3)).await, Ok(vec![]));
    assert_eq!(
        store
            .find_command(main_stream("account", 2), command(2))
            .await,
        Ok(vec![]),
        "per stream"
    );
}

pub async fn find_triggered_finds_a_process_managers_events_by_trigger<S: LocalStore>(store: S) {
    let pm = main_stream("shipping", 1);
    let order = main_stream("order", 7);
    let (first, second) = (event_ref(order, 0), event_ref(order, 1));
    store
        .append(
            pm,
            0,
            &[
                triggered(0, &first),
                triggered(1, &first),
                triggered(2, &second),
                page(3, 9),
            ],
        )
        .await
        .unwrap();
    assert_eq!(
        store.find_triggered(pm, &first).await,
        Ok(vec![triggered(0, &first), triggered(1, &first)])
    );
    assert_eq!(
        store.find_triggered(pm, &second).await,
        Ok(vec![triggered(2, &second)])
    );
    assert_eq!(
        store.find_triggered(pm, &event_ref(order, 2)).await,
        Ok(vec![]),
        "another sequence of the same stream"
    );
    assert_eq!(
        store
            .find_triggered(pm, &event_ref(edition_stream("order", 7, "what-if"), 0))
            .await,
        Ok(vec![]),
        "the same root and sequence in another edition"
    );
    assert_eq!(
        store.find_command(pm, command(9)).await,
        Ok(vec![page(3, 9)]),
        "a command's event on a PM's stream is still found by command"
    );
}

// ------------------------------------------------------- base: snapshots

/// The store keeps what was written last, and judges nothing: an older
/// sequence or other rules written after replaces the one before. Whether
/// it is usable is the caller's.
pub async fn a_store_keeps_the_newest_snapshot_per_stream<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    assert_eq!(store.read_snapshot(s).await, Ok(None));
    store.write_snapshot(s, &snapshot(1, "v1")).await.unwrap();
    store.write_snapshot(s, &snapshot(4, "v1")).await.unwrap();
    assert_eq!(store.read_snapshot(s).await, Ok(Some(snapshot(4, "v1"))));
    store.write_snapshot(s, &snapshot(2, "v0")).await.unwrap();
    assert_eq!(
        store.read_snapshot(s).await,
        Ok(Some(snapshot(2, "v0"))),
        "last written, not highest sequence: the caller judges"
    );
    assert_eq!(
        store.read_snapshot(main_stream("account", 2)).await,
        Ok(None)
    );
    let mut unit = store.begin().await.unwrap();
    assert_eq!(unit.read_snapshot(s).await, Ok(Some(snapshot(2, "v0"))));
}

// ------------------------------------------------------- base: positions

pub async fn a_position_is_zero_until_put_then_the_last_put<S: LocalStore>(store: S) {
    let k = key("ledger-projector", main_stream("account", 1));
    assert_eq!(store.position(k).await, Ok(0));
    store.put_position(k, 3).await.unwrap();
    assert_eq!(store.position(k).await, Ok(3));
    store.put_position(k, 1).await.unwrap();
    assert_eq!(
        store.position(k).await,
        Ok(1),
        "a reset may lower it: monotonicity is the dispatcher's"
    );
}

pub async fn positions_are_per_handler_and_per_stream<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    store.put_position(key("a", s), 5).await.unwrap();
    assert_eq!(store.position(key("b", s)).await, Ok(0), "another handler");
    assert_eq!(
        store.position(key("a", main_stream("account", 2))).await,
        Ok(0),
        "another root"
    );
    assert_eq!(
        store.position(key("a", main_stream("ledger", 1))).await,
        Ok(0),
        "another domain"
    );
    assert_eq!(
        store
            .position(key("a", edition_stream("account", 1, "what-if")))
            .await,
        Ok(0),
        "another edition"
    );
    assert_eq!(store.position(key("a", s)).await, Ok(5));
}

// ------------------------------------------------- base: commit position

pub async fn the_commit_position_rises_with_every_commit<S: LocalStore>(store: S) {
    let empty = store.commit_position().await.unwrap();
    store
        .append(main_stream("account", 1), 0, &[page(0, 1)])
        .await
        .unwrap();
    let appended = store.commit_position().await.unwrap();
    assert!(appended > empty, "an append: {empty}, then {appended}");
    store
        .append(main_stream("ledger", 1), 0, &[page(0, 2)])
        .await
        .unwrap();
    let elsewhere = store.commit_position().await.unwrap();
    assert!(
        elsewhere > appended,
        "another domain: {appended}, then {elsewhere}"
    );
    let mut unit = store.begin().await.unwrap();
    unit.append(main_stream("account", 1), 1, &[page(1, 3)])
        .await
        .unwrap();
    unit.append(main_stream("account", 2), 0, &[page(0, 3)])
        .await
        .unwrap();
    let pending = store.commit_position().await.unwrap();
    assert_eq!(pending, elsewhere, "an open unit has committed nothing");
    unit.commit().await.unwrap();
    let committed = store.commit_position().await.unwrap();
    assert!(
        committed > elsewhere,
        "a unit: {elsewhere}, then {committed}"
    );
    store
        .write_snapshot(main_stream("account", 1), &snapshot(1, "v1"))
        .await
        .unwrap();
    store
        .put_position(key("h", main_stream("account", 1)), 2)
        .await
        .unwrap();
    assert_eq!(
        store.commit_position().await,
        Ok(committed),
        "a snapshot or a position is no event"
    );
}

// ------------------------------------------------------ base: units of work

pub async fn a_unit_of_work_lands_at_commit_or_not_at_all<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    {
        let mut unit = store.begin().await.unwrap();
        unit.append(s, 0, &[page(0, 1)]).await.unwrap();
    }
    assert_eq!(
        store.head(s).await.unwrap().next_sequence,
        0,
        "dropped: rolled back"
    );
    assert_eq!(
        store.covers("account").await,
        Ok(vec![]),
        "dropped: no stream"
    );
    let mut unit = store.begin().await.unwrap();
    unit.append(s, 0, &[page(0, 1)]).await.unwrap();
    assert_eq!(
        store.head(s).await.unwrap().next_sequence,
        0,
        "not seen outside before commit"
    );
    unit.commit().await.unwrap();
    assert_eq!(store.read(s, 0, None).await.unwrap().pages, [page(0, 1)]);
}

pub async fn an_aborted_unit_of_work_lands_nothing<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let k = key("h", s);
    let mut unit = store.begin().await.unwrap();
    unit.append(s, 0, &[page(0, 1)]).await.unwrap();
    unit.put_position(k, 1).await.unwrap();
    unit.abort().await.unwrap();
    assert_eq!(store.head(s).await.unwrap().next_sequence, 0);
    assert_eq!(store.position(k).await, Ok(0));
    assert_eq!(
        store.append(s, 0, &[page(0, 2)]).await,
        Ok(1),
        "free to write again"
    );
}

pub async fn a_unit_of_work_checks_and_reads_its_pending_appends<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let other = main_stream("account", 2);
    store.append(s, 0, &[page(0, 1)]).await.unwrap();
    let mut unit = store.begin().await.unwrap();
    assert_eq!(unit.head(other).await.unwrap().next_sequence, 0);
    assert_eq!(unit.append(s, 1, &[page(1, 2)]).await, Ok(2));
    assert_eq!(
        unit.append(s, 1, &[page(1, 3)]).await,
        Err(conflict(s, 1, 2)),
        "its own pending append counts"
    );
    assert_eq!(
        unit.append(s, 2, &[page(2, 3), page(4, 3)]).await,
        Err(StoreError::Discontinuous {
            stream: s.to_cover(),
            expected: 3,
            found: 4
        })
    );
    assert_eq!(unit.append(other, 0, &[page(0, 4)]).await, Ok(1));
    let slice = unit.read(s, 1, None).await.unwrap();
    assert_eq!(slice.pages, [page(1, 2)]);
    assert_eq!(slice.next_sequence, 2);
    assert_eq!(slice.last_recorded_at, Some(at(1)));
    assert_eq!(unit.read(other, 0, None).await.unwrap().pages, [page(0, 4)]);
    unit.commit().await.unwrap();
    assert_eq!(store.head(s).await.unwrap().next_sequence, 2);
    assert_eq!(store.covers("account").await, Ok(covers(&[s, other])));
}

pub async fn a_unit_of_work_lists_its_pending_streams<S: LocalStore>(store: S) {
    store
        .append(main_stream("account", 2), 0, &[page(0, 1)])
        .await
        .unwrap();
    let mut unit = store.begin().await.unwrap();
    unit.append(main_stream("account", 1), 0, &[page(0, 2)])
        .await
        .unwrap();
    unit.append(main_stream("account", 3), 0, &[])
        .await
        .unwrap();
    assert_eq!(
        unit.covers("account").await,
        Ok(covers(&[
            main_stream("account", 1),
            main_stream("account", 2)
        ])),
        "its own append, the store's, and no empty one, in order"
    );
}

pub async fn a_unit_of_work_finds_its_pending_commands_and_triggers<S: LocalStore>(store: S) {
    let s = main_stream("account", 1);
    let pm = main_stream("shipping", 1);
    let trigger = event_ref(s, 0);
    let mut unit = store.begin().await.unwrap();
    unit.append(s, 0, &[page(0, 1)]).await.unwrap();
    unit.append(pm, 0, &[triggered(0, &trigger)]).await.unwrap();
    assert_eq!(unit.find_command(s, command(1)).await, Ok(vec![page(0, 1)]));
    assert_eq!(
        unit.find_triggered(pm, &trigger).await,
        Ok(vec![triggered(0, &trigger)])
    );
    assert_eq!(
        store.find_command(s, command(1)).await,
        Ok(vec![]),
        "not outside the unit yet"
    );
}

/// Spec 5.6: a reactor's output lands with its source checkpoint, or
/// neither does. One stream plus a position is a unit at its narrowest.
pub async fn a_unit_of_work_puts_positions_with_its_appends<S: LocalStore>(store: S) {
    let out = main_stream("ledger", 1);
    let k = key("order-ledger", main_stream("order", 1));
    let mut unit = store.begin().await.unwrap();
    unit.append(out, 0, &[page(0, 1)]).await.unwrap();
    unit.put_position(k, 1).await.unwrap();
    assert_eq!(unit.position(k).await, Ok(1), "its own put");
    assert_eq!(store.position(k).await, Ok(0), "not outside the unit yet");
    unit.commit().await.unwrap();
    assert_eq!(store.position(k).await, Ok(1));
    assert_eq!(store.head(out).await.unwrap().next_sequence, 1);
    {
        let mut unit = store.begin().await.unwrap();
        unit.append(out, 1, &[page(1, 2)]).await.unwrap();
        unit.put_position(k, 2).await.unwrap();
    }
    assert_eq!(
        store.position(k).await,
        Ok(1),
        "dropped: the checkpoint too"
    );
    assert_eq!(store.head(out).await.unwrap().next_sequence, 1);
}

// ----------------------------------------------------- pair (two handles)

/// The commit position is the store's, not the handle's.
pub async fn the_commit_position_counts_every_handles_commits<S: LocalStore>((a, b): (S, S)) {
    let empty = a.commit_position().await.unwrap();
    b.append(main_stream("account", 1), 0, &[page(0, 1)])
        .await
        .unwrap();
    let created = a.commit_position().await.unwrap();
    assert!(
        created > empty,
        "another handle's append: {empty}, then {created}"
    );
    let mut unit = b.begin().await.unwrap();
    unit.append(main_stream("account", 1), 1, &[page(1, 2)])
        .await
        .unwrap();
    unit.commit().await.unwrap();
    let grown = a.commit_position().await.unwrap();
    assert!(
        grown > created,
        "another handle's unit: {created}, then {grown}"
    );
}

/// A unit that read a stream, then lost the race to another handle's
/// append, is refused as a conflict, at its append or at its commit, and
/// nothing it wrote lands: not its other streams, not its positions.
pub async fn a_unit_that_lost_a_race_lands_nothing<S: LocalStore>((a, b): (S, S)) {
    let s = main_stream("account", 1);
    let other = main_stream("account", 2);
    let k = key("h", main_stream("order", 1));
    let mut unit = b.begin().await.unwrap();
    assert_eq!(unit.head(s).await.unwrap().next_sequence, 0);
    unit.append(other, 0, &[page(0, 2)]).await.unwrap();
    unit.put_position(k, 1).await.unwrap();
    a.append(s, 0, &[page(0, 1)]).await.unwrap();
    let refused = match unit.append(s, 0, &[page(0, 2)]).await {
        Err(e) => Err(e),
        Ok(_) => unit.commit().await,
    };
    assert!(
        matches!(refused, Err(StoreError::Conflict { .. })),
        "refused as a conflict: {refused:?}"
    );
    assert_eq!(a.read(s, 0, None).await.unwrap().pages, [page(0, 1)]);
    assert_eq!(
        a.head(other).await.unwrap().next_sequence,
        0,
        "its other stream"
    );
    assert_eq!(a.position(k).await, Ok(0), "its position");
}

// ------------------------------------------------------------ purge (opt-in)

/// Whether `stream` reads as never written.
async fn assert_gone<S: LocalStore>(store: &S, stream: StreamRef<'_>, what: &str) {
    let slice = store.read(stream, 0, None).await.unwrap();
    assert_eq!(
        (slice.next_sequence, slice.pages),
        (0, vec![]),
        "{what}: read"
    );
    assert_eq!(
        store.read_snapshot(stream).await,
        Ok(None),
        "{what}: snapshot"
    );
    assert_eq!(
        store.find_command(stream, command(1)).await,
        Ok(vec![]),
        "{what}: command ids"
    );
    let listed = store.covers(stream.domain).await.unwrap();
    assert!(
        !listed.contains(&stream.to_cover()),
        "{what}: covers {listed:?}"
    );
}

pub async fn a_purge_deletes_a_streams_events_snapshot_and_command_ids<S>(store: S)
where
    S: LocalStore + LocalPurge,
{
    let purged = main_stream("account", 1);
    let kept = main_stream("account", 2);
    for s in [purged, kept] {
        store.append(s, 0, &[page(0, 1), page(1, 2)]).await.unwrap();
        store.write_snapshot(s, &snapshot(1, "v1")).await.unwrap();
    }
    assert_eq!(store.purge(purged).await, Ok(2), "its two events");
    assert_gone(&store, purged, "purged").await;
    assert_eq!(store.covers("account").await, Ok(covers(&[kept])));
    assert_eq!(
        store.read(kept, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 2)],
        "another stream untouched"
    );
    assert_eq!(store.read_snapshot(kept).await, Ok(Some(snapshot(1, "v1"))));
    assert_eq!(store.purge(purged).await, Ok(0), "nothing left to purge");
    assert_eq!(
        store.purge(main_stream("account", 3)).await,
        Ok(0),
        "no stream"
    );
}

/// A purged stream starts again at 0; a handler's position on it would
/// skip the new events, so it goes too.
pub async fn a_purge_deletes_the_streams_positions<S>(store: S)
where
    S: LocalStore + LocalPurge,
{
    let s = main_stream("account", 1);
    let kept = main_stream("account", 2);
    store.append(s, 0, &[page(0, 1)]).await.unwrap();
    store.put_position(key("a", s), 1).await.unwrap();
    store.put_position(key("b", s), 1).await.unwrap();
    store.put_position(key("a", kept), 4).await.unwrap();
    store.purge(s).await.unwrap();
    assert_eq!(store.position(key("a", s)).await, Ok(0));
    assert_eq!(store.position(key("b", s)).await, Ok(0));
    assert_eq!(
        store.position(key("a", kept)).await,
        Ok(4),
        "another stream's kept"
    );
}

pub async fn a_purge_deletes_a_snapshot_with_no_events<S>(store: S)
where
    S: LocalStore + LocalPurge,
{
    let s = main_stream("account", 1);
    store.write_snapshot(s, &snapshot(4, "v1")).await.unwrap();
    assert_eq!(store.purge(s).await, Ok(0));
    assert_eq!(store.read_snapshot(s).await, Ok(None));
}

pub async fn a_purged_stream_starts_again_from_nothing<S>(store: S)
where
    S: LocalStore + LocalPurge,
{
    let s = main_stream("account", 1);
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    store.purge(s).await.unwrap();
    assert_eq!(
        store.append(s, 2, &[page(2, 2)]).await,
        Err(conflict(s, 2, 0)),
        "a stale writer that raced the purge"
    );
    assert_gone(&store, s, "after the refused append").await;
    assert_eq!(store.append(s, 0, &[page(0, 3)]).await, Ok(1));
    let slice = store.read(s, 0, None).await.unwrap();
    assert_eq!(slice.pages, [page(0, 3)]);
    assert_eq!(slice.last_recorded_at, Some(at(0)));
    assert_eq!(
        store.find_command(s, command(1)).await,
        Ok(vec![]),
        "old ids forgotten"
    );
}

pub async fn a_purge_in_a_unit_of_work_lands_at_commit_or_not_at_all<S>(store: S)
where
    S: LocalStore + LocalPurge,
    for<'s> S::Unit<'s>: LocalUnitPurge,
{
    let s = main_stream("account", 1);
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    store.write_snapshot(s, &snapshot(1, "v1")).await.unwrap();
    {
        let mut unit = store.begin().await.unwrap();
        assert_eq!(unit.purge(s).await, Ok(2));
        assert_eq!(
            unit.head(s).await.unwrap().next_sequence,
            0,
            "inside the unit"
        );
        assert_eq!(unit.read_snapshot(s).await, Ok(None), "inside the unit");
        assert_eq!(unit.find_command(s, command(1)).await, Ok(vec![]));
        assert_eq!(unit.covers("account").await, Ok(vec![]));
    }
    assert_eq!(
        store.read(s, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 1)],
        "dropped: nothing deleted"
    );
    assert_eq!(store.read_snapshot(s).await, Ok(Some(snapshot(1, "v1"))));
    let mut unit = store.begin().await.unwrap();
    unit.purge(s).await.unwrap();
    unit.commit().await.unwrap();
    assert_gone(&store, s, "committed").await;
}

pub async fn a_unit_of_work_purges_its_own_appends_and_appends_after<S>(store: S)
where
    S: LocalStore + LocalPurge,
    for<'s> S::Unit<'s>: LocalUnitPurge,
{
    let s = main_stream("account", 1);
    let other = main_stream("account", 2);
    store.append(s, 0, &[page(0, 1)]).await.unwrap();
    store.write_snapshot(s, &snapshot(0, "v1")).await.unwrap();
    let mut unit = store.begin().await.unwrap();
    unit.append(s, 1, &[page(1, 2)]).await.unwrap();
    unit.append(other, 0, &[page(0, 2)]).await.unwrap();
    assert_eq!(unit.purge(s).await, Ok(2), "stored and pending");
    assert_eq!(unit.purge(other).await, Ok(1), "only pending");
    assert_eq!(unit.covers("account").await, Ok(vec![]));
    assert_eq!(
        unit.append(s, 1, &[page(1, 3)]).await,
        Err(conflict(s, 1, 0))
    );
    assert_eq!(unit.append(s, 0, &[page(0, 3)]).await, Ok(1));
    assert_eq!(unit.read(s, 0, None).await.unwrap().pages, [page(0, 3)]);
    assert_eq!(unit.read_snapshot(s).await, Ok(None));
    unit.commit().await.unwrap();
    let slice = store.read(s, 0, None).await.unwrap();
    assert_eq!((slice.next_sequence, slice.pages), (1, vec![page(0, 3)]));
    assert_eq!(store.read_snapshot(s).await, Ok(None));
    assert_eq!(store.find_command(s, command(2)).await, Ok(vec![]));
    assert_eq!(store.head(other).await.unwrap().next_sequence, 0);
    assert_eq!(store.covers("account").await, Ok(covers(&[s])));
}

pub async fn a_purge_never_lowers_the_commit_position<S>(store: S)
where
    S: LocalStore + LocalPurge,
    for<'s> S::Unit<'s>: LocalUnitPurge,
{
    let purged = main_stream("account", 1);
    let kept = main_stream("account", 2);
    store
        .append(purged, 0, &[page(0, 1), page(1, 1)])
        .await
        .unwrap();
    store.append(kept, 0, &[page(0, 2)]).await.unwrap();
    let before = store.commit_position().await.unwrap();
    store.purge(purged).await.unwrap();
    let after = store.commit_position().await.unwrap();
    assert!(after >= before, "a purge: {before}, then {after}");
    let mut unit = store.begin().await.unwrap();
    unit.purge(kept).await.unwrap();
    unit.commit().await.unwrap();
    let emptied = store.commit_position().await.unwrap();
    assert!(
        emptied >= after,
        "a purge in a unit: {after}, then {emptied}"
    );
    store.append(kept, 0, &[page(0, 3)]).await.unwrap();
    let again = store.commit_position().await.unwrap();
    assert!(
        again > before,
        "rises past every position before: {before}, then {again}"
    );
}

// --------------------------------------------------------- editions (opt-in)

fn create(name: &str) -> CreateEditionRequest {
    CreateEditionRequest {
        name: name.to_string(),
        diverge_at: None,
        store: String::new(),
    }
}

pub async fn an_edition_is_created_once_and_recorded<S>(store: S)
where
    S: LocalStore + LocalEditions,
{
    assert_eq!(store.edition("what-if").await, Ok(None));
    let made = store
        .create_edition(&create("what-if"), at(10))
        .await
        .unwrap();
    assert_eq!(made.name, "what-if");
    assert_eq!(
        made.diverged_at,
        Some(at(10)),
        "unset: the create's instant"
    );
    assert_eq!(
        made.store, DEFAULT_EDITION_STORE,
        "unnamed: the default store"
    );
    assert_eq!(made.created_at, Some(at(10)));
    assert_eq!(store.edition("what-if").await, Ok(Some(made)));
    let earlier = CreateEditionRequest {
        diverge_at: Some(at(3)),
        ..create("then")
    };
    let then = store.create_edition(&earlier, at(10)).await.unwrap();
    assert_eq!(then.diverged_at, Some(at(3)), "the requested point");
    assert_eq!(
        store.create_edition(&create("what-if"), at(11)).await,
        Err(StoreError::EditionExists {
            name: "what-if".to_string()
        })
    );
}

pub async fn an_edition_create_refuses_a_bad_request<S>(store: S)
where
    S: LocalStore + LocalEditions,
{
    assert_eq!(
        store.create_edition(&create(""), at(10)).await,
        Err(StoreError::EditionNameRequired),
        "main is unnamed"
    );
    let future = CreateEditionRequest {
        diverge_at: Some(at(11)),
        ..create("later")
    };
    assert_eq!(
        store.create_edition(&future, at(10)).await,
        Err(StoreError::EditionDivergesInTheFuture {
            name: "later".to_string()
        })
    );
    let elsewhere = CreateEditionRequest {
        store: "nowhere".to_string(),
        ..create("far")
    };
    assert_eq!(
        store.create_edition(&elsewhere, at(10)).await,
        Err(StoreError::EditionStoreUnknown {
            name: "far".to_string(),
            store: "nowhere".to_string()
        })
    );
    for name in ["", "later", "far"] {
        assert_eq!(store.edition(name).await, Ok(None), "{name:?} not recorded");
    }
}

pub async fn deleting_an_edition_removes_it_and_its_streams_never_mains<S>(store: S)
where
    S: LocalStore + LocalEditions,
{
    store
        .create_edition(&create("what-if"), at(10))
        .await
        .unwrap();
    store
        .create_edition(&create("other"), at(10))
        .await
        .unwrap();
    let main = main_stream("account", 1);
    let gone = [
        edition_stream("account", 1, "what-if"),
        edition_stream("ledger", 1, "what-if"),
    ];
    let kept = edition_stream("account", 1, "other");
    for s in [main, gone[0], gone[1], kept] {
        store.append(s, 0, &[page(0, 1)]).await.unwrap();
        store.write_snapshot(s, &snapshot(0, "v1")).await.unwrap();
        store.put_position(key("h", s), 1).await.unwrap();
    }
    store.delete_edition("what-if").await.unwrap();
    assert_eq!(store.edition("what-if").await, Ok(None));
    for s in gone {
        assert_eq!(
            store.head(s).await.unwrap().next_sequence,
            0,
            "{s:?} events"
        );
        assert_eq!(store.read_snapshot(s).await, Ok(None), "{s:?} snapshot");
        assert_eq!(store.position(key("h", s)).await, Ok(0), "{s:?} position");
    }
    for s in [main, kept] {
        assert_eq!(store.head(s).await.unwrap().next_sequence, 1, "{s:?} kept");
        assert_eq!(store.read_snapshot(s).await, Ok(Some(snapshot(0, "v1"))));
        assert_eq!(store.position(key("h", s)).await, Ok(1));
    }
    assert_eq!(store.covers("account").await, Ok(covers(&[main, kept])));
}

pub async fn deleting_an_edition_refuses_an_empty_or_unknown_name<S>(store: S)
where
    S: LocalStore + LocalEditions,
{
    assert_eq!(
        store.delete_edition("").await,
        Err(StoreError::EditionNameRequired)
    );
    assert_eq!(
        store.delete_edition("never").await,
        Err(StoreError::EditionNotFound {
            name: "never".to_string()
        })
    );
    store.create_edition(&create("once"), at(1)).await.unwrap();
    store.delete_edition("once").await.unwrap();
    assert_eq!(
        store.delete_edition("once").await,
        Err(StoreError::EditionNotFound {
            name: "once".to_string()
        }),
        "already deleted"
    );
}

// ------------------------------------------------------------------- macro

/// One test per check of a section, each on a fresh store from `$fresh`
/// (an expression evaluated once per test, inside the test's `async fn`,
/// so it may `.await`), under the caller's test attribute (its runtime):
///
/// - `store_contract!(#[tokio::test], $fresh)`: the base section, every
///   store's;
/// - `store_contract!(purge, #[tokio::test], $fresh)`: for a store that
///   purges (and whose unit does);
/// - `store_contract!(editions, #[tokio::test], $fresh)`: for a store that
///   keeps the edition registry;
/// - `store_contract!(pair, #[tokio::test], $pair)`: `$pair` is two handles
///   `(a, b)` on one fresh, empty store.
///
/// Each section's tests are named after its checks, so a backend invoking
/// several sections does so in one module per section.
#[macro_export]
macro_rules! store_contract {
    (purge, #[$test:meta], $fresh:expr) => {
        $crate::store_contract!(@each #[$test], $fresh;
            a_purge_deletes_a_streams_events_snapshot_and_command_ids,
            a_purge_deletes_the_streams_positions,
            a_purge_deletes_a_snapshot_with_no_events,
            a_purged_stream_starts_again_from_nothing,
            a_purge_in_a_unit_of_work_lands_at_commit_or_not_at_all,
            a_unit_of_work_purges_its_own_appends_and_appends_after,
            a_purge_never_lowers_the_commit_position,
        );
    };
    (editions, #[$test:meta], $fresh:expr) => {
        $crate::store_contract!(@each #[$test], $fresh;
            an_edition_is_created_once_and_recorded,
            an_edition_create_refuses_a_bad_request,
            deleting_an_edition_removes_it_and_its_streams_never_mains,
            deleting_an_edition_refuses_an_empty_or_unknown_name,
        );
    };
    (pair, #[$test:meta], $pair:expr) => {
        $crate::store_contract!(@each #[$test], $pair;
            the_commit_position_counts_every_handles_commits,
            a_unit_that_lost_a_race_lands_nothing,
        );
    };
    (#[$test:meta], $fresh:expr) => {
        $crate::store_contract!(@each #[$test], $fresh;
            append_checks_the_expected_length_and_continuity,
            append_refuses_a_stale_first_sequence,
            an_empty_append_checks_and_creates_nothing,
            read_is_bounded_by_from_and_to,
            a_read_of_no_such_stream_is_empty_at_zero,
            a_read_past_the_end_is_empty_but_knows_the_end,
            head_is_the_next_sequence_and_the_last_recorded_at,
            a_stream_is_domain_edition_and_root,
            covers_orders_main_first_then_by_edition_and_root,
            find_command_finds_a_commands_events_on_its_stream,
            find_triggered_finds_a_process_managers_events_by_trigger,
            a_store_keeps_the_newest_snapshot_per_stream,
            a_position_is_zero_until_put_then_the_last_put,
            positions_are_per_handler_and_per_stream,
            the_commit_position_rises_with_every_commit,
            a_unit_of_work_lands_at_commit_or_not_at_all,
            an_aborted_unit_of_work_lands_nothing,
            a_unit_of_work_checks_and_reads_its_pending_appends,
            a_unit_of_work_lists_its_pending_streams,
            a_unit_of_work_finds_its_pending_commands_and_triggers,
            a_unit_of_work_puts_positions_with_its_appends,
        );
    };
    (@each #[$test:meta], $fresh:expr; $($check:ident),* $(,)?) => {
        $(
            #[$test]
            async fn $check() {
                $crate::contract::$check($fresh).await;
            }
        )*
    };
}
