# angzarr-project: docs site (Astro/Starlight) + proto definitions + features

SITE := "site"

# Shared hook recipes (scan-secrets, submodule guards) consumed by every repo.
import 'submodule.just'

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

# Verify every blackjack rule-tier and acceptance scenario cites a catalogued house rule
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
    # buf lints an empty module cleanly, so a mount that comes up empty
    # (e.g. a daemon that cannot see this path) would pass vacuously: fail
    # unless buf sees at least one .proto file, in the same container run.
    docker run --rm -e BUF_CACHE_DIR=/tmp/buf-cache --entrypoint sh \
        -v "$root:$root:ro" -w "$root/proto" {{BUF_IMAGE}} -c \
        'files=$(buf ls-files 2>&1) && [ -n "$files" ] || { echo "proto-lint: buf sees no .proto files under $PWD: $files" >&2; exit 1; }; buf lint'

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
check-feature-ids *dirs="features/client features/coordinator-contract features/handler-contract features/codegen parity features/example/blackjack features/example/blackjack-framework features/example/blackjack-acceptance":
    python3 scripts/check_feature_ids.py {{dirs}}

GHERKIN_IMAGE := "docker.io/library/python:3.12-slim@sha256:f77ac9e44ae96ef2c90b8053ea08c31f8be030f824196b0ae4db6d462c84e51f"
GHERKIN_VERSION := "42.0.1"

# Every feature file parses with the official Cucumber Gherkin parser
check-gherkin *dirs="features parity":
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    docker run --rm -v "$root:$root:ro" -w "$root" {{GHERKIN_IMAGE}} sh -c \
        "pip install --quiet --disable-pip-version-check --root-user-action=ignore gherkin-official=={{GHERKIN_VERSION}} && python scripts/check_gherkin_parse.py {{dirs}}"

# Required contract gates (proto-breaking is optional and run by hand)
contracts: proto-lint test-check-feature-ids check-feature-ids check-gherkin check-rules check-retired-reasons

# No retired reason key is named in the features, the protos or the site
# docs (the generated Proto API page aside). The retired keys are the names reasons.proto reserves (decision
# 14.44); protoc refuses them as values, this catches them in prose.
check-retired-reasons:
    #!/usr/bin/env bash
    set -euo pipefail
    keys=$(grep -E '^[[:space:]]*reserved[[:space:]]+"' proto/io/angzarr/v1/reasons.proto \
        | grep -oE '"[A-Z0-9_]+"' | tr -d '"' | sort -u | paste -sd'|')
    [ -n "$keys" ] || { echo "FAIL check-retired-reasons: reasons.proto reserves no name" >&2; exit 1; }
    rc=0
    grep -rnwE "($keys)" features proto site/src/content/docs --exclude=reasons.proto --exclude=proto-api.md || rc=$?
    case "$rc" in
        0) echo "FAIL check-retired-reasons: the lines above name a retired reason key" >&2; exit 1 ;;
        1) echo "ok   check-retired-reasons ($(tr '|' '\n' <<< "$keys" | wc -l) retired keys, none named)" ;;
        *) exit "$rc" ;;
    esac

# Unit tests for the scenario-ID checker
test-check-feature-ids:
    python3 -m unittest scripts/test_check_feature_ids.py

