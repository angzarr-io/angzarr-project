# The bus interface: subscriptions served from a stream store

**Status:** the owner's design; §15 and §16 record the owner's decisions on the transport layer. The trait is `angzarr_bus::Bus` in angzarr core's `crates/angzarr-bus`, its conformance suite `angzarr_bus::contract` (feature `contract`); the first implementation is angzarr-embedded's `Bus`. The distributed coordinator's implementation is §9's sketch, not built. The handler contracts it serves are unchanged: `ProjectorService.Project` (docs/design/projectors.md) and `PolicyService.React`/`Translate` (docs/design/policies.md).

A bus serves **subscriptions**: each is a named handler, the streams it
reads, and how much of them it may have in flight. The bus reads every
owed event from the store, hands it to one of the subscription's
instances, and records the subscription's position once the instance
answers. There is ONE interface, so the in-process bus over the event
store and the distributed bus stand in for each other: an application
written against the trait runs on either.

What this document fixes, for every implementation: the two handler
kinds (§1), the subscription (§2), positions (§3), delivery (§4), the
atomic commit of a policy's outputs (§5), failures (§6), purged streams
(§7), and how a policy on a bus relates to the angzarr-embedded kernel's
inline policies (§8).

## 1. Two handler kinds

- **A projector subscription** serves a sink. Its answer is "handled" or
  a failure, nothing else: the bus routes nothing. Its instances may have
  side effects, recording through a runtime (angzarr-embedded's
  `Kernel::handle`) among them, each with its own identity: a runner that
  records one fact per run of a work item, each fact's external id
  derived from its cause, so a redelivery records nothing twice. The bus
  neither sees nor routes what a sink records.
- **A policy subscription** serves a policy (`PolicyService`: React, and
  Translate for its refused commands). Its answer is outputs, commands or
  facts addressed to target streams, and the bus routes them: it
  addresses, stamps and checks each one, derives its command id, delivers
  it, and commits the policy's position with them (§5). Routing is done in
  one place per transport: angzarr-embedded's kernel in process (its
  `check_outputs` and `ids::policy_command_id`, the one copy), the
  coordinator's `Deliver` distributed (docs/design/distributed-transport.md
  §2).

Policies move work across domains; anything that does work and reports
what it found is a projector that records facts. A policy is never a
worker pool.

The handler types are the implementation's (the trait's associated types
`Projector` and `Policy`): angzarr core cannot name angzarr-router's
`ProjectorHandler` and `PolicyComponent`, which depend on it.
angzarr-embedded serves exactly those (a projector boxed as
`DynProjectorHandler`; a policy as a `BusPolicy`, its `PolicyComponent`
with its output domain), and so does a coordinator, whose components are those traits
over gRPC (the host's remote projector and policy). An application is
generic over a bus whose handler types are those.

## 2. The subscription

```rust
pub struct Subscription<P, Q> { /* name, scope, credit, handler */ }
pub enum Handler<P, Q> { Projector { scope: Scope, projector: P }, Policy(Q) }
pub struct Scope   { /* one or more domains */ }
pub struct Credit  { /* instances */ }

pub trait Bus {
    type Projector;
    type Policy;
    type Refused: Diagnostic;
    type Error: Diagnostic;

    fn subscribe(
        &mut self,
        subscription: Subscription<Self::Projector, Self::Policy>,
    ) -> Result<(), Self::Refused>;

    fn serve<M: FnMut(&Served) -> bool + MaybeSend>(
        &mut self,
        more: M,
    ) -> impl Future<Output = Result<(), Self::Error>> + MaybeSend;
}
```

- **The name** keys the positions and, for a policy, derives every
  command id. Two subscriptions on one bus never share a name; a policy's
  name is its `PolicyDescriptor` name.
- **Scope: every stream of a set of domains**, at least one, every
  edition's streams as main's. A stream that appears later is served from
  its start. A policy's scope is its one input domain.
- **Credit: instances.** At most `instances` items of the subscription
  are in its handler at once, and **one of a stream**, always: a stream's
  events are handled one at a time, in order, for projectors and policies
  alike (a policy's position is committed with its outputs, §5, so it
  moves in order). Subscriptions scale by streams, not by events of one
  stream; work items that should run side by side are streams of their
  own. (A per-stream credit above one, with a handled set above the mark,
  was removed by the owner: §12.)
- **Positions** are kept where the subscription says (§17): the hub's
  store by default, memory for an ephemeral projector.
- **Acknowledgement** is the handler's answer: the bus records the
  position only after it (projectors.md §4: "never mark as done until
  business logic responds with an affirmative").
- **Two layers.** `Bus` is the application's interface. Under it a
  `Transport` carries each subscription's deliveries and takes their
  settlements back (§14); `Hub` is the one generic bus over any transport,
  its handlers reached through a `Dispatch` (the kernel in
  angzarr-embedded, the component clients in a coordinator):

  ```rust
  pub trait Transport {                       // push: the one contract (§16.2)
      type Error;
      fn run<'a, K: Sink>(&'a self, opening: Opening<'a>, sink: &'a K) -> impl Future<Output = Result<(), Self::Error>>;
  }
  pub trait Sink {                            // the hub, one subscription
      fn deliver(&self, delivery: Delivery) -> impl Future<Output = Settle>;  // the answer is the ack
      fn idle(&self) -> impl Future<Output = Flow>;                           // Continue | Stop
  }
  pub trait PullTransport {                   // pull-shaped sources, served through Pumped<P>
      type Token; type Error; type Feed<'t>: Feed<Token = Self::Token, Error = Self::Error>;
      fn open(&self, opening: Opening<'_>) -> impl Future<Output = Result<Self::Feed<'_>, Self::Error>>;
  }
  pub trait Feed {
      fn next(&self) -> impl Future<Output = Result<Next<Self::Token>, Self::Error>>;  // Delivery(token, d) | Idle
      fn settle(&self, token: Self::Token, settle: Settle) -> impl Future<Output = Result<(), Self::Error>>;
  }
  pub struct Delivery { stream: Cover, sequence: u64, attempt: Option<u32>, key: OrderingKey, body: Body }
  pub enum Body { Event(Box<EventPage>), Reference, Gone }
  pub enum Settle { Handled, Held { after: Option<Duration> }, DeadLettered }
  pub struct Hub<'h, T: Transport, P /* positions */, D: Dispatch, R: Recover = StoreRead<'h, P>>;  // impl Bus
  ```
- **Serving.** `serve` runs every subscription until `more`, asked with
  what was served since it was last asked each time the bus is idle
  (nothing in flight, nothing owed but what failed), says no, or until
  the bus meets an error it cannot hold (a store failure). Dropping the
  future is a crash: nothing is lost (§4).

## 3. Positions: one mark per stream

A subscription's position on one stream is its **mark**: every sequence
below it is handled, the mark is not. With one event of a stream in
flight the mark moves by one as each is handled; nothing above it is
recorded.

Stored as one position of the store's `PositionStore` (a `PositionKey`'s
next sequence) under the subscription's name, read back through
`Processed`: the format of an inline policy's (§8) and of the
coordinator's checkpoint (decision 14.68). A policy's mark is written in
the write that holds its outputs (§5).

## 4. Delivery

- **At least once.** The position is written after the handler answers.
  A crash between the answer and the write hands the item again; one
  before the answer, likewise. A re-served subscription is handed
  exactly what its stored position does not cover: nothing handled is
  skipped, and nothing below the mark is handed again.
- **Per stream, never across streams.** Nothing orders two streams'
  events (projectors.md §2, decision 14.96).
- **Read when handed.** The bus keeps no event: it reads each from the
  store when an instance is free for it, so credit, not memory, bounds
  what is in flight.
- **Several subscriptions on one bus** each have their own positions and
  instances; one's failure or slowness holds none of the others.
- **Wake source.** The implementation's. In process: the store's
  `CommitNotify`, armed before each read, so no commit after the arming
  is missed, with the `Watch` change token polled on the caller's timer
  as the fallback (another process's commits). Distributed: the stream
  subscription the coordinator follows (§9).
- **A framework meta-event** (an edition's fork) is never handed; its
  sequence counts as handled.

## 5. A policy's outputs, committed with its position

The position never moves past a trigger unless every output of it is
durable, and an output is never delivered twice:

- **Through the outbox, in both** (policies.md §5): the stamped outputs
  are written to the transactional outbox in the same write as the
  policy's position past the trigger, then delivered (distributed,
  `Deliver`; angzarr-embedded, each a step of its own in its target,
  through the target's five steps) and cleared; the receiver
  deduplicates by the command id. A crash after the write leaves the
  entries pending: they are relayed when the policy is next served
  (angzarr-embedded: before its first delivery, `Dispatch::opened`), and
  the policy is not run again for that trigger. A failed write lands
  neither the outputs nor the position.
- **A relayed step's failure** is the kernel's or coordinator's, as for any
  reaction: a refusal goes to Translate, a bug or a cap is dead-lettered,
  and the entry is cleared; a failure that would be run again (a store's,
  a retryable one with retries off) leaves it pending.

Either way the ids are `ids::policy_command_id(trigger, name, index)`,
commands and facts in one index space, so a re-run, a redelivery or a
re-sent outbox entry lands nothing twice. A refusal's fact (Translate) is
committed the same way, with the refused command's id: it is an outbox
entry of its own, written in the same write that clears the refused
command's entry (`Write::cleared`, cleared before the write's own entries
are added), and then relayed as any entry is. A crash after that write
re-sends the fact, never the command. This is the coordinator's design
too; angzarr-embedded's earlier in-memory hand-off of the fact was the
last divergence of its policy path, closed by the owner.

## 6. Failures

- **A projector's failure is classed by its status** (command-handling.md
  §3), as every framework retry loop's is: a retryable one (UNAVAILABLE,
  DEADLINE_EXCEEDED, RESOURCE_EXHAUSTED, ABORTED) is retried with backoff
  and jitter up to the retry cap, then dead-lettered; any other
  (INTERNAL, UNKNOWN, a business status) is dead-lettered at once.
  Dead-lettered, its letter kept, the event is passed and the position
  moves past it: the letter is the record to replay. A failure not yet
  dead-lettered (retries off, the letter not kept, an upcast that failed)
  holds its event, handed again at the next poll; a stream with one item
  in flight is held there, the others go on. Every failure is reported in
  `Served`'s failures. In process the kernel's inline-projector retry
  loop does this (`Kernel::project_book`), so a projector fails alike
  inline and on the bus.
- **A policy's failure is its router's.** In process the kernel's rules
  hold unchanged (command-handling.md, policies.md §4): a policy's own
  error, a handler's bug in a step, or a retryable failure past its cap,
  is dead-lettered, and the position moves past the trigger
  (`OnPolicyBug::MovePast`, the default) or stays (`OnPolicyBug::Stay`);
  a refused answer (`check_outputs`), a malformed reaction, a chain too
  deep (`ChainTooDeep`) or a store failure holds the position. The bus
  reads where the position ended: moved past, the trigger is done;
  held, it is handed again at the next poll. Every one is reported in
  `Served`'s failures. Distributed: the same rules, with on_policy_bug,
  by the policy coordinator.
- **Dead letters** are the router's: the kernel keeps each in the store
  with the write that moves the position past it, as for an inline
  policy.

## 7. Purged streams

A stream the subscription holds a position on and the store no longer
lists (decision 14.68: a purge never touches positions):

- **a projector** is handed it once as gone (its cover, no page), and,
  handled, the position is put back to 0;
- **a policy** is never called for it (one event per call, decision 46,
  Q3): its position is put back to 0, as `Kernel::forget_gone` does.

A stream whose head is below the mark (purged and written again) is
served again from its start.

## 8. Inline policies and the bus

angzarr-embedded runs a policy one of two ways, never both:

- **Inline**: registered in the `Registry` (`Registry::policy` and its
  twins). It runs inside `Kernel::handle`'s chain, once per written
  event, and `Kernel::resume` runs what it owes after a crash.
