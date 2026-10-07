# angzarr-project

Core resources for the [Angzarr](https://angzarr.io) polyglot event-sourcing framework:

- **`site/`** — Documentation site (Astro + Starlight), deployed to [angzarr.io](https://angzarr.io)
- **`proto/`** — Canonical Protocol Buffer definitions (single source of truth)
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

AGPL-3.0 — see [LICENSE](LICENSE).
