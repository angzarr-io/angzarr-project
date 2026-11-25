# angzarr-project

Core resources for the [Angzarr](https://angzarr.io) polyglot event-sourcing framework:

- **`site/`** — Documentation site (Astro + Starlight), deployed to [angzarr.io](https://angzarr.io)
- **`proto/`** — Canonical Protocol Buffer definitions (single source of truth), in four packages (decision 14.64):
  - `io/angzarr/v1` — core: messages only (books, pages, covers, snapshots, descriptors, options, the router's and kernel's reason keys, dead letters, editions); imports nothing else of angzarr's and no sererr;
  - `io/angzarr/component/v1` — the component contract: the handler-side services (`CommandHandlerService`, `PolicyService`, `ProjectorService`, `UpcasterService`, `ComponentService`);
  - `io/angzarr/transport/embedded/v1` — the local-process transport: the child launch protocol's constants and its reason keys;
  - `io/angzarr/transport/distributed/v1` — the distributed transport: the coordinator, query, stream, edition-admin and DLQ-admin services, the bus envelope and claim check, the dead-letter envelope, CloudEvents, and its reason keys.

  Each transport imports only component and core, never the other transport.
- **`features/`** — Cucumber/Gherkin specs shared across language implementations

## Development

```sh
just install     # install site dependencies
just dev         # run the docs site locally
just build       # strict build to site/dist
just proto-docs  # regenerate the Proto API reference page only
```

`dev` and `build` first run `just vendor` (fetches the example repositories referenced by code-region embeds into `vendor/examples/`, each pinned to a full commit in the justfile (`EXAMPLES_PINS`; embeds name a `// docs:start:NAME` region or a `// region NAME` one)) and `just proto-docs` (renders `proto/` with a pinned protoc-gen-doc container into `site/src/content/docs/reference/proto-api.md`, which is generated and not committed). The site embeds code via the custom `remark-code-region` plugin (see `site/src/plugins/remark-code-region.mjs`); a missing file or region fails the build unless `DOCS_LENIENT=1` is set.

## License

Licensed under either of Apache License 2.0 or BSD 3-Clause, at your option ([LICENSE-APACHE](LICENSE-APACHE), [LICENSE-BSD](LICENSE-BSD)); SPDX: `Apache-2.0 OR BSD-3-Clause`. `proto/` carries identical copies ([proto/LICENSE-APACHE](proto/LICENSE-APACHE), [proto/LICENSE-BSD](proto/LICENSE-BSD)) so the buf module is self-contained.
The vendored third-party protos, `proto/google/` (Apache-2.0), `proto/sererr/` (sererr's BSD-3-Clause or MIT) and `proto/io/cloudevents/` (CloudEvents Authors, Apache-2.0), keep their own licences.

Author: Benjamin Abbitt

## As a cargo package

The repository root is also a cargo package, `angzarr-project` (Rust path
`angzarr_project`), so Rust dependents take the spec by git revision and
override it with `[patch]`. It has no build script and no dependencies; it
names the directories:

```rust
angzarr_project::proto_dir();    // <checkout>/proto
angzarr_project::features_dir(); // <checkout>/features
```

`PROTO_DIR` and `FEATURES_DIR` are the same paths as `&str` constants, for
`concat!` and `include_str!`.
