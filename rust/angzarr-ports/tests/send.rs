//! On a native target the ports' futures are `Send` (RULED(12): `MaybeSend`
//! is `Send` there): a server spawns a whole unit of work, generic over the
//! store, onto a multi-threaded runtime. The spawning compiling is half the
//! test; running it on `MemoryStore` is the other.

#![cfg(not(target_arch = "wasm32"))]

#[cfg(not(all(feature = "contract", feature = "memory")))]
compile_error!("run `just test` (every feature)");

use std::sync::Arc;

use angzarr_ports::contract::{main_stream, page};
use angzarr_ports::memory::MemoryStore;
use angzarr_ports::{EventStore, PositionKey, Store, StoreError, Unit, UnitOfWork};

/// annals' chain, generic: a unit over two streams and a position, every
/// await inside one spawned task. Compiles only if every port future is
/// `Send` for any `Send` store.
async fn chain<S: Store + 'static>(store: Arc<S>) -> Result<u64, StoreError> {
    tokio::spawn(async move {
        let (a, b) = (main_stream("account", 1), main_stream("ledger", 1));
        let mut unit = store.begin().await?;
        unit.append(a, 0, &[page(0, 1)]).await?;
        unit.append(b, 0, &[page(0, 1)]).await?;
        let key = PositionKey {
            handler: "account-ledger",
            stream: a,
        };
        unit.put_position(key, 1).await?;
        unit.commit().await?;
        store.commit_position().await
    })
    .await
    .expect("the task ran")
}

#[tokio::test(flavor = "multi_thread")]
async fn a_generic_unit_of_work_spawns_on_a_multi_threaded_runtime() {
    let store = Arc::new(MemoryStore::new());
    let position = chain(Arc::clone(&store)).await.unwrap();
    assert!(position > 0);
    assert_eq!(
        store
            .head(main_stream("ledger", 1))
            .await
            .unwrap()
            .next_sequence,
        1
    );
}
