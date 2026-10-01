# angzarr-project: docs site (Astro/Starlight) + proto definitions + features

SITE := "site"

# Run dev server for the docs site
dev: vendor proto-docs
    cd {{SITE}} && npm run dev

# Build the docs site to site/dist. Code snippets resolve strictly: a
# missing file or region fails the build.
build: vendor proto-docs
    cd {{SITE}} && npm run build

# Install exact site dependencies, then build (what CI runs)
site-ci: install build

# Preview the built site locally
preview:
    cd {{SITE}} && npm run preview

# Install site dependencies from the lockfile
install:
    cd {{SITE}} && npm ci

# Shallow-clone the sibling repos that remark-code-region reads snippets from
vendor:
    mkdir -p vendor/examples vendor/client
    [ -d vendor/examples/python ] || git clone --depth=1 https://github.com/angzarr-io/angzarr-examples-python.git vendor/examples/python
    [ -d vendor/client/python ]   || git clone --depth=1 https://github.com/angzarr-io/angzarr-client-python.git   vendor/client/python

# Clean build artifacts
clean:
    rm -rf {{SITE}}/dist {{SITE}}/.astro {{PROTO_DOCS_OUT}}

# ---------------------------------------------------------------------------
# Proto API reference: protoc-gen-doc renders the framework protos to a
# Starlight page under Reference. The page is generated, not committed.
# ---------------------------------------------------------------------------

PROTOC_GEN_DOC_IMAGE := "docker.io/pseudomuto/protoc-gen-doc:1.5.1@sha256:779263a6dc01fbe375298c4e556d784640539e7b2bd433a50588285da88b74d5"
PROTO_DOCS_OUT := "site/src/content/docs/reference/proto-api.md"

# Generate the Proto API reference page from proto/ (framework + sererr; examples excluded)
proto-docs:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    protos=$(cd "$root/proto" && find io/angzarr sererr -name '*.proto' ! -path 'io/angzarr/examples/*' | sort)
    docker run --rm -v "$root/proto:/protos:ro" -v "$tmp:/out" {{PROTOC_GEN_DOC_IMAGE}} \
        --doc_opt=markdown,proto-api.md $protos
    {
        printf -- '---\ntitle: Proto API\ndescription: Generated reference for the Angzarr protobuf API.\n---\n\n'
        # protoc-gen-doc emits its own H1; the frontmatter title replaces it.
        sed '0,/^# /{/^# /d}' "$tmp/proto-api.md"
    } > "$root/{{PROTO_DOCS_OUT}}"
    echo "wrote {{PROTO_DOCS_OUT}}"

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
