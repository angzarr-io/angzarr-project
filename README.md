# Angzarr Project

Core project resources for [Angzarr](https://github.com/angzarr-io/angzarr) - a polyglot Event Sourcing & CQRS framework.

## Contents

- **Documentation** - Docusaurus site published to https://angzarr.io
- **Proto definitions** - Shared protobuf definitions for examples

## Documentation

**Live site:** https://angzarr.io

Built using [Docusaurus](https://docusaurus.io/).

### Local Development

```bash
npm install
npm start
```

Starts a local development server at `http://localhost:3000`.

### Build

```bash
npm run build
```

Generates static content into `build/` for deployment.

### Deployment

Documentation is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to `main`.

## Proto Definitions

The `proto/` directory contains shared protobuf definitions used by example implementations across all languages.

## License

AGPL-3.0