- **On a bus**: a policy subscription
  (`Subscription::policy(instances, BusPolicy::new(policy))`) of
  angzarr-embedded's bus, which is the trait's implementation and has no
  API of its own beside it (`Bus::new(Host::new(store, kernel, clock,
  wait, every))`). It is
  not in the registry, so no chain runs it and `Kernel::resume` and
  `Kernel::forget_gone` never touch it: the bus's positions are its
  resume, and the bus forgets its purged streams (§7). The hosted bus
  refuses to subscribe a policy whose name the kernel's registry runs
  inline (`Misconfigured::ComponentRegistered`), and one whose source is a
  remote domain (`Misconfigured::RemoteSource`), as registering it is
  refused; so is a projector subscription whose scope holds a remote
  domain.

A policy step on the bus is an inline step's: the kernel runs the one
policy on the one trigger (upcast first), routes its outputs as a chain
does (the same `react`, `check_outputs`, ids, retries, Translate, dead
letters, `OnPolicyBug` and depth limit), and then settles what those
outputs wrote: the targets' inline policies and the inline projectors
run, exactly as after `Kernel::handle`. Its sampled instant is the bus's
clock's at the step.

**Moving a policy between inline and the bus keeps its place**: both
keep the position under the policy's name, as the next sequence on each
source stream, so a policy registered inline yesterday and served by a
bus today is handed only what it has yet to handle, and its re-derived
ids deduplicate anything in between.

Nothing about an inline policy changes: `Kernel::handle`, the chain, its
failures and `Kernel::resume` are as they were.

## 9. The distributed implementation

The coordinator implements the same trait:

- **Projector subscriptions**: the coordinator follows each scope's
  domains through its transport (the bus envelope, or a broker: §14,
  §16) as its wake source, lists streams with `ListStreams`, hands each
  owed event to one of the subscription's instances
  (`ProjectorService.Project`) within its credit, and records the mark in
  its `PositionStore` after the affirmative answer. The mark is the
  coordinator's, never the client's cursor. It is the `Hub`'s role, with
  the component clients as its `Dispatch`: credit and positions are the
  coordinator's, never the client's. `EventStreamService.Subscribe` is not
  the bus's (§16.10, Backlog).
- **Policy subscriptions**: `PolicyService.React` per owed trigger, the
  outputs checked, addressed and stamped (the same rules and ids as
  angzarr-embedded's kernel), written to the outbox with the checkpoint in
  one transaction, relayed by `Deliver`, Translate on a business refusal
  (policies.md §3-5).
- **Gone streams** from its `ListStreams` and `Processed` as in §7; dead
  letters to its `DeadLetterStore`.

One copy of the output rules: `check_outputs` and the stamping are
angzarr-embedded's today; for the coordinator to share them they move to
angzarr-router (beside `PolicyComponent`), a change of its own.

## 10. angzarr-embedded's earlier bus, audited against the distributed design

angzarr-embedded's first `Bus` (projectors only, before this interface)
was designed in process first. Each of its points against the
distributed design, and what became of it; the trait (§2) is the
definition, and the bus was reworked to it:

| Point | The earlier bus | Verdict | Now |
|---|---|---|---|
| Positions | a mark under the name and the handled set under `name+handled`, two `PositionStore` positions in one write, read back through `Processed` | compatible | the mark kept, the format of the coordinator's checkpoint (its `Processed` is the same record, decision 14.68); the handled set removed with per-stream credit above one (§12) |
| A policy's outputs | none: projectors only | needed change | policy subscriptions, committed through the outbox as the coordinator's are (§5) |
| Ack and credit | the handler's `Ok`, written after; instances and per stream | compatible | the ack kept: projectors.md §4's "never mark as done until business logic responds"; credit is instances, one event of a stream in flight (§2) |
| Ordering | per stream, never across | compatible | kept (decision 14.96, queries-and-subscriptions.md §5) |
| At least once, dedup | re-handed until written; a projector skips by (stream, sequence) | compatible | kept; a policy's dedup is its derived ids (§5) |
| Failure | every error held and re-handed at each poll, forever: no status class, no retry cap, no dead letter, so one bug stalled its stream | needed change | classed by status, retried to the cap, dead-lettered and passed (§6), the kernel's inline-projector loop reused |
| Purged streams | handed once as gone, forgotten | compatible | kept; a policy forgets without a call (§7) |
| Wake | `CommitNotify`, the `Watch` poll | unavoidable divergence | the transport's (§12, 5) |
| Naming and identity | the projector's name keyed its positions; a name was refused twice on one bus, not against the registry | needed change | the name is the component's registered name (the coordinator's projector and policy names); a policy is refused if the registry runs it inline, and any subscription of a remote source is refused |
| API | its own `Subscription`, `Served` and `follow`/`follow_commits`, served with a catalog and no kernel | needed change | removed: `Bus::new(Host)` implements the trait and has nothing beside it, so an application written to it is written to the trait |

## 11. The Go predecessor (evented)

angzarr's Go predecessor (github.com/benjaminabbitt/evented) ran sagas
and projectors over a transport. What it was, read from its source:

- **Interfaces.** Async delivery was one method,
  `EventTransporter.Handle(ctx, *EventBook) error`
  (transport/async/eventTransporter.go:8-10); synchronous delivery one
  per kind, `SyncSagaTransporter.HandleSync(ctx, *EventBook)
  (*SynchronousProcessingResponse, error)`
  (transport/sync/saga/syncSagaTransporter.go:9-11) and
  `SyncProjectorTransporter.HandleSync(ctx, *EventBook) (*Projection,
  error)` (transport/sync/projector/syncProjectionTransporter.go:9-11).
  The command handler held them in a `transport.Holder`: Go channels of
  books for the async sinks, and the sync clients
  (applications/command/command-handler/framework/transport/transportHolder.go:9-16).
  The services were `Saga`/`SagaCoordinator` and
  `Projector`/`ProjectorCoordinator`, each `Handle` and `HandleSync`
  (proto/evented/evented.proto:81-93, 119-130).
- **Delivery: pushed by the writer.** After its write the command
  handler called every sync projector and saga with the pages marked
  `synchronous` (framework/server.go:74-106, 108-144; the retries at :58, :112, :132), then sent the book
  down every async channel to an AMQP fanout exchange
  (transport/async/amqp/sender/amqp.go:23-40). A saga's or projector's
  coordinator received from its queue
  (transport/async/amqp/receiver/amqp.go:30-58,
  applications/event/saga/amqp/amqp.go:30-46).
- **A saga's outputs** were books its business logic answered
  (`SynchronousProcessingResponse.books`), which the coordinator sent to
  the other domain's `BusinessCoordinator.Record`
  (support/coordinator/sagaCoordinator.go:41-47): facts recorded at the
  target, the first configured target only
  (applications/event/saga/grpc/coordinator.go:24), with no derived id.
- **Acknowledgement and retry.** The receiver acked on success and nacked
  to requeue on failure (applications/event/saga/amqp/amqp.go:33-44),
  but consumed with auto-ack on (receiver/amqp.go:117-125), so the
  broker had already dropped the message. Every gRPC call retried with
  an unbounded exponential backoff (transport/sync/saga/grpcSagaClient.go:15-21,
  framework/server.go:58-61); there was no dead letter.
- **Positions.** `Processed` kept the last sequence received per root,
  one collection per deployed coordinator
  (repository/processed/processed.go:22-57). On a delivery whose sequence
  was past the last + 1, the coordinator read the gap from
  `EventQuery.GetEvents` and handed it first (`RepairSequencing`,
  support/coordinator/coordinatorBase.go:18-48), then marked the book
  processed (:50-58). A saga's position was marked before its outputs
  were routed (sagaCoordinator.go:34 then :41), and a routing error was
  logged and dropped (:43-45).
- **In-memory and networked transports were interchangeable** by the
  narrow interface: a channel, a no-op sender
  (transport/async/amqp/sender/noop.go) and AMQP behind
  `EventTransporter`; a gRPC client behind each `Sync*Transporter`.

Point by point, which side has the better idea (evented, angzarr-embedded's
earlier `Bus`, or the distributed design as written), and why:

| Point | Better | Why |
|---|---|---|
| A request/response handler contract | the earlier `Bus`, with the distributed design | evented had one: `Handle(EventBook) -> Empty` and `HandleSync(EventBook) -> SynchronousProcessingResponse`/`Projection` on every `Saga` and `Projector` (proto/evented/evented.proto:88-93, 126-130), and its AMQP coordinator acked on `Handle`'s answer (applications/event/saga/amqp/amqp.go:33-44). But the answer acknowledged nothing durable: auto-ack had already dropped the message, and the position was marked before a saga's outputs were routed. The earlier `Bus` makes the per-event answer the ack (the position written after it, nothing before), which is projectors.md §4's rule; keep it |
| Credit | the earlier `Bus` | instances bound what is in flight per subscription, one event of a stream at a time; evented had none (a channel, a queue's prefetch), and the distributed design names none. Proposal 1 below |
| The event source | the earlier `Bus` | nothing is stored twice: each event is read from the store at the position when an instance is free for it, the bus holding only slots and positions, woken by `CommitNotify` with the `Watch` token as the fallback. evented carried whole books through channels and AMQP; the distributed design carries books in a `BusEnvelope`, with a claim check for large payloads (distributed-transport.md §4), a second copy of every event and a second failure path (`PAYLOAD_UNAVAILABLE`). Proposal 2 below |
| Gaps and redelivery | the earlier `Bus` | evented repaired a gap by reading the store when a pushed book arrived past its position (`RepairSequencing`); reading from the store always makes a gap impossible rather than repaired |
| Positions | the distributed design | a checkpoint per (handler, stream) in `Processed` (decision 14.68), as evented did per root; the earlier `Bus`'s handled set above the mark is removed (§12) |
| A policy's commit | the distributed design | the outbox written with the checkpoint (policies.md §5) is stronger than angzarr-embedded's last-step write: it needs no re-derivation. evented's mark-before-route lost outputs. angzarr-embedded now commits through the outbox too (§5) |
| Retry and dead letters | the distributed design | status classes, a capped backoff, then a dead letter (command-handling.md §3); evented retried without bound, and the earlier `Bus` held a bug forever. The bus now does the distributed design's (§6) |
| Interchangeable transports | evented and the distributed design alike | one narrow interface per handler kind, its in-process and gRPC implementations behind it; the trait keeps that (§1) |

The owner's rulings on the two proposals:

1. **Credit in the distributed design: approved, made.** The projector and
   policy coordinators serve each subscription at a credit of instances,
   one event of a stream at a time
   (projectors.md §4, distributed-transport.md §2 and §3).
2. **Notifications, not events, on the distributed message bus: not
   approved.** The bus envelope keeps carrying events, with claim checks
   for large payloads (distributed-transport.md §4); a transport may still
   carry references (§14), and every transport falls back to the store for
   missing predecessors.

What we keep:

- **One narrow interface per handler kind**, the same in process and over
  the wire: `ProjectorService.Project` and `PolicyService.React`/`Translate`
  are the Go `Projector`/`Saga` services' successors, and the trait's
  associated handler types are them (§1).
- **The store is the truth, a delivery a hint.** `RepairSequencing` read
  the gap from the store whenever a pushed book arrived past the
  position; the bus goes further and reads every event from the store
  when it is handed (§4), so a lost or reordered push loses nothing.
- **A position per (handler, stream), the next sequence**, as `Processed`
  kept it; ours names the handler (one store holds every subscription's).
- **A saga answering facts for its target**: angzarr's policy fact arm
  (policies.md §2).

What we do differently, and why:

- **The position moves with the outputs, never before them** (§5):
  evented marked a saga's position before routing its outputs and
  dropped a failed route, so a crash or a refusal lost them. This answers
  the outbox: the outputs are durable with the checkpoint, written in
  one transaction, in angzarr-embedded as in the coordinator; evented's
  loss is the case against anything weaker.
- **Ids are derived** (`policy_command_id`), so a redelivery lands
  nothing twice; evented's facts had none, and a requeue recorded them
  again.
- **Acknowledge only after the answer, and bound the retries**: evented's
  auto-ack lost failed messages and its unbounded backoff stalled a
  stream on a bug forever; the bus writes the position after the answer
  and dead-letters at the cap (§6).
- **One event of a stream at a time for a policy** (§2): evented's
  coordinators handled a root's books in sequence (the gap repair
  assumed it), which a saga's outputs need; the bus keeps that order for
  every subscription.
- **The writer does not call its subscribers** (evented's command
  handler called every sync saga and projector and waited): a transport
  pushes into the bus (§16), the store its canonical source and the
  commit its doorbell in process, and SIMPLE's synchronous projection is
  the command coordinator's (`HandleSync`), not the bus's.
- **Every output goes to its policy's one output domain**, addressed by
  the kernel or coordinator; evented sent every saga book to its first
  configured target.

## 12. Divergences of angzarr-embedded from the distributed design

(Ephemeral subscriptions, §17, are not a divergence: the same trait, the
same semantics, and a broker mapping for each, on both.)

The rule: angzarr-embedded and the distributed system diverge only where
they must, so an application prototyped on angzarr-embedded moves to the
distributed system unchanged. The distributed design (§9,
distributed-transport.md, policies.md, queries-and-subscriptions.md,
process-managers.md) is the reference, not angzarr-embedded's existing
behaviour. The trait and the conformance suite (§13) are written to it:
every check holds of both. Where angzarr-embedded's `Bus` differs today:

1. **(closed)** A refusal's fact is its own outbox entry, written in the
   write that clears its refused command's (policies.md §4), in both (§5;
   `Write::cleared` in angzarr-ports).
2. **(closed)** A policy's outputs and position commit through the
   outbox in both (§5).
3. **A served policy's step settles the inline chain downstream** (its
   targets' inline policies and the inline projectors run in the same
   call). Necessary only while inline policies exist; they are
   angzarr-embedded's alone (the atomic in-process chain, a deliberate
   divergence tagged in angzarr-embedded-conformance's `tags.test.rs`). An
   application with every policy on the bus has none.
4. **`Kernel::resume` and `Kernel::forget_gone`** exist for inline
   policies alone; the bus, in both, is its own resume. Necessary for the
   same reason as 3.
5. **The wake source**: the store's `CommitNotify` and `Watch` in process,
   the coordinator's stream subscription distributed. Necessary: it is the
   transport.
6. **(closed)** A held failure is settled `Held { after }` with the bus's
   retry policy's delay (§15.8), in both; the store transport waits it
   out. What remains is where the attempts are counted: angzarr-embedded's
   store transport keeps no count, so the hub counts in memory and a
   restart resets the count (Choice B); a broker that counts is
   authoritative.
7. **One event per Project call.** Distributed, Project is handed a run
   of one stream's events (projectors.md §1); angzarr-embedded's bus hands
   runs of one. A run of one is a run, so a projector written for either
   is correct on both; the coordinator may batch a stream's run.

**Removed by the owner: per-stream credit above one.** The earlier bus
let a projector of independent work items ask for up to 64 events of one
stream in flight, finishing out of order, its position a mark and a
handled set above it (`Window`, a second position under `name+handled`).
Removed entirely: no handled set, no `MAX_PER_STREAM`, no per-stream
credit; `Credit` is instances, one event of a stream in flight, and the
`CreditGate` admits one per key. Why: every broker's ordering (a Kafka
partition, a JetStream subject at `max_ack_pending` 1, an SQS message
group) and the hub's one fill per stream (§16.4) assume one in flight per
stream; a second position per stream cost the coordinator a write per
event; and work items that should run side by side are streams of their
own (Cherenkov's runner: one stream per mutant, n instances).

## 13. Conformance

`angzarr_bus::contract` is a test kit any implementation runs: a
`Harness` gives the suite a bus over durable state it can drop and
rebuild, a store to append to and purge, and adapters from the suite's
scripted sink and policy to the implementation's handler types; each
check is a `pub async fn` over a harness, `bus_contract!` stamps a test
per check. The checks below are the bus's own; the positions' and the
ephemeral subscription's are §17's. The checks:

- a crash hands again exactly what the stored position does not cover,
  skipping nothing;
- a re-served policy delivers nothing twice: its outputs' ids are
  `policy_command_id`'s, deduplicated at their targets;
- several subscriptions on one bus are each served all their scope's
  events, and only those;
- a stream's events are handed one at a time, in order; credit bounds
  what is in flight, instances in all and one of a stream;
- a policy's position moves only with its outputs (a failed commit lands
  neither);
