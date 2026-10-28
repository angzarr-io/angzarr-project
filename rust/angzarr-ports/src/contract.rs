//! The conformance suite: what every backend must do, as checks a backend's
//! own tests run, one test per check. annals' store contract moved here and
//! reshaped to the shared ports, joined by core's cases and the opt-in
//! capabilities' sections.
//!
//! **Shape.**
//! - Each check is a `pub async fn` taking a fresh, EMPTY store (or, in a
//!   pair section, two handles `(a, b)` on one fresh store) and panicking,
//!   naming what failed. Pages are opaque to a store: the checks write their
//!   own and never decode a payload.
//! - The checks are generic over the one trait set, so they run on any
//!   backend, `Arc<dyn DynStore>` included, under the caller's runtime.
//! - [`store_contract!`](crate::store_contract) stamps one test per check of
//!   a section.
//! - Every check is proven able to fail: `tests/meta.rs` runs it on a store
//!   broken on purpose and requires it to catch the bug.
//!
//! **Sections** (a backend runs those whose capabilities it has):
//!
//! | Section | Needs | Takes |
//! |---|---|---|
//! | base | [`Store`] | a store |
//! | `pair` | [`Store`] | two handles |
//! | `purge` | [`Purge`], [`UnitPurge`] on its unit | a store |
//! | `editions` | [`Editions`] | a store |
//! | `read` | [`ReadStore`] | two handles |
//! | `read_purge` | [`ReadStore`], [`Purge`] | two handles |
//! | `read_editions` | [`ReadStore`], [`Editions`] | a store |
//! | `watch` | [`Watch`] | a store |
//! | `watch_pair` | [`Watch`] | two handles |
//! | `until_time` | [`ReadUntilTime`] | a store |
//! | `correlation` | [`ReadByCorrelation`] | a store |
//! | `list_streams` | [`ListStreams`] | a store |
//! | `outbox` | [`Outbox`], [`UnitOutbox`] on its unit | a store |

use std::future::Future;

use angzarr_proto::uuid::Uuid;
use angzarr_proto::v1::event_meta::Causation;
use angzarr_proto::v1::{
    Cover, CreateEditionRequest, EventBook, EventMeta, EventPage, EventRef, Snapshot,
};
use prost_types::{Any, Timestamp};

use crate::error::StoreError;
use crate::store::{
    Editions, ListStreams, Outbox, OutboxEntry, Purge, ReadByCorrelation, ReadStore, ReadUnit,
    ReadUntilTime, Store, Unit, UnitOutbox, UnitPurge, Watch, DEFAULT_EDITION_STORE,
};
use crate::stream::{PositionKey, StreamRef};

// ------------------------------------------------------------- the fixtures

/// The instant `page(sequence, _)` records.
pub fn at(sequence: u64) -> Timestamp {
    Timestamp {
        seconds: sequence as i64,
        nanos: 0,
    }
}

/// Command `n`'s id (and correlation `n`'s).
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
    stamped(sequence, Causation::CommandId(command(n).into()), 0xC0)
}

/// The event at `sequence`, produced by command `n`, in correlation `c`.
pub fn correlated(sequence: u64, n: u8, c: u8) -> EventPage {
    stamped(sequence, Causation::CommandId(command(n).into()), c)
}