# lefthook's pre-push step, given the remote's name and git's pushed refs on
# stdin: mutation-test what each pushed ref changes in rust/angzarr-ports
# (`mutation-diff` there, judged by its MUTATION_THRESHOLD), in that commit's
# tree checked out alone (rust/angzarr-ports/target/push-tree), so an
# unpushed edit cannot pass or fail it. The diff's base is the merge base of
# the commit pushed and the remote's current tip of that ref (a fast-forward's
# base is that tip); for a new ref, or a tip not fetched here, the merge base
# with the remote's default branch (<remote>/HEAD, else main). A deleted ref,
# and a ref that changes no Rust there, pass at once. rust/angzarr-proto is
# generated code (build.rs), not mutated.
#
# Red tests (cargo-mutants' baseline fails, exit 4) cannot be judged: pushed
# to a branch other than the default one they pass, with a warning that the
# branch cannot merge until they pass; pushed to the default branch they are
# refused. `lefthook` is what lefthook.yml passes to stop lefthook skipping
# it, and is ignored.
[positional-arguments]
mutation-push remote *lefthook:
    #!/usr/bin/env bash
    set -euo pipefail
    top='{{justfile_directory()}}'
    crate=rust/angzarr-ports
    remote=$1
    default=$(git -C "$top" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null) && default=${default#"$remote"/} || default=main
    tree="$top/$crate/target/push-tree"
    mkdir -p "$top/$crate/target"
    exec 9> "$top/$crate/target/.push-tree.lock"
    flock 9
    # git exports repository-locating variables (GIT_DIR, ...) into a hook;
    # with them, a git -C the push tree would act on this checkout instead,
    # and so would git run by a test there.
    unset $(git rev-parse --local-env-vars)
    pushed=0
    while read -r local_ref local_sha remote_ref remote_sha; do
        [ -n "${local_sha:-}" ] || continue
        [ "${local_sha//0/}" = "" ] && continue  # a deletion
        pushed=1
        target=${remote_ref#refs/heads/}
        base=
        if [ -n "${remote_sha//0/}" ] && git -C "$top" cat-file -e "$remote_sha^{commit}" 2>/dev/null; then
            base=$(git -C "$top" merge-base "$remote_sha" "$local_sha") || base=
        fi
        if [ -z "$base" ]; then
            for ref in "refs/remotes/$remote/$default" "refs/heads/$default"; do
                if git -C "$top" rev-parse --verify --quiet "$ref^{commit}" > /dev/null; then
                    base=$(git -C "$top" merge-base "$ref" "$local_sha") && break
                fi
            done
        fi
        if [ -z "$base" ]; then
            echo "FAIL mutation-push: $local_ref shares no history with $remote's tip or with $default" >&2
            exit 1
        fi
        range="$(git -C "$top" rev-parse --short "$base")..$(git -C "$top" rev-parse --short "$local_sha") to $remote/$target"
        if [ -z "$(git -C "$top" diff --name-only "$base" "$local_sha" -- "$crate/*.rs")" ]; then
            echo "ok   mutation-push ($range: no mutants, the push changes no Rust in $crate)"
            continue
        fi
        # The pushed commit's tree, alone, no hook run for it.
        if ! git -C "$tree" rev-parse --git-dir > /dev/null 2>&1; then
            rm -rf "$tree"
            git -C "$top" worktree prune
            git -c core.hooksPath=/dev/null -C "$top" worktree add --quiet --detach --no-checkout "$tree" "$local_sha"
        fi
        git -c core.hooksPath=/dev/null -C "$tree" checkout --quiet --detach --force "$local_sha"
        git -C "$tree" clean -fdq
        mkdir -p "$tree/$crate/target"
        git -C "$top" diff --relative="$crate" --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ \
            "$base" "$local_sha" -- "$crate/*.rs" > "$tree/$crate/target/push.patch"
        rc=0
        CARGO_TARGET_DIR="$top/$crate/target/push" just --justfile "$tree/$crate/justfile" mutation-diff target/push.patch 9>&- || rc=$?
        case "$rc" in
            0) ;;
            4)
                if [ "$remote_ref" != "refs/heads/$default" ]; then
                    echo "RED  mutation-push: $range not judged, the tests are red; allowed off $default, which $target cannot merge into until they pass"
                else
                    echo "FAIL mutation-push: $range: red tests cannot be pushed to $remote/$target" >&2
                    exit 1
                fi ;;
            *) exit "$rc" ;;
        esac
    done
    [ "$pushed" = 1 ] || echo "ok   mutation-push (no commit pushed: nothing to mutate)"
