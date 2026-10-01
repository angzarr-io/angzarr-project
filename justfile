# angzarr-project: docs site (Astro/Starlight) + proto definitions + features

SITE := "site"

# Run dev server for the docs site
dev:
    cd {{SITE}} && npm run dev

# Build the docs site to site/dist
build:
    cd {{SITE}} && npm run build

# Preview the built site locally
preview:
    cd {{SITE}} && npm run preview

# Install site dependencies
install:
    cd {{SITE}} && npm install

# Vendor sibling repos used by remark-code-region (Python only for now)
vendor:
    mkdir -p vendor/examples vendor/client
    [ -d vendor/examples/python ] || git clone --depth=1 git@github.com:angzarr-io/angzarr-examples-python.git vendor/examples/python
    [ -d vendor/client/python ]   || git clone --depth=1 git@github.com:angzarr-io/angzarr-client-python.git   vendor/client/python

# Clean build artifacts
clean:
    rm -rf {{SITE}}/dist {{SITE}}/.astro

# Verify every poker/acceptance scenario is governed by a # Rule: citation
check-rules:
    python3 features/example/check_rule_citations.py

# ---------------------------------------------------------------------------
# Contract gates (proto + feature specs). buf runs in a pinned container so
# the host needs only docker; CI calls these recipes and nothing else.
# ---------------------------------------------------------------------------

BUF_IMAGE := "bufbuild/buf:1.47.2"

# Branch/ref the optional proto-breaking check compares against.
BREAKING_AGAINST := env_var_or_default("BREAKING_AGAINST", "origin/main")

# Lint the protos under proto/ with the repo's buf.yaml
proto-lint:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    docker run --rm -e BUF_CACHE_DIR=/tmp/buf-cache \
        -v "$root:$root:ro" -w "$root/proto" {{BUF_IMAGE}} lint

# Optional manual check (not part of `contracts` or CI): report wire/JSON
# breakage against BREAKING_AGAINST via buf's git input. Stored data is wiped
# across schema changes during active development, so breakage is allowed.
proto-breaking:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    # The common git dir is the real repository even from a linked
    # worktree; mount it at the same path so buf's git input resolves.
    gitdir="$(git rev-parse --path-format=absolute --git-common-dir)"
    docker run --rm -e BUF_CACHE_DIR=/tmp/buf-cache \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0="*" \
        -v "$root:$root:ro" -v "$gitdir:$gitdir:ro" -w "$root" {{BUF_IMAGE}} \
        breaking proto --against "$gitdir#ref={{BREAKING_AGAINST}},subdir=proto"

# Every scenario carries exactly one unique @<TIER>-NNNN tag
check-feature-ids *dirs="features/client features/coordinator-contract parity":
    python3 scripts/check_feature_ids.py {{dirs}}

# Required contract gates (proto-breaking is optional and run by hand)
contracts: proto-lint test-check-feature-ids check-feature-ids

# Unit tests for the scenario-ID checker
test-check-feature-ids:
    python3 -m unittest scripts/test_check_feature_ids.py