/// A process manager's event at `sequence`, written in reaction to
/// `trigger`: no command (13.2).
pub fn triggered(sequence: u64, trigger: &EventRef) -> EventPage {
    stamped(sequence, Causation::TriggeringEvent(trigger.clone()), 0xC0)
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

/// Outbox entry `n` from `origin`, its message `body`.
pub fn entry(n: u8, origin: &str, body: u8) -> OutboxEntry {
    OutboxEntry {
        id: command(n),
        origin: origin.to_string(),
        message: Any {
            type_url: "/angzarr.contract.v1.Message".to_string(),
            value: vec![body; 3],
        },
    }
}

fn stamped(sequence: u64, causation: Causation, correlation: u8) -> EventPage {
    EventPage {
        payload: Some(Any {
            type_url: "/angzarr.contract.v1.Page".to_string(),
            value: sequence.to_be_bytes().to_vec(),
        }),
        meta: Some(EventMeta {
            causation: Some(causation),
            correlation_id: Some(command(correlation).into()),
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

fn create(name: &str) -> CreateEditionRequest {
    CreateEditionRequest {
        name: name.to_string(),
        diverge_at: None,
        store: String::new(),
    }
}

/// `future`'s output, or a panic naming `what` if it has not finished
/// within a few seconds: how the suite tells "waits" from "answers" with no
/// runtime of its own. (On `wasm32`, which has no threads, it just awaits.)
pub async fn within<F: Future>(what: &str, future: F) -> F::Output {
    #[cfg(not(target_arch = "wasm32"))]
    {
        deadline::Deadline::new(what, std::time::Duration::from_secs(5), future).await
    }
    #[cfg(target_arch = "wasm32")]
    {
        let _ = what;
        future.await
    }
}

#[cfg(not(target_arch = "wasm32"))]
mod deadline {
    use std::future::Future;
    use std::pin::Pin;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::task::{Context, Poll};
    use std::time::Duration;

    /// A future that panics if `inner` is still pending once `limit` has
    /// passed, woken by a timer thread.
    pub struct Deadline<'w, F> {
        what: &'w str,
        limit: Duration,
        inner: Pin<Box<F>>,
        expired: Option<Arc<AtomicBool>>,
    }

    impl<'w, F> Deadline<'w, F> {
        pub fn new(what: &'w str, limit: Duration, inner: F) -> Self {
            Deadline {
                what,
                limit,
                inner: Box::pin(inner),
                expired: None,
            }
        }
    }

    impl<F: Future> Future for Deadline<'_, F> {
        type Output = F::Output;

        fn poll(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<F::Output> {
            if let Poll::Ready(out) = self.inner.as_mut().poll(cx) {
                return Poll::Ready(out);
            }
            match &self.expired {
                Some(flag) if flag.load(Ordering::SeqCst) => {
                    panic!(
                        "{} did not finish within {:?}: it waits",
                        self.what, self.limit
                    )
                }
                Some(_) => {}
                None => {
                    let flag = Arc::new(AtomicBool::new(false));
                    let (set, waker, limit) = (flag.clone(), cx.waker().clone(), self.limit);
                    std::thread::spawn(move || {
                        std::thread::sleep(limit);
                        set.store(true, Ordering::SeqCst);
                        waker.wake();
                    });
                    self.expired = Some(flag);
                }
            }
            Poll::Pending
        }
    }
}

// --------------------------------------------------------- base: appends

pub async fn append_checks_the_expected_length_and_continuity<S: Store>(store: S) {
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
    assert_eq!(
        store.read(s, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 1), page(2, 2)],
        "nothing refused landed, and every page as written"
    );
}

/// Core's rule, "the first page must be the head", is `expected =
/// pages[0].sequence`: a writer whose stamped pages are stale is refused,
/// as a conflict, not a gap.
pub async fn append_refuses_a_stale_first_sequence<S: Store>(store: S) {
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

pub async fn an_empty_append_checks_and_creates_nothing<S: Store>(store: S) {
    let s = main_stream("account", 1);
    let before = store.commit_position().await.unwrap();
    assert_eq!(store.append(s, 0, &[]).await, Ok(0));
    assert_eq!(store.covers("account").await, Ok(vec![]), "no stream made");
    assert_eq!(store.append(s, 1, &[]).await, Err(conflict(s, 1, 0)));
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

pub async fn read_is_bounded_by_from_and_to<S: Store>(store: S) {
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

/// "No such stream" is an empty slice at 0.
pub async fn a_read_of_no_such_stream_is_empty_at_zero<S: Store>(store: S) {
    let slice = store
        .read(main_stream("account", 1), 0, None)
        .await
        .unwrap();
    assert_eq!(slice.pages, []);
    assert_eq!(slice.next_sequence, 0);
    assert_eq!(slice.last_recorded_at, None);
}

pub async fn a_read_past_the_end_is_empty_but_knows_the_end<S: Store>(store: S) {
    let s = main_stream("account", 1);
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    let slice = store.read(s, 7, None).await.unwrap();
    assert_eq!(slice.pages, []);
    assert_eq!(slice.next_sequence, 2);
    assert_eq!(slice.last_recorded_at, Some(at(1)));
}

pub async fn head_is_the_next_sequence_and_the_last_recorded_at<S: Store>(store: S) {
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

pub async fn a_stream_is_domain_edition_and_root<S: Store>(store: S) {
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

pub async fn covers_orders_main_first_then_by_edition_and_root<S: Store>(store: S) {
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

pub async fn find_command_finds_a_commands_events_on_its_stream<S: Store>(store: S) {
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

pub async fn find_triggered_finds_a_process_managers_events_by_trigger<S: Store>(store: S) {
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

/// The store keeps what was written last and judges nothing.
pub async fn a_store_keeps_the_newest_snapshot_per_stream<S: Store>(store: S) {
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

pub async fn a_position_is_zero_until_put_then_the_last_put<S: Store>(store: S) {
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

pub async fn positions_are_per_handler_and_per_stream<S: Store>(store: S) {
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

pub async fn the_commit_position_rises_with_every_commit<S: Store>(store: S) {
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

pub async fn a_unit_of_work_lands_at_commit_or_not_at_all<S: Store>(store: S) {
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

pub async fn an_aborted_unit_of_work_lands_nothing<S: Store>(store: S) {
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

pub async fn a_unit_of_work_checks_and_reads_its_pending_appends<S: Store>(store: S) {
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

pub async fn a_unit_of_work_lists_its_pending_streams<S: Store>(store: S) {
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

pub async fn a_unit_of_work_finds_its_pending_commands_and_triggers<S: Store>(store: S) {
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
/// neither does.
pub async fn a_unit_of_work_puts_positions_with_its_appends<S: Store>(store: S) {
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

/// Ruling 8: two units may be open on one handle. A backend that cannot
/// serve the second refuses it as [`StoreError::UnitBusy`] at once; it
/// never waits, since the unit it would wait on may be the caller's own.
/// Once the first has ended, a begin serves.
pub async fn a_second_begin_on_a_handle_serves_or_refuses_never_waits<S: Store>(store: S) {
    let (s, other) = (main_stream("account", 1), main_stream("account", 2));
    let mut first = store.begin().await.unwrap();
    first.append(s, 0, &[page(0, 1)]).await.unwrap();
    match within("a second begin while a unit is open", store.begin()).await {
        Ok(mut second) => {
            second.append(other, 0, &[page(0, 2)]).await.unwrap();
            second.commit().await.unwrap();
            assert_eq!(store.head(other).await.unwrap().next_sequence, 1);
        }
        Err(StoreError::UnitBusy) => {}
        Err(refused) => panic!("a busy handle refuses as UnitBusy, not {refused:?}"),
    }
    first.commit().await.unwrap();
    assert_eq!(store.head(s).await.unwrap().next_sequence, 1);
    let again = within("a begin after the open unit ended", store.begin()).await;
    assert!(
        again.is_ok(),
        "serves once no unit is open: {:?}",
        again.err()
    );
}

// ----------------------------------------------------- pair (two handles)

/// The commit position is the store's, not the handle's.
pub async fn the_commit_position_counts_every_handles_commits<S: Store>((a, b): (S, S)) {
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
/// nothing it wrote lands.
pub async fn a_unit_that_lost_a_race_lands_nothing<S: Store>((a, b): (S, S)) {
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

async fn assert_gone<S: Store>(store: &S, stream: StreamRef<'_>, what: &str) {
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
    S: Store + Purge,
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

/// A purged stream starts again at 0; a position on it would skip the new
/// events, so it goes too (ruling 10).
pub async fn a_purge_deletes_the_streams_positions<S>(store: S)
where
    S: Store + Purge,
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
    S: Store + Purge,
{
    let s = main_stream("account", 1);
    store.write_snapshot(s, &snapshot(4, "v1")).await.unwrap();
    assert_eq!(store.purge(s).await, Ok(0));
    assert_eq!(store.read_snapshot(s).await, Ok(None));
}

pub async fn a_purged_stream_starts_again_from_nothing<S>(store: S)
where
    S: Store + Purge,
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
    S: Store + Purge,
    for<'s> S::Unit<'s>: UnitPurge,
{
    let s = main_stream("account", 1);
    store.append(s, 0, &[page(0, 1), page(1, 1)]).await.unwrap();
    store.write_snapshot(s, &snapshot(1, "v1")).await.unwrap();
    {
        let mut unit = store.begin().await.unwrap();
        assert_eq!(UnitPurge::purge(&mut unit, s).await, Ok(2));
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
    UnitPurge::purge(&mut unit, s).await.unwrap();
    unit.commit().await.unwrap();
    assert_gone(&store, s, "committed").await;
}

pub async fn a_unit_of_work_purges_its_own_appends_and_appends_after<S>(store: S)
where
    S: Store + Purge,
    for<'s> S::Unit<'s>: UnitPurge,
{
    let s = main_stream("account", 1);
    let other = main_stream("account", 2);
    store.append(s, 0, &[page(0, 1)]).await.unwrap();
    store.write_snapshot(s, &snapshot(0, "v1")).await.unwrap();
    let mut unit = store.begin().await.unwrap();
    unit.append(s, 1, &[page(1, 2)]).await.unwrap();
    unit.append(other, 0, &[page(0, 2)]).await.unwrap();
    assert_eq!(
        UnitPurge::purge(&mut unit, s).await,
        Ok(2),
        "stored and pending"
    );
    assert_eq!(
        UnitPurge::purge(&mut unit, other).await,
        Ok(1),
        "only pending"
    );
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
    S: Store + Purge,
    for<'s> S::Unit<'s>: UnitPurge,
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
    UnitPurge::purge(&mut unit, kept).await.unwrap();
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

pub async fn an_edition_is_created_once_and_recorded<S>(store: S)
where
    S: Store + Editions,
{
    assert_eq!(store.edition("what-if").await, Ok(None));
    store
        .append(main_stream("account", 1), 0, &[page(0, 1)])
        .await
        .unwrap();
    let head = store.commit_position().await.unwrap();
    let made = store
        .create_edition(&create("what-if"), at(10))
        .await
        .unwrap();
    assert_eq!(made.edition.name, "what-if");
    assert_eq!(
        made.edition.diverged_at,
        Some(at(10)),
        "unset: the create's instant"
    );
    assert_eq!(
        made.edition.store, DEFAULT_EDITION_STORE,
        "unnamed: the default store"
    );
    assert_eq!(made.edition.created_at, Some(at(10)));
    assert_eq!(made.divergence, head, "the commit position at the create");
    assert_eq!(store.edition("what-if").await, Ok(Some(made)));
    let earlier = CreateEditionRequest {
        diverge_at: Some(at(3)),
        ..create("then")
    };
    let then = store.create_edition(&earlier, at(10)).await.unwrap();
    assert_eq!(
        then.edition.diverged_at,
        Some(at(3)),
        "the requested instant, recorded"
    );
    assert_eq!(
        store.create_edition(&create("what-if"), at(11)).await,
        Err(StoreError::EditionExists {
            name: "what-if".to_string()
        })
    );
}

pub async fn an_edition_create_refuses_a_bad_request<S>(store: S)
where
    S: Store + Editions,
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

/// EA-3, ruling 11: the STORE falls through. A created edition's stream is
/// main's events committed below the divergence, then its own, numbered on
/// from them; main's later events are not its.
pub async fn an_edition_reads_mains_events_below_its_divergence_then_its_own<S>(store: S)
where
    S: Store + Editions,
{
    let main = main_stream("account", 1);
    let born_after = main_stream("account", 2);
    let fork = edition_stream("account", 1, "what-if");
    store
        .append(main, 0, &[page(0, 1), page(1, 1)])
        .await
        .unwrap();
    store
        .create_edition(&create("what-if"), at(10))
        .await
        .unwrap();
    store.append(main, 2, &[page(2, 2)]).await.unwrap();
    store.append(born_after, 0, &[page(0, 3)]).await.unwrap();

    let history = store.read(fork, 0, None).await.unwrap();
    assert_eq!(
        history.pages,
        [page(0, 1), page(1, 1)],
        "main's, below the divergence"
    );
    assert_eq!(history.next_sequence, 2);
    assert_eq!(history.last_recorded_at, Some(at(1)));
    assert_eq!(
        store
            .read(edition_stream("account", 2, "what-if"), 0, None)
            .await
            .unwrap()
            .pages,
        [],
        "a main stream begun after the divergence is not the edition's"
    );
    assert_eq!(
        store.covers("account").await,
        Ok(covers(&[main, born_after])),
        "listed only once it holds an event of its own"
    );
    assert_eq!(
        store.append(fork, 0, &[page(0, 5)]).await,
        Err(conflict(fork, 0, 2)),
        "its length counts main's history"
    );
    assert_eq!(store.append(fork, 2, &[page(2, 5)]).await, Ok(3));
    assert_eq!(
        store.read(fork, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 1), page(2, 5)]
    );
    assert_eq!(
        store.read(main, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 1), page(2, 2)],
        "main untouched"
    );
    assert_eq!(
        store.find_command(fork, command(1)).await,
        Ok(vec![page(0, 1), page(1, 1)]),
        "dedup sees its history"
    );
    assert_eq!(store.find_command(fork, command(2)).await, Ok(vec![]));
    assert_eq!(
        store.covers("account").await,
        Ok(covers(&[main, born_after, fork]))
    );
    let mut unit = store.begin().await.unwrap();
    assert_eq!(
        unit.read(fork, 0, Some(2)).await.unwrap().pages,
        [page(0, 1), page(1, 1)],
        "a unit reads the same history"
    );
    assert_eq!(unit.append(fork, 3, &[page(3, 6)]).await, Ok(4));
}

pub async fn deleting_an_edition_removes_it_and_its_streams_never_mains<S>(store: S)
where
    S: Store + Editions,
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
    S: Store + Editions,
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

// --------------------------------------------------- read units (opt-in)

pub async fn a_read_unit_sees_the_store_as_it_began<S>((reader, writer): (S, S))
where
    S: Store + ReadStore,
{
    let early = main_stream("account", 1);
    let late = main_stream("account", 2);
    writer.append(early, 0, &[page(0, 1)]).await.unwrap();
    let mut reads = reader.begin_read().await.unwrap();
    writer.append(early, 1, &[page(1, 2)]).await.unwrap();
    writer.append(late, 0, &[page(0, 2)]).await.unwrap();
    assert_eq!(
        reads.covers("account").await,
        Ok(covers(&[early])),
        "covers as the unit began"
    );
    writer.append(early, 2, &[page(2, 3)]).await.unwrap();
    let slice = reads.read(early, 0, None).await.unwrap();
    assert_eq!(slice.pages, [page(0, 1)], "pages as the unit began");
    assert_eq!(slice.next_sequence, 1);
    assert_eq!(slice.last_recorded_at, Some(at(0)));
    assert_eq!(
        reads.read(late, 0, None).await.unwrap().next_sequence,
        0,
        "begun after"
    );
    drop(reads);
    let mut later = reader.begin_read().await.unwrap();
    assert_eq!(later.covers("account").await, Ok(covers(&[early, late])));
    assert_eq!(later.read(early, 0, None).await.unwrap().next_sequence, 3);
}

/// EA-2: a read unit refuses a stream in an edition never created; such a
/// stream is neither read nor listed. Main is always read.
pub async fn a_read_unit_refuses_an_edition_never_created<S>((reader, writer): (S, S))
where
    S: Store + ReadStore,
{
    let main = main_stream("account", 1);
    let uncreated = edition_stream("account", 1, "what-if");
    writer.append(main, 0, &[page(0, 1)]).await.unwrap();
    writer.append(uncreated, 0, &[page(0, 2)]).await.unwrap();
    let mut reads = reader.begin_read().await.unwrap();
    assert_eq!(
        reads.read(uncreated, 0, None).await,
        Err(StoreError::UnknownEdition {
            stream: uncreated.to_cover()
        }),
        "a stream it holds, in an edition never created"
    );
    let misspelt = edition_stream("account", 2, "wat-if");
    assert_eq!(
        reads.read(misspelt, 0, None).await,
        Err(StoreError::UnknownEdition {
            stream: misspelt.to_cover()
        }),
        "no such stream either: refused, not empty"
    );
    assert_eq!(
        reads.covers("account").await,
        Ok(covers(&[main])),
        "not listed"
    );
    assert_eq!(reads.read(main, 0, None).await.unwrap().pages, [page(0, 1)]);
}

pub async fn a_read_unit_keeps_a_stream_purged_after_it_began<S>((reader, writer): (S, S))
where
    S: Store + ReadStore + Purge,
{
    let purged = main_stream("account", 1);
    let kept = main_stream("account", 2);
    writer
        .append(purged, 0, &[page(0, 1), page(1, 2)])
        .await
        .unwrap();
    writer.append(kept, 0, &[page(0, 3)]).await.unwrap();
    let mut reads = reader.begin_read().await.unwrap();
    let listed = reads.covers("account").await.unwrap();
    assert_eq!(listed, covers(&[purged, kept]));
    assert_eq!(writer.purge(purged).await, Ok(2));
    let slice = reads.read(purged, 0, None).await.unwrap();
    assert_eq!(slice.pages, [page(0, 1), page(1, 2)], "whole, as it began");
    assert_eq!(reads.covers("account").await, Ok(listed), "listed still");
    drop(reads);
    let mut later = reader.begin_read().await.unwrap();
    assert_eq!(later.covers("account").await, Ok(covers(&[kept])));
}

/// A read unit reads a created edition as the store does: through to main.
pub async fn a_read_unit_reads_a_created_edition_through_to_main<S>(store: S)
where
    S: Store + ReadStore + Editions,
{
    let main = main_stream("account", 1);
    let fork = edition_stream("account", 1, "what-if");
    store.append(main, 0, &[page(0, 1)]).await.unwrap();
    store
        .create_edition(&create("what-if"), at(10))
        .await
        .unwrap();
    store.append(fork, 1, &[page(1, 2)]).await.unwrap();
    store.append(main, 1, &[page(1, 3)]).await.unwrap();
    let mut reads = store.begin_read().await.unwrap();
    assert_eq!(
        reads.read(fork, 0, None).await.unwrap().pages,
        [page(0, 1), page(1, 2)]
    );
    assert_eq!(reads.covers("account").await, Ok(covers(&[main, fork])));
}

// --------------------------------------------------------- watch (opt-in)

/// `store`'s token now, asked twice: nothing committed in between.
async fn steady<S: Watch>(store: &S, what: &str) -> crate::store::ChangeToken {
    let token = store.change_token().await.unwrap();
    assert_eq!(
        store.change_token().await,
        Ok(token),
        "the token holds with nothing committed, after {what}"
    );
    token
}

pub async fn a_change_token_changes_when_its_own_store_commits<S>(store: S)
where
    S: Store + Watch,
{
    let first = main_stream("account", 1);
    let empty = steady(&store, "nothing").await;
    store.append(first, 0, &[page(0, 1)]).await.unwrap();
    let appended = steady(&store, "an append").await;
    assert_ne!(appended, empty, "an append");
    store.read(first, 0, None).await.unwrap();
    store.covers("account").await.unwrap();
    store.find_command(first, command(1)).await.unwrap();
    store.read_snapshot(first).await.unwrap();
    assert_eq!(
        store.change_token().await,
        Ok(appended),
        "reads commit nothing"
    );
    let mut unit = store.begin().await.unwrap();
    unit.append(first, 1, &[page(1, 2)]).await.unwrap();
    unit.commit().await.unwrap();
    let committed = steady(&store, "a unit").await;
    assert_ne!(committed, appended, "a unit committed");
}

pub async fn a_change_token_changes_when_another_handle_commits<S>((watcher, writer): (S, S))
where
    S: Store + Watch,
{
    let s = main_stream("account", 1);
    let empty = steady(&watcher, "nothing").await;
    writer.append(s, 0, &[page(0, 1)]).await.unwrap();
    let created = steady(&watcher, "a stream created").await;
    assert_ne!(created, empty, "another handle's append");
    let mut unit = writer.begin().await.unwrap();
    unit.append(s, 1, &[page(1, 2)]).await.unwrap();
    unit.commit().await.unwrap();
    let grown = steady(&watcher, "a unit").await;
    assert_ne!(grown, created, "another handle's unit");
}

// ------------------------------------------------------ core's reads (opt-in)

pub async fn read_until_time_is_the_prefix_recorded_by_then<S>(store: S)
where
    S: Store + ReadUntilTime,
{
    let s = main_stream("account", 1);
    let pages: Vec<_> = (0..5).map(|n| page(n, 1)).collect();
    store.append(s, 0, &pages).await.unwrap();
    let then = store.read_until_time(s, &at(2)).await.unwrap();
    assert_eq!(then.pages, pages[..3], "recorded at or before: inclusive");
    assert_eq!(then.next_sequence, 5, "the stream's end, as read");
    assert_eq!(store.read_until_time(s, &at(9)).await.unwrap().pages, pages);
    let before = Timestamp {
        seconds: -1,
        nanos: 0,
    };
    assert_eq!(store.read_until_time(s, &before).await.unwrap().pages, []);
    assert_eq!(
        store
            .read_until_time(main_stream("account", 2), &at(9))
            .await
            .unwrap()
            .next_sequence,
        0
    );
}

pub async fn read_by_correlation_gives_one_book_per_stream<S>(store: S)
where
    S: Store + ReadByCorrelation,
{
    let (a1, a2, l1) = (
        main_stream("account", 1),
        main_stream("account", 2),
        main_stream("ledger", 1),
    );
    let fork = edition_stream("account", 3, "what-if");
    store
        .append(
            a1,
            0,
            &[
                correlated(0, 1, 7),
                correlated(1, 2, 8),
                correlated(2, 3, 7),
            ],
        )
        .await
        .unwrap();
    store.append(a2, 0, &[correlated(0, 4, 8)]).await.unwrap();
    store.append(l1, 0, &[correlated(0, 5, 7)]).await.unwrap();
    store.append(fork, 0, &[correlated(0, 6, 7)]).await.unwrap();
    let book = |s: StreamRef<'_>, pages: Vec<EventPage>, next| EventBook {
        cover: Some(s.to_cover()),
        pages,
        next_sequence: next,
        ..EventBook::default()
    };
    assert_eq!(
        store.read_by_correlation(None, None, command(7)).await,
        Ok(vec![
            book(a1, vec![correlated(0, 1, 7), correlated(2, 3, 7)], 3),
            book(l1, vec![correlated(0, 5, 7)], 1),
        ]),
        "every domain, main only, its pages only, in stream order"
    );
    assert_eq!(
        store
            .read_by_correlation(Some("ledger"), None, command(7))
            .await,
        Ok(vec![book(l1, vec![correlated(0, 5, 7)], 1)])
    );
    assert_eq!(
        store
            .read_by_correlation(None, Some("what-if"), command(7))
            .await,
        Ok(vec![book(fork, vec![correlated(0, 6, 7)], 1)]),
        "the edition's timeline"
    );
    assert_eq!(
        store.read_by_correlation(None, None, command(9)).await,
        Ok(vec![])
    );
}

pub async fn list_streams_is_every_domains_covers_in_order<S>(store: S)
where
    S: Store + ListStreams,
{
    for s in [
        main_stream("ledger", 1),
        edition_stream("account", 1, "a"),
        main_stream("account", 2),
        main_stream("account", 1),
    ] {
        store.append(s, 0, &[page(0, 1)]).await.unwrap();
    }
    store.append(main_stream("order", 1), 0, &[]).await.unwrap();
    let mut every = store.covers("account").await.unwrap();
    every.extend(store.covers("ledger").await.unwrap());
    assert_eq!(store.list_streams().await, Ok(every.clone()));
    assert_eq!(
        every,
        covers(&[
            main_stream("account", 1),
            main_stream("account", 2),
            edition_stream("account", 1, "a"),
            main_stream("ledger", 1),
        ])
    );
}

// ------------------------------------------------------------ outbox (opt-in)

/// 5.6: the outbox lands with the unit's appends and checkpoint, or none
/// of them does. An entry is no event.
pub async fn an_outbox_entry_lands_with_its_unit_or_not_at_all<S>(store: S)
where
    S: Store + Outbox,
    for<'s> S::Unit<'s>: UnitOutbox,
{
    let own = main_stream("order-fulfilment", 1);
    let k = key("order-fulfilment", main_stream("order", 1));
    {
        let mut unit = store.begin().await.unwrap();
        unit.append(own, 0, &[page(0, 1)]).await.unwrap();
        unit.put_position(k, 1).await.unwrap();
        unit.put_outbox(&[entry(1, "order-fulfilment", 1)])
            .await
            .unwrap();
        assert_eq!(store.pending(10).await, Ok(vec![]), "not before commit");
    }
    assert_eq!(store.pending(10).await, Ok(vec![]), "dropped: no entry");
    assert_eq!(store.position(k).await, Ok(0));
    let before = store.commit_position().await.unwrap();
    let mut unit = store.begin().await.unwrap();
    unit.put_position(k, 1).await.unwrap();
    unit.put_outbox(&[
        entry(1, "order-fulfilment", 1),
        entry(2, "order-fulfilment", 2),
    ])
    .await
    .unwrap();
    unit.commit().await.unwrap();
    assert_eq!(
        store.pending(10).await,
        Ok(vec![
            entry(1, "order-fulfilment", 1),
            entry(2, "order-fulfilment", 2)
        ])
    );
    assert_eq!(store.position(k).await, Ok(1), "with its checkpoint");
    assert_eq!(
        store.commit_position().await,
        Ok(before),
        "an entry is no event"
    );
}

pub async fn the_outbox_drains_oldest_first_and_clears<S>(store: S)
where
    S: Store + Outbox,
    for<'s> S::Unit<'s>: UnitOutbox,
{
    for batch in [
        vec![entry(3, "a", 1), entry(1, "b", 1)],
        vec![entry(2, "a", 1)],
    ] {
        let mut unit = store.begin().await.unwrap();
        unit.put_outbox(&batch).await.unwrap();
        unit.commit().await.unwrap();
    }
    let (e3, e1, e2) = (entry(3, "a", 1), entry(1, "b", 1), entry(2, "a", 1));
    assert_eq!(
        store.pending(10).await,
        Ok(vec![e3.clone(), e1.clone(), e2.clone()]),
        "commit order, then put order; never by id"
    );
    assert_eq!(
        store.pending(2).await,
        Ok(vec![e3.clone(), e1.clone()]),
        "a limit"
    );
    assert_eq!(store.clear(&[e3.id, e1.id]).await, Ok(2));
    assert_eq!(store.pending(10).await, Ok(vec![e2.clone()]));
    assert_eq!(
        store.clear(&[e1.id]).await,
        Ok(0),
        "cleared twice: no error"
    );
    assert_eq!(store.clear(&[e2.id]).await, Ok(1));
    assert_eq!(store.pending(10).await, Ok(vec![]));
}

/// At least once: an entry stays pending, verbatim, until cleared.
pub async fn a_pending_entry_is_redelivered_until_cleared<S>(store: S)
where
    S: Store + Outbox,
    for<'s> S::Unit<'s>: UnitOutbox,
{
    let mut unit = store.begin().await.unwrap();
    unit.put_outbox(&[entry(1, "a", 9)]).await.unwrap();
    unit.commit().await.unwrap();
    assert_eq!(store.pending(10).await, Ok(vec![entry(1, "a", 9)]));
    assert_eq!(
        store.pending(10).await,
        Ok(vec![entry(1, "a", 9)]),
        "read again, uncleared: delivered again, byte for byte"
    );
}

/// An id is the receiver's dedup key: put again while pending, the first
/// message is kept, verbatim.
pub async fn an_entry_put_again_while_pending_keeps_its_first_message<S>(store: S)
where
    S: Store + Outbox,
    for<'s> S::Unit<'s>: UnitOutbox,
{
    let mut unit = store.begin().await.unwrap();
    unit.put_outbox(&[entry(1, "a", 1), entry(1, "a", 2)])
        .await
        .unwrap();
    unit.commit().await.unwrap();
    let mut unit = store.begin().await.unwrap();
    unit.put_outbox(&[entry(1, "a", 3)]).await.unwrap();
    unit.commit().await.unwrap();
    assert_eq!(store.pending(10).await, Ok(vec![entry(1, "a", 1)]));
}

// ------------------------------------------------------------------- macro

/// One test per check of a section, under the caller's test attribute (its
/// runtime), each on a fresh store (or pair) from the last argument: an
/// expression evaluated once per test, inside its `async fn`, so it may
/// `.await`. `store_contract!(#[tokio::test], $fresh)` is the base section;
/// `store_contract!(<section>, #[tokio::test], $fresh)` any other (see the
/// module's table). Tests are named after their checks, so a backend runs
/// each section in a module of its own.
#[macro_export]
macro_rules! store_contract {
    (pair, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            the_commit_position_counts_every_handles_commits,
            a_unit_that_lost_a_race_lands_nothing,
        );
    };
    (purge, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_purge_deletes_a_streams_events_snapshot_and_command_ids,
            a_purge_deletes_the_streams_positions,
            a_purge_deletes_a_snapshot_with_no_events,
            a_purged_stream_starts_again_from_nothing,
            a_purge_in_a_unit_of_work_lands_at_commit_or_not_at_all,
            a_unit_of_work_purges_its_own_appends_and_appends_after,
            a_purge_never_lowers_the_commit_position,
        );
    };
    (editions, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            an_edition_is_created_once_and_recorded,
            an_edition_create_refuses_a_bad_request,
            an_edition_reads_mains_events_below_its_divergence_then_its_own,
            deleting_an_edition_removes_it_and_its_streams_never_mains,
            deleting_an_edition_refuses_an_empty_or_unknown_name,
        );
    };
    (read, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_read_unit_sees_the_store_as_it_began,
            a_read_unit_refuses_an_edition_never_created,
        );
    };
    (read_purge, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_read_unit_keeps_a_stream_purged_after_it_began,
        );
    };
    (read_editions, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_read_unit_reads_a_created_edition_through_to_main,
        );
    };
    (watch, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_change_token_changes_when_its_own_store_commits,
        );
    };
    (watch_pair, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            a_change_token_changes_when_another_handle_commits,
        );
    };
    (until_time, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            read_until_time_is_the_prefix_recorded_by_then,
        );
    };
    (correlation, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            read_by_correlation_gives_one_book_per_stream,
        );
    };
    (list_streams, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            list_streams_is_every_domains_covers_in_order,
        );
    };
    (outbox, #[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
            an_outbox_entry_lands_with_its_unit_or_not_at_all,
            the_outbox_drains_oldest_first_and_clears,
            a_pending_entry_is_redelivered_until_cleared,
            an_entry_put_again_while_pending_keeps_its_first_message,
        );
    };
    (#[$t:meta], $f:expr) => {
        $crate::store_contract!(@each #[$t], $f;
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
            a_second_begin_on_a_handle_serves_or_refuses_never_waits,
        );
    };
    (@each #[$t:meta], $f:expr; $($check:ident),* $(,)?) => {
        $(
            #[$t]
            async fn $check() {
                $crate::contract::$check($f).await;
            }
        )*
    };
}
