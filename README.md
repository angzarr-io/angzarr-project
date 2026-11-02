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

`dev` and `build` first run `just vendor` (shallow-clones the sibling repos referenced by code-region embeds into `vendor/`) and `just proto-docs` (renders `proto/` with a pinned protoc-gen-doc container into `site/src/content/docs/reference/proto-api.md`, which is generated and not committed). The site embeds code via the custom `remark-code-region` plugin (see `site/src/plugins/remark-code-region.mjs`); a missing file or region fails the build unless `DOCS_LENIENT=1` is set.

## License

Everything under `proto/` except the vendored `proto/google/` and `proto/sererr/` trees: Licensed under either of Apache License 2.0 or BSD 3-Clause, at your option ([proto/LICENSE-APACHE](proto/LICENSE-APACHE), [proto/LICENSE-BSD](proto/LICENSE-BSD)).
The vendored third-party protos, `proto/google/` (Apache-2.0) and `proto/sererr/` (sererr's BSD-3-Clause or MIT), keep their own licences.
Everything else is AGPL-3.0; see [LICENSE](LICENSE).

Author: Benjamin Abbitt

Commercial licensing: the AGPL-3.0 parts of this project (not the
dual-licensed protos above) are also available under a commercial
licence. The author is open to it; contact Benjamin Abbitt.
