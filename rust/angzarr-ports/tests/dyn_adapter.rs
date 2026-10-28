//! The dyn adapter: core's `Arc<dyn …>` wiring (OPEN(15) in contract.rs).
//!
//! Red because the adapter's boxing impls (src/dyn_store.rs) are stubbed,
//! and beneath them the reference store.

#[cfg(not(feature = "contract"))]
compile_error!("the suite is behind the `contract` feature: run `just test`");

mod memory;

use std::sync::Arc;

use angzarr_ports::contract::{main_stream, page};
use angzarr_ports::{DynEventStore, DynStore, DynUnitOfWork};
use memory::MemoryStore;

/// `Arc<dyn DynStore>` is a `Store` again, so the whole base section runs
/// on it unchanged: the adapter is held to the same contract as the
/// backend under it.
mod base_through_dyn {
    use super::*;
    angzarr_ports::store_contract!(
        #[tokio::test],
        Arc::new(MemoryStore::new()) as Arc<dyn DynStore>
    );
}

mod pair_through_dyn {
    use super::*;
    angzarr_ports::store_contract!(pair, #[tokio::test], {
        let (a, b) = MemoryStore::pair();
        (
            Arc::new(a) as Arc<dyn DynStore>,
            Arc::new(b) as Arc<dyn DynStore>,
        )
    });
}

/// What core does: hold the store as `Arc<dyn DynStore>`, clone it into a
/// spawned task on a multi-threaded runtime, and call the boxed methods
/// directly. Needs `'static + Send` futures from a shared handle.
#[tokio::test(flavor = "multi_thread")]
async fn a_dyn_store_is_shared_across_tasks_as_an_arc() {
    let store: Arc<dyn DynStore> = Arc::new(MemoryStore::new());
    let writer = Arc::clone(&store);
    let s = main_stream("account", 1);
    let written = tokio::spawn(async move {
        let mut unit = DynUnitOfWork::begin(&*writer).await?;
        unit.append(s, 0, &[page(0, 1)]).await?;
        unit.commit().await
    });
    written.await.unwrap().unwrap();
    assert_eq!(
        DynEventStore::head(&*store, s).await.unwrap().next_sequence,
        1
    );
}

/// Core's per-port fields (`Arc<dyn DynEventStore>` beside
/// `Arc<dyn DynSnapshotStore>`) upcast from the one store.
#[tokio::test]
async fn one_dyn_store_upcasts_to_each_port() {
    let store: Arc<dyn DynStore> = Arc::new(MemoryStore::new());
    let events: Arc<dyn DynEventStore> = store.clone();
    let s = main_stream("account", 1);
    events.append(s, 0, &[page(0, 1)]).await.unwrap();
    assert_eq!(
        DynEventStore::read(&*store, s, 0, None)
            .await
            .unwrap()
            .pages,
        [page(0, 1)]
    );
}