- a projector's retryable failure is handed again, and its bug
  dead-lettered and passed, its stream going on;
- a policy's bug is dead-lettered (the position past it, not run again)
  or held (run again);
- a purged stream is handed to a projector once as gone and forgotten by
  a policy;
- a commit wakes the bus with no poll;
- over the suite's scripted transport: out-of-order deliveries served in
  stream order from the store, the late originals not handled twice; a
  policy's triggers likewise; a held delivery settled held and delivered
  again, one attempt more; seventy delivered last first handled in order;
  a missing predecessor held and never skipped, dead-lettered at the cap
  naming the sequence it waits on; a poison event recovered from the
  store dead-lettered at the cap (attempts counted across sources); a
  long gap recovered within credit; a held delivery carrying its retry
  delay.

The invariant every check keeps: events missing or out of order are
recovered and applied in stream order; the transport's own copies,
arriving later, are dropped as duplicates, never handed again.

The transport's own checks are §14's.

**The kit is itself tested.** Every check of `angzarr_bus::contract` and
`contract::transport` is run, in angzarr core's `tests/contract/flawed.rs`,
against an implementation broken on purpose: a handler called twice,
an event skipped or swapped, a failure swallowed, no dead letter kept, a
credit exceeded or undershot, a delay dropped, a commit that does not wake,
a recovery that invents or misnumbers an event, a transport that mislabels
a delivery, forgets what was unsettled or the positions, ignores a delay, or
drops a purged stream, or answers idle for ever. Each check must fail its
flawed implementation (naming why) and pass the same wrapper with no flaw,
so no check is green by accident; a test lists every check by name and fails
if one has no flaw. The ports' outbox clearing check has the same
(`angzarr-ports/tests/meta.rs`). A check that waits does so within one
deadline (three seconds in the reference run), so a bus that never answers
fails quickly instead of spinning.

**Accepted mutation survivors** (cargo-mutants over the branch's diff; core
85% and embedded 90% of what is not unviable are the bars). Mutants killed by
a test hanging until the run's timeout count as kills: they are busy loops in
the hub or the store feed under a broken step (a delivery's slot never
settled, a fill that returns without progress), which no deadline can
interrupt on one thread. What survives, and why it cannot be told from the
original by anything observable:

| Where (angzarr core, at the branch tip) | Mutation | Why equivalent |
|---|---|---|
| `pump.rs` `pump`, the burst bound `taken > BURST` | `>` to `==`, `>=` | The bound is a fairness constant: yielding after 32 or after 33 steps differs only in when the runtime runs its other work; the starvation test passes with any bound that yields at all. |
| `contract.rs` `a_projectors_bug_is_dead_lettered_and_its_stream_goes_on`, its wait `handled >= 1 && idles >= 3` | `&&` to `\|\|`, `>=` to `<` | How long the check watches for a repeat after the bug is passed. The reference run and every flaw in the flawed tests settle within the first idle; the three idles only widen the window. |
| `contract.rs` `a_purged_stream_is_handed_to_a_projector_once_as_gone_and_forgotten_by_a_policy`, its wait | `&&` to `\|\|`, `>=` to `<` | As above, for a repeated gone delivery. |
| `contract.rs` `a_commit_wakes_the_bus_with_no_poll`, the commit's wait `idles >= 1` | `>=` to `<` | The serve is polled before the commit's future in the check's driver, so the bus has already scanned and gone idle when the commit lands, with the wait or without it. |

Three survivors in angzarr-embedded are not equivalents but gaps, left for a
store that can be made to fail at a chosen step of a relay: `served.rs`
`relay_pending`'s arm that stops the bus on a store failure while it keeps
the letters of a relayed entry; `step_relayed`'s test that a handler's fault
writes its command's letter only if the step raised none (`==`), and its
`retried || given_up` (`||`). The toy store's faults count writes, not steps,
and could not place a failure there.


## 14. Brokers: handled or failed, and what a delivery must carry

Every delivery is acknowledged, handled (dequeued) or failed, with no
fire-and-forget path, and the interface maps onto real brokers (Kafka,
RabbitMQ, JetStream and the like) using only the data it carries; a
broker may carry the event or only a reference to it, resolved against
the event store.

**The transport layer** (the owner's decision; its push shape §16).
Under `Bus` (§2) a `Transport` runs one subscription (its name, scope and
credit: the consumer group, queue or durable consumer) into a `Sink`, the
hub: each `Sink::deliver` call is one `Delivery`, and the `Settle` it
answers is the acknowledgement, once, after its handler answered:
`Handled` (dequeue: Kafka commit, AMQP `basic.ack`, JetStream `ack`),
`Held { after }` (redeliver after the delay, its attempt one more: the
retry topic of its delay band, `basic.nack` or the delay exchange, `nak`
with the delay) or `DeadLettered` (dequeue after the bus kept the
letter). A pull-shaped source implements `PullTransport` and its `Feed`
(`next`, then `settle(token, ..)`), served through `Pumped`. `Hub` is the
one generic bus over any transport; what it does above it is the same
for every transport:

- **positions** are its own, one mark per (subscription, stream) in its
  `PositionStore`, written after the answer: a transport's cursor (an
  offset, an ack floor) is only its own;
- **dedup by the mark**: a delivery below it (a redelivery, a late
  original) is settled handled without its handler;
- **order from the store**: a delivery past its stream's mark waits in
  the stream's lane (at most `AHEAD` of them, one more answered held),
  and one fill drives the stream from the mark, each sequence from an
  arrived delivery or, where none arrived, from the `Recover` stream (the
  event store's canonical copy), in order; the late originals, when they
  come, are below the mark and settled without their handler. So a transport's order never decides correctness: the store is
  the source of order, whatever the broker delivers;
- **references resolved** by reading the event store at the delivery's
  stream and sequence: the event store is part of the bus's context (the
  `Hub`'s store; a coordinator's `EventQueryService`), not an
  implementation detail;
- **credit**: at most a subscription's instances in its handler at once,
  as its transport honours the same credit.

angzarr-embedded's bus is the `Hub` over `Pumped<StoreTransport>`, the
event store as a pull transport, pumped: each owed event delivered as a reference at the
subscription's stored position, nothing carried or kept twice, woken by
the store's `CommitNotify` with its `Watch` token polled as the fallback.
A Kafka or AMQP adapter is another `Transport` under the same `Hub`; none
is built yet, and the requirements on them are below.

**What a delivery must carry**, for any broker to ack, nack or redeliver
it with nothing else:

| Field | Why |
|---|---|
| a delivery handle, the transport's own, kept beside the call (a pull feed's token) | the broker's handle (Kafka: topic, partition, offset; AMQP: channel and delivery tag; JetStream: the message's reply subject; SQS: the receipt handle; Pub/Sub: the ack id; in process: the claim's slot), with the epoch of the serve it belongs to |
| the stream: domain, root, edition | the position's key, the dead letter's place, the ordering key |
| the sequence | the position; dedup by (stream, sequence) |
| the attempt, where the broker counts | authoritative where it has one (JetStream's delivery count, SQS's `ApproximateReceiveCount`); `None` elsewhere, and the hub counts in memory (Choice B) |
| the ordering key | derived from the stream (domain, root, edition), never chosen by the producer: the partition (Kafka), the consistent-hash routing key or single-active-consumer queue (AMQP), the subject token (JetStream), the message group (SQS FIFO), the ordering key (Pub/Sub) |
| the body: the event, or a reference | a reference is (stream, sequence), the claim check's case (`BusEnvelope.claim_checks`), resolved by reading the event store at it |

