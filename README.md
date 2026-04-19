# angzarr-project

Core resources for the [Angzarr](https://angzarr.io) polyglot event-sourcing framework:

- **`site/`** — Documentation site (Astro + Starlight), deployed to [angzarr.io](https://angzarr.io)
- **`proto/`** — Canonical Protocol Buffer definitions (single source of truth)
- **`features/`** — Cucumber/Gherkin specs shared across language implementations

## Development

```sh
just vendor    # clone sibling repos referenced by code-region embeds
just install   # install site dependencies
just dev       # run the docs site locally
```

The site embeds code from `vendor/` via the custom `remark-code-region` plugin (see `site/src/plugins/remark-code-region.mjs`).

## License

AGPL-3.0 — see [LICENSE](LICENSE).
