---
title: Upcasting
---
# Upcasting

Transform old event versions to the current version at read time. Upcasting enables gradual schema migration without rewriting historical events.

## How It Works

```mermaid
flowchart LR
    ES["Event Store<br/>(v1 events)"] -->|"OrderCreatedV1<br/>{ item: 'X' }"| U[Upcaster Service]
    U -->|"OrderCreatedV3<br/>{ items: ['X'], currency: 'USD' }"| A["Aggregate<br/>(expects v3)"]
```

## When to Use

- Adding required fields with defaults
- Renaming fields
- Restructuring nested objects
- Splitting/merging event types

## Upcaster Chain

Events may go through multiple transformations:

```mermaid
flowchart LR
    V1 --> V2
    V2 --> V3["V3 (current)"]
```

Each upcaster handles one version transition.

## In Angzarr

The `UpcasterService` gRPC service handles version transformation:

```protobuf
service UpcasterService {
  rpc Upcast(UpcasterRequest) returns (UpcasterResponse);
}
```

## Alternative: Event Versioning

Instead of upcasting, you can:
- Store multiple event versions
- Have aggregates handle multiple versions

Upcasting is preferred for cleaner aggregate code.