**The mappings.**

| | Kafka | RabbitMQ (AMQP 0-9-1) | NATS JetStream | in-process store-backed bus | distributed coordinator |
|---|---|---|---|---|---|
| subscription | consumer group, named by the subscription | a queue per subscription, bound to the domain's exchange | a durable consumer per subscription | a pool, by name | a subscription, by the component's name |
| handled (dequeue) | commit the partition's offset up to the lowest unhandled message | `basic.ack` of the delivery tag | `ack` | the position written after the answer | the checkpoint written after the answer |
| failed, held | no per-message nack: publish to the retry topic of its delay band | `basic.nack` with requeue, or the delay exchange | `nak` with the delay | held, its delay waited out | the relay re-delivers after the delay |
| redelivery | from the committed offset after a crash or rebalance | requeued; `redelivered` set | after `ack_wait` | from the stored mark | from the checkpoint |
| dead letter | a dead-letter topic, then commit | a dead-letter exchange (`x-dead-letter-exchange`), or ack after writing the letter | `term`, after writing the letter; `max_deliver` | the letter kept in the store, the position past it | `DeadLetterStore`, the position past it |
| credit (instances) | `max.poll.records`, pause/resume per partition | `basic.qos` prefetch per consumer | `max_ack_pending` | instances | instances |
| per-stream order | per partition, the stream its key: holds, but a partition holds many streams | not across consumers, unless single-active-consumer or a consistent-hash exchange on the stream key | per subject, with `max_ack_pending` per subject 1 or ordered consumers | per stream | per stream |
| position | the offset per partition, contiguous: committed up to the lowest unsettled record (§15.9) | none in the broker: the checkpoint is the consumer's | the consumer's ack floor | a mark per stream, stored | a mark per stream, in `Processed` |
| a reference body | the record holds (stream, sequence) | the message holds (stream, sequence) | likewise | always: the event is read at the position | the claim check |

(SQS and Pub/Sub fit as JetStream does: delete or ack as handled, the
visibility timeout or ack deadline as redelivery, a redrive policy or
dead-letter topic, FIFO message groups or ordering keys for per-stream
order.)

**What brokers cannot express, and the design around it:**

1. **Kafka has no per-message nack, and its offset is per partition.**
   *Required of a Kafka transport:* a **retry topic**. A delivery settled
   held is published to the subscription's retry topic, keyed by its
   stream's ordering key, and its source offset committed, so the
   partition goes on; the retry topic is consumed by the same feed, its
   attempt counted in the record. Per-stream order is kept by routing
   (every record of a stream, retried or not, keyed by its stream) and,
   whatever arrives first, by the bus's order from the store: a later
   event of a stream whose earlier one is retrying is past the stream's
   mark, so it waits in the stream's lane while the hub reads and hands
   the earlier one from the store (or waits for it in flight). The source offset is committed up to
   the lowest unsettled record; a dead-lettered record is committed after
   the bus keeps its letter (a dead-letter topic is optional, the store's
   letter the record). Credit is `max.poll.records` with pause and resume
   per partition.
2. **AMQP orders nothing across consumers.** No subscription is refused
   for it: the bus's order from the store makes the broker's order
   irrelevant to correctness (above). Single-active-consumer or a
   consistent-hash exchange keyed by the ordering key is still advised,
   as it saves the predecessor reads and the late originals' redundant
   deliveries. `basic.qos` prefetch is the credit; `basic.nack` with
   requeue is held; a dead-letter exchange is optional, the store's
   letter the record.
3. **Brokers count attempts loosely.** The attempt is carried in the
   delivery where the broker counts (JetStream's delivery count, SQS's
   receive count), and is then authoritative; elsewhere the hub counts in
   memory (Choice B), so the retry cap (§6) holds on every broker, across
   restarts only where the broker counts.
4. **A broker that carries the event** (the distributed `BusEnvelope`,
   its claim checks resolved before the bus sees the book) delivers
   `Body::Event`; one that carries only (stream, sequence) delivers
   `Body::Reference`, and the bus reads the event at it. Both are the
   same interface. (The proposal to carry notifications only on the
   distributed message bus was not approved: its envelopes still carry
   events, and any transport still falls back to the store for missing
   predecessors.)

**The conformance suite** checks both layers:

- *the transport* (`angzarr_bus::contract::transport`,
  `transport_contract!`, for any broker adapter): a delivery carries its
  stream, sequence, attempt, ordering key, and an event equal to the
  store's or a reference the store resolves; an unsettled delivery is
  delivered again after reopening; a handled delivery whose position is
  recorded is not; a held one is delivered again, its attempt one more
  where the transport counts, and waits out its delay; credit bounds what
  is unsettled, instances in all and one of a stream; a purged stream is
  delivered gone;
- *the bus* (`bus_contract!`, §13), over the implementation's own
  transport, and over the suite's scripted transport, which delivers in a
  scripted order whatever the credit: out-of-order deliveries served in
  stream order, their predecessors read from the store, the late
  originals settled handled without their handler; a policy's triggers
  likewise; every delivery settled, a held one delivered again one
  attempt more; recovery (§13's last checks); and every earlier check.

angzarr core runs both against the generic bus over its in-memory store
(a reference dispatch), and angzarr-embedded runs the bus checks against
its own.

## 15. Composable transports and recovery

**Decided by the owner**, each choice below recorded with its ruling.
Built for the embedded store's assembly only (§15.10: angzarr core's
`angzarr-bus`, used by angzarr-embedded); every other transport is the
specification here. The push shape and the fill (§16) supersede this
section's first recovery flow (parking and batched re-sends, §15.3); what
they replace is said where it stood.

### 15.1 The invariant

Events missing or out of order are recovered and **applied in stream
order**; when the transport's own copies of them arrive later, they are
**dropped as duplicates**: settled handled, never handed again. Every
recovery source keeps it. A sequence is never skipped: what cannot be
recovered holds its stream (§15.5).

### 15.2 The components

A transport is assembled from these, each a type or trait in
`angzarr-bus`; a broker adapter implements what its broker does natively
and borrows the rest. The `Hub` (the generic bus) owns positions,
attempts, parking and the order; the components below serve it.

1. **Recovery** (re-send): a stream's sequences `from..to`, as a stream
   (§16.9).

   ```rust
   pub struct Recovered { pub sequence: u64, pub body: Body }   // Event or Reference

   pub trait Pages: MaybeSend {
       type Error;
       /// The next recovered event, read when asked for; `None` at the end.
       fn next(&mut self) -> impl Future<Output = Option<Result<Recovered, Self::Error>>> + MaybeSend;
   }
   pub trait Recover: MaybeSend + MaybeSync {
       type Error: MaybeSend;
       type Pages<'a>: Pages<Error = Self::Error> + 'a where Self: 'a;
       /// `stream`'s events from `from` on, before `to`, in sequence order,
       /// lazily. Ending early, or skipping a sequence, is a miss (§15.5),
       /// never an error.
       fn recover<'a>(&'a self, stream: &'a Cover, from: u64, to: u64) -> Self::Pages<'a>;
   }
   ```

   Implementations: `StoreRead<S: EventRead>` (the event store's read,
   paged inside the stream; code); a broker's re-send (a JetStream
   replay consumer, the coordinator's `GetEvents`), each spec only.

2. **Reference resolution**: a `Body::Reference` (or a claim check) to
   the event.

   ```rust
   pub trait Resolve: MaybeSend + MaybeSync {
       type Error;
       /// The event at `sequence` of `stream`; `None` is a miss (§15.5).
       fn resolve(&self, stream: &Cover, sequence: u64)
           -> impl Future<Output = Result<Option<EventPage>, Self::Error>> + MaybeSend;
   }
   ```

   `StoreRead<S>` resolves too, reading the store (code); a claim-check
   resolver reads the payload store (`PayloadReference`, spec).

3. **The credit gate**: a concrete type, shared, for any transport whose
   broker cannot bound in-flight per stream (code).

   ```rust
   pub struct CreditGate { /* credit; the keys unsettled; total */ }
   impl CreditGate {
       pub fn new(credit: Credit) -> CreditGate;
       pub fn admits(&self, key: &OrderingKey) -> bool;   // total < instances && key not unsettled
       pub fn take(&mut self, key: &OrderingKey);
       pub fn release(&mut self, key: &OrderingKey);
       pub fn full(&self) -> bool;                        // a broker adapter pauses its fetch
   }
   ```

4. **The contiguous prefix** (spec): positions are one mark per stream
   (§3); for brokers whose commit is cumulative (Kafka offsets per
   partition), a prefix tracker over transport positions:

   ```rust
   pub struct Prefix { /* next uncommitted position; set settled above it */ }
   impl Prefix {
       pub fn at(next: u64) -> Prefix;
       pub fn settled(&mut self, position: u64) -> Option<u64>;  // the new committable next, if it moved
       pub fn committable(&self) -> u64;
   }
   ```

   **Choice A (the prefix's bound), decided: unbounded** (a `BTreeSet`
   above the committable offset, any `max.poll.records`), spec. A bound
   of 64 would cap a whole partition, which carries many streams, not one
   stream; and the 64-bit `Window` it would have reused is removed (§12).

5. **Retry scheduling** (code): the bus's retry policy (the kernel's
   `OnRetryable` shape, in core) gives each held delivery its delay, and
   a shared delay queue serves a transport without broker-side delay.

   ```rust
   pub struct RetryPolicy { pub cap: Option<u32>, pub initial: Duration, pub multiplier: f64,
                            pub max: Duration, pub jitter: f64 }   // cap None: no retries
   impl RetryPolicy {
       pub fn last(&self, attempt: u32) -> bool;                   // at the cap: dead-letter
       pub fn after(&self, attempt: u32, draw: f64) -> Duration;   // the delay before the next
   }
   pub struct Delayed<'t, K> { /* keys due once their timer fires */ }
   impl<'t, K> Delayed<'t, K> {
       pub fn hold<W: Timer + ?Sized>(&mut self, key: K, after: Duration, timer: &'t W);
       pub fn due(&mut self, cx: &mut Context<'_>) -> Vec<K>;
   }
   ```

   `Settle::Held` is `Settle::Held { after: Option<Duration> }` (§15.8).

6. **The gap sweep** (spec only): finds what no delivery will reveal (a
   dropped last event of a stream).

   ```rust
   pub struct Sweep<'s, S> { store: &'s S, every: Duration }
   impl<S: ReadStore + ListStreams> Sweep<'_, S> {
       /// Each stream of `scope` whose head is past its mark and which
       /// nothing delivered or waiting covers: (stream, mark, head).
       pub async fn owed(&self, scope: &Scope, marks: &impl Fn(&Cover) -> u64)
           -> Result<Vec<(Cover, u64, u64)>, StoreError>;
   }
   ```

   Its trigger, cost and reads are §15.6. The store transport needs none
   (its scan is the sweep).

### 15.3 The recovery flow

*Superseded by the fill (§16.4).* The first draft parked an ahead
delivery, re-sent its predecessors in batches of the per-stream credit as
deliveries of the hub's own, and unparked it. Built instead: one fill per
stream, driven by one delivery's call, which walks the stream from its
mark, each sequence from an arrived delivery or from the `Recover`
stream, handing each the same way; the late duplicates are below the mark
and settled `Handled` without their handler. A sweep-detected gap (spec)
enters the stream's lane as an arrival with no waiter.

### 15.4 Attempts across sources

The hub keeps the attempt count per (subscription, stream, sequence),
whatever delivered it (the transport, a recovery, a redelivery after a
crash): a held event's next delivery, from any source, carries the
count, so a poison event recovered from the store reaches the cap and is
dead-lettered as any other.

**Choice B (where attempts live), decided: the broker's count where it has
one, else the hub's in memory, not persisted.** A delivery's `attempt` is
`Some` where the broker counts (JetStream's, SQS's
`ApproximateReceiveCount`) and is then authoritative; `None` elsewhere, and
the hub counts per (subscription, stream) in memory. The embedded store
transport keeps no count, so **a restart resets the count there**: a
poison event gets a fresh cap after each crash of the process. Persisting
it (a position key `name+attempts`) was not chosen.

### 15.5 Holding on a miss, and ahead overflow

- **A miss holds**: a predecessor `recover` does not return (fewer than
  asked, or one missing in the range), or a reference `resolve` answers
  `None` for, is never skipped. The stream holds at it: the parked `d` is
  settled `Held { after }` per the retry policy, recovery stops at the
  miss, the miss is reported (`Served::failures`, its sequence and
  stream), and its attempt counts.
- **Choice C (a miss at the cap), decided: dead-letter the waiting
  delivery, its letter naming the missing sequence, and hold the
  stream; never skip.** The letter is the record an operator replays
  (angzarr-embedded: `predecessor-missing`, "event k of stream s waits on
  event m, which no source has"). Holding for ever was not chosen; skipping
  violates the invariant and was never offered.
- **Ahead overflow**: at most `AHEAD` (4) deliveries ahead of the mark
  wait in a stream's lane; one more is answered `Held { after: None }` at
  once, the broker its buffer (§16.11, 3). Conformance: seventy events
  delivered last first are all handled in order.

### 15.6 The gap sweep

- **Trigger**: on the transport's idle (`Next::Idle`) and on a timer
  (`every`), whichever first; never while a stream's recovery runs.
- **Reads**: one read unit: the scope's streams (`covers` per domain, or
  `ListStreams`) and each one's head; the marks are the hub's.
- **Cost**: one listing and one head per stream per sweep, so `every`
  bounds it. **Choice D, decided: a broker adapter beside a local store
  sweeps every listed stream; the coordinator needs none** (its
  transport, the bus envelope, delivers every stream's events, and a
  dropped tail is the transport's redelivery). `Sweep` is spec only; the
  store transport needs none (its scan is the sweep).

### 15.7 Recovery within credit

Recovery of a long gap runs in the fill (§16.4), in the slot of the call
that drives it, never as deliveries of its own: the `Recover` stream is
read lazily (`StoreRead` a page of 64 at a time), each event handed in
turn, so at most what is in flight is in memory, and the other streams
go on in the other slots. **Choice E, decided: a waiting (ahead) delivery
does not count against the subscription's instances**; its transport's
credit bounds it, and `AHEAD` bounds it per stream. Conformance: a gap of
150 events recovered within a credit of two.

### 15.8 `Held { after }`

```rust
pub enum Settle { Handled, Held { after: Option<Duration> }, DeadLettered }
```

The hub sets `after` from the retry policy and the attempt
(`RetryPolicy::after`); `None` asks for the transport's default. Each
transport honours it natively or with `Delayed` (§15.2.5): JetStream `nak`
with delay, SQS `ChangeMessageVisibility`, Pub/Sub `modifyAckDeadline`,
AMQP a delayed-message exchange or a per-delay TTL queue dead-lettering
back, Kafka retry-topic tiers (one topic per delay band, the record
routed to the band at or above `after`), the store transport `Delayed`
on its timer.

### 15.9 Kafka's contiguous commit

Kafka commits are cumulative per partition: an offset commit says every
record below it is done. A Kafka transport keeps a `Prefix` per assigned
partition: each record's settlement (handled, dead-lettered, or held and
moved to its retry topic) marks its offset; the committable offset is the
prefix's; it commits that (asynchronously, on an interval or every n).
On revocation it commits the prefix and drops the partition's state; on
assignment it starts at the committed offset, and the records re-read
above it are below the hub's marks, settled without their handler.

### 15.10 The assemblies

| Transport | Delivery and settle | Credit | Held, delay | Recovery | Gap sweep | Resolution | Gaps |
|---|---|---|---|---|---|---|---|
| **embedded store** (code) | a pull feed, pumped (§16.11, 1): its scan delivers owed sequences at the stored position as references, woken by the commit; settle `Handled` is the hub's position | `CreditGate`, one of a stream | `Delayed` on its timer | `StoreRead` (rarely used: it delivers in order) | none: its scan is the sweep | `StoreRead` | none |
| **Kafka** | consumer group per subscription; settle marks the `Prefix`, commit cumulative | `max.poll.records`, pause/resume driven by `CreditGate`, one of a key | native: retry-topic tiers | borrowed: the store's read (**Choice F, decided: borrow**; no offset index is kept for a native seek), spec | required | `Body::Event`; claim checks by `Resolve` | no per-message nack (retry topic); offsets per partition (`Prefix`, Choice A) |
| **RabbitMQ (AMQP 0-9-1)** | `basic.ack`; held `basic.nack` with requeue or the delay route | `basic.qos` prefetch; `CreditGate`, one of a key | delayed-message exchange or TTL queues | borrowed: the store's read (no replay) | required | as Kafka | no order across consumers (the hub's order from the store; single-active-consumer advised); no native delay |
| **NATS JetStream** | durable consumer; `ack`, `nak`, `term` | `max_ack_pending`; `CreditGate`, one of a key | native: `nak` with delay | native if subjects are per stream and the sequence is a header (a filtered replay consumer from a start sequence); else borrowed | required | as Kafka | JetStream's sequence is the stream's, not angzarr's: a native re-send needs the subject per stream |
| **SQS** (FIFO) | delete as handled; message group = ordering key | `MaxNumberOfMessages` and in-flight; `CreditGate`, one of a key | native: visibility timeout | borrowed (no replay) | required | as Kafka | visibility at most 12 h; in-flight limits per queue; a redrive policy unused (the bus dead-letters) |
| **Google Pub/Sub** | ack; held `modifyAckDeadline` | flow control; `CreditGate`, one of a key | native: ack deadline | borrowed (seek is to a time or snapshot, coarse) | required | as Kafka | ordering keys pause a key on nack until acked or redelivered |
| **distributed coordinator** (the `Hub`'s role) | the bus envelope; settle is its checkpoint | native, per projectors.md §4 | its relay's schedule | `EventQueryService.GetEvents` range, through `EventRead` over its client (§16.7) | none (Choice D) | claim checks | none beyond the transport's |

Every transport shares the hub's order, dedup, attempts and positions;
what differs is only what it implements natively.

**Built** (the embedded store's assembly only): in `angzarr-bus`,
`Recover` and `Pages`, `Resolve`, `StoreRead`, `CreditGate`,
`RetryPolicy`, `Delayed`, `Settle::Held { after }`; in `Hub`, one fill
per stream through `Recover`, the miss hold and its dead letter at the
cap, attempts (Choice B), and `Held { after }` from the retry policy;
`StoreTransport` a pull feed over `CreditGate` and `Delayed`, pumped.
`Prefix` and `Sweep` are specified, not built (no transport here needs
them). The conformance cases built: a missing predecessor held and never
skipped, dead-lettered at the cap; a poison event recovered from the
store dead-lettered at the cap; a long gap recovered within credit; late
duplicates after recovery dropped; seventy delivered last first; a held
delay honoured. A dropped tail recovered by a sweep stays spec, with
`Sweep`.

## 16. A push-shaped transport, and one fill for catch-up and recovery

**Decided by the owner: (b)**, one push contract with pull-shaped sources
pumped (16.5), as amended by the prior art (16.11, amendments 1 to 9).
Built in angzarr core's `angzarr-bus` and used by angzarr-embedded: the
push `Transport` and `Sink`, `Pumped`, the hub's lanes (a mark and a
fill), the stream-shaped `Recover`, the hub's stores split by role, local
implementations only. The remote implementations (16.7's gRPC reads,
16.10's protos) are specification. The owner had asked whether the
pull-shaped `Feed` fits the existing and planned buses, which are
push-shaped; this section reads core's earlier bus layer, compares the
two shapes, and records the one chosen, with the fill the owner asked
for.

### 16.1 Core's earlier bus layer (removed at 1075b467)

`src/bus/traits.rs`: `EventBus { publish(Arc<EventBook>) ->
PublishResult, subscribe(Box<dyn EventHandler>), start_consuming(),
create_subscriber(name, domain_filter) }`, and `EventHandler::handle(
Arc<EventBook>) -> BoxFuture<Result<(), BusError>>`: **push-shaped**, the
bus calling its handlers. `dispatch.rs` calls every handler in turn and
answers whether all succeeded (`DispatchResult::should_ack`: success or
an undecodable payload).

| Adapter | Consumed by | Acked | Checkpoint |
|---|---|---|---|
| AMQP (`amqp/mod.rs`) | `basic_consume` stream (`while let Some(delivery) = consumer.next()`), one at a time; no `basic_qos`, so prefetch unbounded | `delivery.ack()` after dispatch **whatever the handlers answered**; `reject` (no requeue) for an undecodable payload | none (the broker's) |
| Kafka (`kafka/bus.rs`) | rdkafka `StreamConsumer::stream()` (a poll loop as a stream), one at a time | `commit_message(.., Async)` after dispatch **whatever the handlers answered**, and for an undecodable payload | the group's offsets |
| NATS JetStream (`nats/consumer.rs`) | `consumer.messages()` stream, one at a time | `msg.ack()` after dispatch, whatever the answer; ack for undecodable | the consumer's ack floor |
| IPC (`ipc/client.rs`, `checkpoint/`) | a pipe reader, one book at a time, blocking | none | a file of the last sequence per (routing key, root), skipping what it covers (dedup), updated after dispatch and flushed on an interval and at EOF: the hub's mark, kept by the transport |
| channel, mock | in-process broadcast | none | none |

What it shows: every adapter was a **push consumer** (a stream the
adapter drives, calling the handler), handled one delivery at a time,
and acknowledged after the call. None honoured the handler's answer, none
bounded prefetch, none recovered a gap (IPC only skipped what its
checkpoint covered), and none ordered across partitions or consumers.
The shape is right; what it did with the answer is what the bus fixes.

### 16.2 The push-shaped transport

```rust
/// A transport runs one subscription's deliveries into a sink.
pub trait Transport: MaybeSend + MaybeSync {
    type Error;
    /// Deliver `opening`'s events into `sink` until `sink` says stop or an
    /// error: at most `opening.credit.instances()` calls of `sink.deliver`
    /// at once, and one of a stream. Each call's answer IS the
    /// acknowledgement, applied before the slot is reused.
    fn run<'a, K: Sink + 'a>(&'a self, opening: Opening<'a>, sink: &'a K)
        -> impl Future<Output = Result<(), Self::Error>> + MaybeSend + 'a;
}

/// What a transport delivers into: the hub, one per subscription.
pub trait Sink: MaybeSend + MaybeSync {
    /// One delivery: its settlement, once its turn in its stream has been
    /// handled. It may wait (the delivery stays unsettled, counting
    /// against the transport's credit, until it returns).
    fn deliver(&self, delivery: Delivery) -> impl Future<Output = Settle> + MaybeSend + '_;
    /// The transport has nothing more now (caught up). `Continue` waits on;
    /// `Stop` ends `run`.
    fn idle(&self) -> impl Future<Output = Flow> + MaybeSend + '_;
}

pub enum Flow { Continue, Stop }

/// A delivery carries no token: the transport keeps its own handle beside
/// the call, and applies the settlement the call answers.
pub struct Delivery { stream: Cover, sequence: u64, attempt: Option<u32>,
                      key: OrderingKey, body: Body }
pub enum Settle { Handled, Held { after: Option<Duration> }, DeadLettered }
```

How each fits:

- **AMQP** `basic_qos(prefetch = instances)`, `basic_consume`: each
  delivery is a `deliver` call (at most prefetch at once); `Handled`:
  `basic.ack`; `Held`: `basic.nack(requeue)` or the delay exchange;
  `DeadLettered`: `basic.ack` (the bus kept the letter). One of a stream:
  consistent-hash exchange or single-active-consumer advised; without
  them the hub's fill orders (16.4).
- **NATS JetStream** push or pull consumer, `max_ack_pending =
  instances`: each message a call; `ack`, `nak(delay)`, `term`.
- **Kafka**: the poll loop pushes each record as a call, up to the credit,
  pausing the partitions while the credit is full (`pause`/`resume`) and
  serialising each ordering key; the answers mark a `Prefix` per
  partition, committed at its contiguous prefix; `Held` routes to the
  retry topic of its delay band.
- **SQS / Pub/Sub**: the receive loop pushes each message; delete or ack,
  `ChangeMessageVisibility` or `modifyAckDeadline`.
- **The old `EventBus.subscribe(handler)`**: the same shape, the handler
  now answering a settlement instead of a bare result.
- **The store transport**: a pull feed, pumped (16.11, 1): its scan
  hands each owed sequence (a reference) within the credit gate, one of a
  stream; it applies nothing on `Handled` (the hub wrote the position),
  holds on `Held` (`Delayed` on its timer), and answers `Idle` when
  nothing is owed, waiting on the commit, its doorbell.

### 16.3 Push against pull

| | Pull (`Feed::next` + `settle`) | Push (`Transport::run` into a `Sink`) |
|---|---|---|
| **Buffering** | the hub queues deliveries it has taken (an event-carrying queue in front of the handlers, which the owner's rule forbids) | none: each unsettled delivery is held only by its own call; at most the credit in flight |
| **Backpressure** | the transport bounds what `next` hands out; the hub's queue can still grow while instances are busy | the transport cannot start a call past its credit: native prefetch, pause, `max_ack_pending`, flow control |
| **Cancellation** | dropping the serve drops the queue and the feed; unsettled tokens are redelivered | dropping `run` drops the in-flight calls; unsettled deliveries are redelivered (no ack was sent) |
| **Parking and recovery** | the hub must keep each parked delivery's token and settle it later through a separate handle | a parked delivery's call simply has not returned: no separate settle handle; its slot stays counted |
| **Request/response** | split across two calls | one call: the answer is the ack (what the owner values) |

**Can a push sink answer "park"?** Yes, by not returning yet: the
delivery stays unsettled, its slot counted, until its turn is handled
(16.4). No separate settle handle is needed. The one cost: a parked call
holds a transport slot, so a stream with many ahead-deliveries can fill
the credit while its fill runs; the fill itself runs in the first
parked call's slot (16.4), so the credit bounds the work, and the other
streams go on in the remaining slots.

### 16.4 One fill for catch-up and recovery

The owner's requirement: catch-up and recovery take the arrived
ahead-deliveries and the stream's mark, and present one ordered series
of handle calls: `mark..k` filled from the recovery source, then the
arrived items, merged in sequence order, without duplicates.

```rust
/// One stream's fill: the arrived deliveries ahead of its mark, waiting,
/// and the source of what lies between.
struct Fill {
    mark: u64,
    /// Arrived ahead of the mark, by sequence: each its body and the
    /// waiter its `deliver` call awaits (its settlement).
    waiting: BTreeMap<u64, Vec<(Body, Waiter<Settle>)>>,
    /// A call is driving the fill.
    driving: bool,
}

/// The ordered series to hand: from `mark`, each sequence's body from a
/// waiting delivery if one arrived, else from `recover` in batches of at
/// most `batch`, lazily; ends at the last waiting sequence, or at a miss.
fn fill<'a, R: Recover>(stream: &'a Cover, mark: u64, waiting: &'a Mutex<Fill>,
                        recover: &'a R, batch: usize)
    -> impl Stream<Item = Result<Next, R::Error>> + 'a;

enum Next { Hand { sequence: u64, body: Body, from: Source },  // Source::Arrived | Source::Recovered
            Missing { sequence: u64 } }
```

Step by step, in the push shape:

1. **A delivery arrives** for `(stream, k)`: its `deliver` call enters
   the stream's lane. `k < mark`: answered `Handled` at once (a
   duplicate). Otherwise it joins `waiting` at `k`.
2. **One driver.** If no call is driving the lane's fill, this call drives
   it; any other delivery of the stream arriving meanwhile only joins
   `waiting` and awaits its waiter: never a second fill. The lane owns its
   fill, which fits one in flight per stream.
3. **The driver walks the series** (`fill`): at each sequence from the
   mark, an arrived body if one waits there (the transport's copy, and
   any duplicates of it, settled together), else the next batch from
   `Recover` (`recover(stream, s, min(next waiting, s + batch), batch)`),
   held in memory one batch at a time. Each item is handed the same way,
   one handle call, its attempt the transport's count for an arrived
   item, else the hub's.
4. **After each item** the mark moves (its position written). The
   arrived deliveries at that sequence are settled through their waiters
   (`Handled`, or `DeadLettered`), and their calls return, freeing their
   slots.
5. **When the driver's own sequence is handled**, its call returns its
   settlement; if deliveries still wait ahead, the lowest waiting call
   becomes the driver.
6. **A miss** (the source has no sequence `s`): the series stops at `s`.
   The stream holds, `s` is never skipped. Every waiting call is answered
   `Held { after }` (its delivery redelivered later; the fill starts again
   then), its attempt counted; at the cap each is answered `DeadLettered`,
   its letter naming `s`, and the stream stays held.
7. **A held item** (its handler answered held): as a miss, from that
   sequence.
8. **Initial catch-up** is the same call: a subscription at its mark whose
   first delivery is ahead fills `mark..k` first. A transport with no
   delivery ahead (the store's) delivers from the mark, so nothing is
   filled; a broker's gap at the tail is the sweep's (§15.6), which enters
   the lane as an arrival with no waiter.

In the pull shape the same `Fill` runs inside the hub, but each waiting
entry holds a transport token instead of a waiter, the hub's queue holds
the deliveries `next` handed it, and each settlement is a separate
`settle(token, ..)` call. It works, but it holds events in a hub queue in
front of the handlers, and it splits each request from its answer.

### 16.5 Supporting both push and pull

The owner: push is likely the better shape, and pull must be supported
too. Four ways to have both; in every one the bound on buffering is the
credit (at most `instances` deliveries in memory, of one stream one), and
nothing is ever a second copy of the store: recovered events are read a
batch at a time as the fill walks, never accumulated.

**(a) Two transport traits, push and pull, both served by the hub.**
`PushTransport::run(opening, sink)` and `PullTransport::open -> Feed`.
- Buffering: none for push; for pull, the hub's taken-but-unhandled
  deliveries, at most the credit.
- Backpressure: push, the transport's; pull, `next` not called past the
  credit.
- Cancellation: dropping the serve; unsettled deliveries redelivered in
  both.
- Fill and parking: two code paths in the hub (a waiter per parked call
  for push, a token per parked delivery for pull), one `Fill`.
- Cost: every hub feature twice; the conformance suite twice.

**(b) One push trait; a pull transport adapted by a pump.** A
`Pumped<F: Feed>` is a `Transport` whose `run` loops: while fewer than
`credit` calls are in flight, `feed.next()`, then call `sink.deliver`
in a future of its own, and on its answer `feed.settle(token, answer)`.
- Buffering: the pump holds only the in-flight calls' tokens, at most the
  credit; `next` is not called past it. No queue.
- Backpressure: the pump's credit check before each `next`: a broker's pull
  API (JetStream pull `fetch(n)`, SQS `ReceiveMessage(max)`, Kafka `poll`)
  is asked for at most the free slots.
- Cancellation: dropping `run` drops the in-flight calls; the tokens are
  never settled, so the broker redelivers.
- Fill and parking: one path, the push one (a parked call has not
  returned; its token waits in the pump's frame).
- Cost: one adapter, written once in core, for every pull-shaped broker.

**(c) One pull trait; a push transport adapted through a bounded buffer.**
A push consumer's callbacks enqueue into a buffer of at most `credit`
entries that `next` drains; the callback waits (or the consumer pauses)
when it is full.
- Buffering: the buffer, at most the credit, plus the hub's taken
  deliveries, at most the credit again: twice the credit in memory.
- Backpressure: a full buffer pausing the push consumer; brokers whose
  push cannot pause (AMQP without prefetch, core NATS) overflow into it
  unless prefetch is set equal to the buffer.
- Cancellation: the buffer's deliveries are lost on drop and redelivered by
  the broker; a callback blocked on a full buffer must be cancelled too.
- Fill and parking: the pull path (tokens and separate settles).
- Cost: an event-carrying queue in front of the handlers, which the
  owner's earlier rule forbids, and the request split from its answer.

**(d) Demand-signalled (Reactive Streams `request(n)`).** The sink grants
the transport `n` more deliveries; the transport pushes at most that many
until granted more.
- Buffering: none beyond the granted `n`, which is the free credit.
- Backpressure: explicit demand, the sink's.
- Cancellation: `cancel()`; unsettled deliveries redelivered.
- Fill and parking: as push; demand is withheld for a slot a parked call
  holds.
- Cost: a protocol (`request`, `cancel`, `on_next`, `on_complete`) where
  (b)'s credit already is the demand: in (b) the free slots are exactly
  `request(free)`, implicit in the pump.

**Recommendation: (b).** One push-shaped `Transport` (16.2) is the hub's
only interface, and pull-shaped brokers are adapted to it once, in core, by
`Pumped<F: Feed>`, whose `Feed` is the pull shape of §14 (`next` within
credit, `settle(token, ..)`). Push brokers (AMQP `basic_consume`, a NATS push
consumer, the old `EventBus.subscribe`) implement `Transport` directly;
pull brokers (JetStream pull, SQS, Kafka's `poll`, Pub/Sub pull)
implement `PullTransport` and its `Feed`, and are pumped. The store
transport is a pull feed, pumped (16.11, 1). Buffering stays bounded by
the credit in both, the fill is one code path, and (d)'s demand is the
pump's free-slot count. **The owner chose (b).**

### 16.6 Recommendation (the shape)

**Push**: `Transport::run(opening, sink)`, `Sink::deliver(delivery) ->
Settle` (the answer is the ack), `Sink::idle() -> Flow`, the token gone
from `Delivery`, and the fill of 16.4 in the hub's lanes; pull-shaped
brokers supported through the pump of 16.5 (b), `Pumped<F: Feed>`. It matches every
bus angzarr had and plans, it needs no event-carrying queue in front of
the handlers, its backpressure is the transport's own, and parking is a
call that has not returned yet.

Built:

- **transport.rs**: `Transport::run` and `Sink`, `Flow`; `Delivery`
  without its token (`attempt: Option<u32>`); `PullTransport`, `Feed` and
  `Next` as the pull shape, served only through `Pumped<P>` (a
  `Transport`). `Settle` (with `Held { after }`), `Body`, `OrderingKey`,
  `Timer` stay.
- **pump.rs**: `Pumped<P: PullTransport>`, a runtime-agnostic loop that
  asks its feed for a delivery only while a slot is free, calls the sink
  in a future of its own, and settles each by the call's answer; a feed
  is opened per serve, so a token of an earlier serve (its epoch) is
  never settled through a later one.
- **hub.rs**: a `Sink` per subscription; each lane a mark and its fill
  (16.4) in place of the queue and parked list, at most `AHEAD` (4)
  waiting, one more answered `Held { after: None }`; `serve` runs each
  subscription's `transport.run(opening, sink)` and asks `more` when every
  run is quiet; positions (marks), attempts (Choice B), the miss hold and
  its dead letter at the cap (`Dispatch::missing`), the retry policy
  (`Hub::retrying`), `Dispatch` as before.
- **store.rs**: the existing `Feed`-shaped store transport (one in
  flight per stream, its credit gate, `Delayed` for held), its scan woken
  by the commit, wrapped by `Pumped` (16.11, 1); no push-shaped store loop
  was written.

The old adapters port as push transports: AMQP's `basic_consume` loop
(adding `basic_qos`, concurrent calls up to the credit, and acking by the
answer), Kafka's `StreamConsumer` loop (adding pause/resume, per-key
serialisation and the `Prefix` commit), NATS's `messages()` loop (adding
`max_ack_pending` and `nak`/`term`), SQS, Pub/Sub likewise; IPC's pipe
reader without its checkpoint file (the hub's marks replace it); the
channel bus as an in-process push transport for tests.

### 16.7 The hub's stores, by role, local or remote

The hub never assumes a local store. Its one `&S` today is split by role,
each injected, each local or remote on its own:

| Role | What it is | Local (code) | Remote (spec) |
|---|---|---|---|
| **event reads** | `Recover` (a stream's `from..to`, in bounded batches) and `Resolve` (the event at a sequence, for references) | `StoreRead` over the store's `EventRead` | `StoreRead` over `QueryClient: EventRead`, the `EventQueryService` client (below) |
| **positions** | each subscription's mark per stream: read (`PositionStore`, `Processed` at open) and written (`Write::positions`); a policy's outbox written with it | the store's `PositionStore` and `Outbox` | wherever the coordinator keeps its checkpoints: its own store |
| **listing and heads** | the scope's streams and each one's head: the store transport's scan, and the sweep (§15.6) | `ReadStore` (`covers`, `head`) | `EventQueryService.ListStreams` and a `GetEventBook` of the stream's tail |
| **wake** | what tells the bus something was committed | `CommitNotify`, `Watch` | none: the transport (a broker, the bus envelope) is the wake |

```rust
pub struct Hub<'h, T: Transport, P /* positions */, D: Dispatch, R /* reads */ = StoreRead<'h, P>> { .. }
impl<'h, T, P, D, R: Recover + Resolve> Hub<'h, T, P, D, R> {
    pub fn new(transport: T, store: &'h P, dispatch: D) -> Hub<'h, T, P, D>;   // reads from the same store
    pub fn reading(transport: T, positions: &'h P, dispatch: D, reads: R) -> Self;
}
```

Valid combinations: **embedded**, all local (the one store holds events,
positions and the outbox; the store transport scans it and its commits
wake it); **the distributed coordinator**, reads remote over gRPC
(`QueryClient`), positions and its outbox in its own store, a broker
transport as the wake; **a broker transport beside a local store** (a
coordinator co-located with its event store), reads local, positions
local, wake from the broker. Not valid: a store transport over a remote
store (it needs the local commit wake and a one-moment read unit), and
positions anywhere the policy's outbox cannot be written in the same
transaction (§5).

**The remote reads reuse the read store's gRPC** (spec; code later), no
new protocol: `EventQueryService` (angzarr-project's
`proto/io/angzarr/transport/distributed/v1/query.proto`), served in core
by `angzarr-coordinator-grpc` (`edge.rs`, `query.rs`), its tonic client
`event_query_service_client::EventQueryServiceClient` generated in
`angzarr-proto-transport-distributed` (used only by tests so far). The
adapters are thin:

- **Recover** `from..to`: `GetEvents(Query { cover, selection: range:
  SequenceRange { lower: from, upper: Some(min(to, from + batch)) } })`,
  its stream of books read as it comes.
- **Resolve** `s`: `GetEventBook(Query { cover, selection: sequences:
  SequenceSet { values: [s] } })`.
- **Listing** (the sweep): `ListStreams()`, filtered to the scope's
  domains; **heads**: `GetEventBook(Query { cover })`'s
  `next_sequence` (or a range from the mark with no upper, read to its
  end).

**The seam: `EventRead` over the client, recommended.** angzarr-ports'
`EventRead` (`read(stream, from, to)`, `head(stream)`, `covers(domain)`)
is exactly those three calls, and `StoreRead<S: EventRead>` already makes
`Recover` and `Resolve` of any `EventRead`. So one `QueryClient:
EventRead` adapter serves event reads, listing and heads at once, and the
hub needs no second recovery type. Not a `ReadStore`: its read unit
promises every read sees one moment, which a sequence of RPCs cannot;
the store transport needs that, the hub does not. Not `PositionStore` or
`Outbox`: positions are the coordinator's, in its own store.

Its gRPC statuses map to the hold and miss rules:

| `GetEvents` / `GetEventBook` answer | Means | The hub |
|---|---|---|
| `OK`, every sequence asked | recovered | handed in order |
| `OK`, fewer than asked, or a sequence absent inside the range | a miss at the first absent sequence | held; at the cap dead-lettered, naming it (§15.5) |
| `NOT_FOUND` (an unknown edition, a stream that does not exist) | a definite miss | as above |
| `UNAVAILABLE`, `DEADLINE_EXCEEDED`, `RESOURCE_EXHAUSTED`, a dropped stream or connection | not known | held with its delay; never counted as a miss, never a skip |
| `INVALID_ARGUMENT`, `PERMISSION_DENIED`, any other | the deployment's or the client's bug | held and reported; past the cap the subscription stops with the error (an alert, not a dead letter) |

The conformance kit runs with a recovery source separate from the
position store: its `Harness` gives the bus's reads and its positions
apart (the reference run puts the events in one in-memory store and the
positions in another, and recovers through a `Recover` over the first),
so a hub that reads positions where it should recover, or the reverse,
fails the ordering checks.

### 16.8 The rule: business logic sees a stream of events

All of this is hidden from business logic, which gets a stream of
events. Business handlers (projectors, policies, Cherenkov's runner) see
only their events, in stream order, through angzarr's component contracts
(angzarr-router's `ProjectorHandler` and `PolicyComponent`, and the
generated interfaces: `ProjectRequest { events }`, `ReactRequest {
trigger }`, `TranslateRequest`). They never see transports, tokens or
settlement; recovery or fill, or whether an event was pushed, pulled or
recovered; positions, marks, credit, attempts or retry delays; the gRPC
store client, or any store. The handler's answer (handled, or an error
classed retryable or a bug, by its status, as today) is the only thing
that flows back; the hub and the dispatch turn it into a settlement.

Checked against the code (core 099ef5ae, angzarr-embedded 8698576):

- `Item { stream, sequence, attempt, last, page }` is the hub-to-dispatch
  type, framework side. The embedded dispatch builds the business request
  from `stream` and `page` alone (`project_request` gives
  `ProjectRequest { events }`, the same book an inline projector gets;
  `react_served` gives `ReactRequest { trigger }`, as an inline policy's
  step does). `attempt` and `last` reach the dispatch only, where the
  retry policy uses them (`last`: dead-letter instead of holding); they
  are never in a request. Nothing of transport origin leaks.
- A coordinator's gRPC dispatch would call `ProjectorService.Project` and
  `PolicyService.React` with the same messages: a handler cannot tell
  whether it runs inline, on the in-process bus, or under a distributed
  coordinator. `Item.attempt` and `Item.last` stay framework-only.
- A compile-and-run check exists: angzarr-embedded's bus tests run one
  `Policy` type (`Bookkeeping`) inline in one test and on the bus in
  another, and one `ProjectorHandler` (`Worker`) registered inline and
  subscribed on the bus, unchanged
  (`a_policy_moved_from_inline_to_the_bus_keeps_its_place`,
  `a_policy_on_the_bus_steps_as_an_inline_one_and_resume_leaves_it_alone`).
  Proposed for the conformance suite: a check that the request a sink is
  handed carries only the event (the suite's `Sink` gets a `Delivery`
  of stream and sequence today; it would get the business request shape,
  and assert no field beyond it).

### 16.9 Recovery is a stream

Recovery is stream-shaped end to end, not batches: a gap of a million
events holds only what is in flight.

```rust
pub trait Recover: MaybeSend + MaybeSync {
    type Error: MaybeSend;
    type Pages<'a>: Pages<Error = Self::Error> + 'a where Self: 'a;
    /// `stream`'s events from `from` on, before `to`, in sequence order,
    /// read lazily: the next one is read when it is asked for
    /// (`Pages::next`, a stream without a `Stream` dependency).
    fn recover<'a>(&'a self, stream: &'a Cover, from: u64, to: u64) -> Self::Pages<'a>;
}
```

- **The fill pulls** the next recovered item only when it is ready to hand
  it (16.4, step 3): one item in memory, the one in its handler; the
  `limit` and the hub's recovery batch go from the trait.
- **Backpressure is the stream's own**: HTTP/2 flow control on
  `GetEvents` (server streaming, a `SequenceRange { lower: from, upper:
  Some(to) }`); a cursor or paged read for the local store
  (`StoreRead` reads a page of `EventRead::read(stream, s, Some(min(to, s +
  page)))` at a time, its page size an implementation detail).
- **Gaps inside the stream**: a stream that ends before `to`, or skips a
  sequence, is a miss at the first absent sequence (the hold rule, §15.5).
  An error mid-stream (`UNAVAILABLE`, a dropped connection) is a hold with
  its delay; the fill resumes by reopening the range **from the mark**,
  never from the original `from`, so what was handed is not handed again.
- **Cancellation**: dropping the stream cancels the call (tonic cancels the
  RPC when its response stream is dropped; the local read holds nothing
  between pages), so a fill stopped by shutdown or by its subscription
  going away leaks nothing.
- **Big events**: `GetEvents` already chunks its books (angzarr-reads'
  `Limits`: at most 1000 pages and 3 MiB a book, under a transport's 4 MiB
  message; a page larger than that travels alone, in a book of its own).
  A single page over the gRPC message limit is the claim check's: the
  distributed design carries an oversized payload as a `ClaimCheck`
  resolved before anything sees the book (distributed-transport.md §4),
  so the recovery stream yields either the page or a reference the
  hub's `Resolve` turns into it (through the payload store). Nothing else
  is chunked below a page.
- **`Resolve`** stays a single call (one event).
- **The store transport's scan** reads no ranges (it lists streams and
  heads, and delivers references), so it is unchanged; the hub's reads of
  each referenced event are single reads. Its initial catch-up of a long
  backlog is the store transport delivering from the mark, one event of a
  stream at a time, which already holds only what is in flight.

**Built** (amending §15's): `Recover::recover` returns its `Pages`;
`StoreRead` pages its reads inside them (64 a page); the hub's fill
consumes them lazily, and an error mid-way holds the stream's waiting
deliveries with their delay, the fill reopening from the mark when they
come again, so nothing is handed twice; the conformance suite recovers a
gap of 150 events within a credit of two.

### 16.10 Direct send, and republishing from a point

Two more ways for missing events to reach a hub. Both are specification;
their protos are in the Backlog (below), none committed.

**`EventStreamService.Subscribe` is outside the bus** (the owner's
ruling). The bus does not use it: not as a transport, not as a recovery
source, and its catch-up is not a sweep or an acknowledgement. A hub
recovers through `Recover` (`GetEvents` remotely, through `EventRead` over
the query client, 16.7) and is woken by its transport. Whether
`Subscribe` is kept for client-facing use, narrowed, or removed is a
Backlog question, answered from what uses it.

**1. Direct send (a send the source starts).** For a source to push to a
hub that did not ask (an operator's repair, a coordinator sending a late
consumer what it missed), the consumer's coordinator would need an
intake that takes a stream of events for a named subscription and
answers each one's settlement; `ProjectorCoordinatorService.HandleAsync`
and `PolicyCoordinatorService.Execute` take books but answer none. Its
pages would enter the hub as arrived deliveries of a push transport, so
the fill applies them in order, drops what is below the mark, recovers
what lies before them, and holds on a miss. Spec; its proto is Backlog.

**2. Republish from a point, to all consumers: decided (a), on the
aggregate's coordinator.** An operation of `CommandHandlerCoordinatorService`
(the domain's owner), generalising its post-persist publish (what it
publishes after each append) to a range: re-publish stream X (a set of
streams, or a domain, an edition) from sequence `s` (to `t`, or the head)
onto the bus, so every subscription receives those events again as
ordinary deliveries. Safe by construction: each hub settles what is below
its mark without its handler and fills what it was missing. For an
operator's repair after a broker lost messages, a consumer joining late on
a broker with short retention, or a restored store. Streamed a stream at a
time through the reads engine, within the bus's publish credit, its
progress reported per stream so a cancelled republish resumes; operator
or framework identity only, audited. It replaces the earlier draft's
separate `RepublishAdminService`. Spec; its proto is Backlog.

**angzarr-embedded's twin** would be `Kernel::republish(scope, from, to)`,
having each subscription's store transport deliver its scope's streams
again from `from`; in process it is a no-op unless a position was lost or
rewound. Not built (it is not trivial: the store transport delivers from
the stored mark, so a republish would need a transport cursor below it);
it stays specification beside the coordinator's.

**Prior art: core's `GapFiller`** (removed at 9193c819,
`src/services/gap_fill/filler.rs`): handler-relative completion of a
pushed `EventBook` against the handler's checkpoint per (domain, root),
reading what it lacked from an `EventSource`, either `LocalEventSource`
(the event book repository) or `RemoteEventSource` (the query service
over gRPC). It is `Recover` and its two placements (16.7's local and
remote reads) in an earlier form: the hub's fill completes from the mark
as `fill_if_needed` did, and `update_checkpoint` is the hub's mark.

### 16.11 Prior art, and what it changes

A survey of how others solved push and pull behind one consumer
(Axon, EventStoreDB/KurrentDB, Reactive Streams and Alpakka, the Rust
broker crates, Watermill, Benthos, NATS JetStream, Marten, Ecotone,
Eventuous, Elixir EventStore, Propulsion, Kafka Streams, Pub/Sub; its
findings marked verified, inferred or from memory) was made for this
decision; its findings are folded in here. What
it confirms:

- **(b) is the common shape.** Watermill's Router is a generic pump turning
  pull-ish subscriber channels into push calls whose return is the
  settlement; Pub/Sub's client is push to the user over pull on the wire;
  Propulsion is push into handlers with per-stream positions and hold on a
  gap. Pull is the canonical primitive for anything with a position (Axon
  streaming, ESDB catch-up, NATS pull, rdkafka, SQS, Benthos), and push
  sources become demand-driven through a bounded window (AMQP prefetch,
  NATS `MaxAckPending`, Reactive Streams `request(n)`). A pump is a
  semaphore of permits, not a Reactive Streams implementation.
- **The settlement verbs converge** on ack, redeliver after a delay, and
  terminal (NATS `Nak(d)`/`Term`, SQS visibility, ESDB `Retry`/`Park`), our
  `Handled`, `Held { after }`, `DeadLettered`.
- **Holding on a gap is safe here and not for others.** Axon and Marten
  give gaps up by timeout because a global sequence has dead numbers;
  angzarr's per-stream sequences are dense (assigned under optimistic
  concurrency), so a gap is always a missing delivery, never a missing
  event, and one store read resolves it. No gap timeout enters the hub;
  the only skip is an explicit dead letter.

What it changes in this note:

1. **The store transport is pull plus a doorbell** (Axon's
   `setOnAvailableCallback`): a `Feed` that reads from its position and is
   woken by `CommitNotify`, served through the pump like any pull broker.
   So the store's transport is the existing `Feed`-shaped one, pumped, and
   no push-shaped store loop is written (16.6 amended below).
2. **Ahead deliveries are hints and settlement obligations, never data the
   hub depends on** (Propulsion, Elixir EventStore). The fill reads the
   store's canonical copy where it reads a range anyway, and uses an
   arrived body only where no read is under way; the arrived delivery is
   then only settled.
3. **Bound the ahead deliveries, and overflow to the broker.** At most `K`
   ahead deliveries held per stream (and the credit in all); one beyond
   that is answered `Held { after }` at once, leaving the broker as the
   buffer, rather than holding a slot. `K` small (1 to 4) where the store is
   close. This replaces 16.3's "a parked call holds its slot" for all but
   `K` of them, so a stream with many ahead deliveries cannot exhaust the
   credit.
4. **Never acknowledge an ahead delivery before its sequence is at or below
   the durable mark**: acked early and then crashed, the broker forgets it,
   and nothing wakes the stream (a lost wakeup). The fill's rule (settle
   once the mark passes) already keeps this; it is stated as a rule.
5. **A hold's delay stays below the broker's delivery limit**
   (`MaxDeliver`, `maxReceiveCount`, ESDB `maxRetryCount`), so a stream
   merely blocked is not dead-lettered by the broker's policy instead of
   the hub's.
6. **gRPC `Subscribe` has no in-band ack**: an ESDB-style catch-up, it
   cannot settle a delivery. The bus does not use it (16.10); it is
   outside the bus.
7. **Settle handles carry their subscription's epoch** (Eventuous's
   resubscribe race): a settlement from an earlier serve is a no-op.
8. **The pump's permits set the broker's window**: NATS `MaxAckPending`,
   AMQP prefetch at least the permit count, or deliveries stall on the
   broker.
9. **Push transports start only when attached to a live sink** (NATS push
   consumers deliver to nobody otherwise).

**16.6 amended, and decided.** (b), with the store transport a `Feed`
(pull plus its commit doorbell) and pumped, the ahead bound `K` (`AHEAD`,
4) per stream with overflow answered `Held { after: None }`, the canonical
store copy preferred in a fill, and the epoch on settle handles (a feed
per serve). Amendments 1 to 4 and 7 are built; 5, 8 and 9 are rules for
the broker adapters (spec).

## 17. Positions are a subscription's choice: durable, or ephemeral

A subscription's **position** (the record of what its handler has handled:
one mark per stream, every sequence below it handled; the receipt the bus
keeps for each handled event) lives where the subscription says. The hub
asks a tracker for three things: a stream's mark on its first delivery
(`load`), the mark after a handler answers (`record`), and whether the
mark can be committed in the same write as a policy's outputs
(`atomic_with_outputs`).

```rust
pub trait Positions: MaybeSend + MaybeSync {
    fn atomic_with_outputs(&self) -> bool;  // a policy may be served only if true
    fn resumes(&self) -> bool;              // outlives the serve, in the store the transport reads
    fn begin(&self) {}                      // a serve begins: a tracker that does not outlive it empties
    fn load<'a>(&'a self, name: &'a str, stream: &'a Cover) -> BoxFuture<'a, Result<u64, StoreError>>;
    fn record<'a>(&'a self, name: &'a str, stream: &'a Cover, mark: u64) -> BoxFuture<'a, Result<(), StoreError>>;
}

impl<P> Subscription<P, Q> {
    pub fn positions(self, tracker: Arc<dyn Positions>) -> Self;  // its own tracker
    pub fn ephemeral(self) -> Self;                               // MemoryPositions
}
```

- **Chosen per subscription, at run time.** A subscription with no tracker
  of its own uses the hub's store (`DurablePositions`, the store's
  `PositionStore`/`Processed`: today's behaviour); `Subscription::ephemeral()`
  gives it `MemoryPositions`. One `Bus` serves both side by side.
- **Dispatch: a trait object** (`Arc<dyn Positions>`), not a type parameter
  of the hub (which would fix one kind for the whole bus) and not an enum
  of known kinds (which would need the hub changed for each new one). Its
  futures are boxed: one allocation per first delivery of a stream and per
  handled event, beside the store read each already makes. A coordinator-
  held durable tracker, a remote one, or a broker's committed offsets
  implement the trait and change nothing in the hub.
- **Durable** (`DurablePositions`): the event store's position records,
  under the subscription's name, outliving the process; `resumes` and
  `atomic_with_outputs` are true. The coordinator's `Processed` is the same
  record (decision 14.68): its tracker is `DurablePositions` over the
  coordinator's store, and its outbox (§5) is what makes a policy's
  position atomic with its outputs; the two are one implementation, not two.
- **Ephemeral** (`MemoryPositions`): in the process, empty at the start of
  every serve. Nothing is written to any store (no `Write::positions`, no row
  under the name), and the transport is told not to resume
  (`Opening::resume` false), so it starts every stream at sequence 0 even
  if rows exist under the name. Everything else is a durable projector's:
  one mark per stream, the fill, dedup, credit, retry and dead letters.
- **Projectors only.** A policy's position must commit atomically with its
  outputs (§5), which a position in memory cannot: `subscribe` refuses a
  policy whose tracker is not `atomic_with_outputs`
  (`Dispatch::non_atomic_policy`; angzarr-embedded:
  `Misconfigured::EphemeralPolicy`, `angzarr-embedded-ephemeral-policy`).
- **Delivery is at least once, and the whole history again after a
  restart**, so an ephemeral projector's handler must be idempotent. Its
  use: a read model rebuilt in memory by every process (ctxloom's
  `PendingModel`), which a shared durable name would starve (a second
  process marks an event handled before the first sees it) and a per-process
  durable name would litter (`PositionStore` has no delete).
- **From the start, not the head.** An ephemeral subscription replays from
  sequence 0, which is what a rebuilt read model needs; starting at the
  head (only what is committed from now on) is a different subscription
  (Kafka `auto.offset.reset=latest`, JetStream `DeliverNew`), recommended
  only for a handler that wants no history, and not built here.

**Distributed parity.** The semantics are a broker's own, so this is not an
embedded-only feature:

| Broker | An ephemeral subscription is |
|---|---|
| Kafka | a consumer with no committed offsets (`enable.auto.commit=false`, `auto.offset.reset=earliest`), a group id per instance; the hub's mark is the only position |
| NATS JetStream | an ephemeral consumer (no durable name), `DeliverAll`, removed by the server when its subscriber goes |
| AMQP | an exclusive auto-delete queue, declared per serve, replaying from the store (the hub's recovery fills it from the start) |
| the coordinator | `MemoryPositions` in the coordinator, a projector subscribed ephemeral |

A transport whose broker holds the cursor (Kafka offsets, a JetStream
durable) reads it only when the tracker `resumes`; an ephemeral
subscription's `Opening::resume` is false, so it starts at the beginning
whatever the broker holds.

**Conformance.** `contract::positions` (`positions_contract!`) holds any
tracker to: a stream starts at 0 and holds what is recorded; marks are per
subscription and per stream; 0 forgets; a restart resumes where `resumes`
says and starts over where it does not; `begin` empties a tracker that does
not outlive the serve; only a tracker in the store is atomic with outputs.
The bus suite adds, for an ephemeral projector: it starts at 0 each serve
and stores no row (and a new bus is handed the history again), an ephemeral
policy is refused, out-of-order deliveries are recovered, failures are held
and dead-lettered as a durable one's, and one bus serves a durable and an
ephemeral projector side by side. The existing checks run unchanged against
the durable path.

## Backlog (distributed)

Parked by the owner; no further design here.

- **`EventStreamService.Subscribe`: keep, narrow or remove**, for
  client-facing use only (the bus does not use it, 16.10); decided from
  what uses it.
- **Client-facing and internal gRPC, split**: the existing inventory
  stands as is, not extended.
- **`HandleAsync`'s wording**, as a nudge (enqueue and return), not a
  delivery with a settlement.
- **The republish RPC's proto** (16.10, 2, on
  `CommandHandlerCoordinatorService`) and **the direct-send intake's
  proto** (16.10, 1).
- **The gRPC `EventRead` adapter** over `EventQueryServiceClient` (16.7)
  and **the broker adapters** (Kafka, AMQP, JetStream, SQS, Pub/Sub: §14,
  §15.10, 16.11's rules 5, 8, 9).
