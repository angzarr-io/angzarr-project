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

# The spec draft every wire change lands on, and the line `proto-breaking`
# guards: bump it with the draft.
DRAFT_BRANCH := "spec/20261019-draft"

# A ref to compare against instead of the merge base with the draft (a
# manual check against some other line); empty in every gate.
BREAKING_AGAINST := env_var_or_default("BREAKING_AGAINST", "")

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

# Wire and JSON compatibility (decision 14.54; buf.yaml's WIRE_JSON rules):
# the protos at `ref` (a commit; empty means the working tree) against the
# merge base of that commit (HEAD for the working tree) with `base` (the
# draft), so a branch is held only to what it changed, never to what the
# draft gained after it forked. A removed field, value or message needs a
# `reserved` statement; an incompatible change needs a new message
# version and an upcaster. Run by `contracts`, CI and the pre-push hook.
proto-breaking ref="" base=("origin/" + DRAFT_BRANCH):
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    # The common git dir is the real repository even from a linked
    # worktree; mount it at the same path so buf's git input resolves.
    gitdir="$(git rev-parse --path-format=absolute --git-common-dir)"
    ref='{{ref}}'
    against='{{BREAKING_AGAINST}}'
    if [ -z "$against" ]; then
        if ! git rev-parse --verify --quiet '{{base}}^{commit}' > /dev/null; then
            echo "proto-breaking: no {{base}} here to compare against (git fetch it)" >&2
            exit 1
        fi
        against=$(git merge-base "${ref:-HEAD}" '{{base}}')
    else
        against=$(git rev-parse --verify "$against^{commit}")
    fi
    if [ -n "$ref" ]; then
        input="$gitdir#ref=$(git rev-parse --verify "$ref^{commit}"),subdir=proto"
    else
        input=proto
    fi
    docker run --rm -e BUF_CACHE_DIR=/tmp/buf-cache \
        -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0="*" \
        -v "$root:$root:ro" -v "$gitdir:$gitdir:ro" -w "$root" {{BUF_IMAGE}} \
        breaking "$input" --against "$gitdir#ref=$against,subdir=proto"
    echo "ok   proto-breaking (${ref:-the working tree} against $(git rev-parse --short "$against"))"

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

# Required contract gates
contracts: proto-lint proto-breaking test-check-feature-ids check-feature-ids check-gherkin check-rules check-reason-names test-check-reason-keys check-reason-keys

# The features, the protos and the site docs (the generated Proto API page
# aside) name no retired reason key, bare or prefixed, and no live key
# without its enum's prefix (decision 14.44). reasons.proto is the list:
# protoc refuses a reserved name as a value, this catches names in prose.
check-reason-names:
    #!/usr/bin/env bash
    set -euo pipefail
    proto=proto/io/angzarr/v1/reasons.proto
    prefixes='(ROUTER|HOST|COORDINATOR)_REASON_'
    # A reserved name sits on a line of its own in a `reserved` list.
    retired=$(grep -E "^[[:space:]]+\"${prefixes}[A-Z0-9_]+\"[,;]$" "$proto" | tr -d ' ",;' \
        | sed -E "s/^${prefixes}//" | sort -u | paste -sd'|')
    live=$(grep -oE "^[[:space:]]+${prefixes}[A-Z0-9_]+ = [1-9]" "$proto" \
        | sed -E "s/^[[:space:]]+${prefixes}//; s/ = .*//" | sort -u | paste -sd'|')
    [ -n "$retired" ] && [ -n "$live" ] || { echo "FAIL check-reason-names: no keys read from $proto" >&2; exit 1; }
    scan() { grep -rnwE "$1" features proto site/src/content/docs --exclude=reasons.proto --exclude=proto-api.md; }
    failed=0
    rc=0; scan "(${prefixes})?(${retired})" || rc=$?
    case "$rc" in 0) echo "FAIL check-reason-names: the lines above name a retired reason key" >&2; failed=1 ;; 1) ;; *) exit "$rc" ;; esac
    rc=0; scan "(${live})" || rc=$?
    case "$rc" in 0) echo "FAIL check-reason-names: the lines above name a reason key without its enum's prefix" >&2; failed=1 ;; 1) ;; *) exit "$rc" ;; esac
    [ "$failed" = 0 ] || exit 1
    echo "ok   check-reason-names ($(tr '|' '\n' <<< "$live" | wc -l) live keys prefixed, $(tr '|' '\n' <<< "$retired" | wc -l) retired keys unnamed)"

# Unit tests for the scenario-ID checker
test-check-feature-ids:
    python3 -m unittest scripts/test_check_feature_ids.py

# reasons.proto's keys keep decision 14.44's rules (every key carries its
# enum's prefix, every enum reserves every retired key), read from the
# descriptor buf builds in its pinned container. The Rust crates' own
# reason tests (generated code) live with angzarr-proto in angzarr-core.
check-reason-keys:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(git rev-parse --show-toplevel)"
    docker run --rm -e BUF_CACHE_DIR=/tmp/buf-cache \
        -v "$root:$root:ro" -w "$root/proto" {{BUF_IMAGE}} \
        build -o '-#format=json' --path io/angzarr/v1/reasons.proto \
        | python3 "$root/scripts/check_reason_keys.py" -

# Unit tests for the reason-key checker
test-check-reason-keys:
    python3 -m unittest scripts/test_check_reason_keys.py

# Every test the repository has: the scenario-ID and reason-key checkers'
# unit tests. What `push-check` runs. (The Rust crates moved to
# angzarr-core; their tests run there.)
test: test-check-feature-ids test-check-reason-keys

# The branches red tests never reach: the remote's default branch, and these
# (bash globs): the dated spec drafts that land on it whole.
PROTECTED_BRANCHES := "spec/*-draft"

# lefthook's pre-push step, given the remote's name and git's pushed refs on
# stdin: every test (`just test`), in each pushed commit's tree checked out
# alone (target/push-tree), so an unpushed edit cannot pass or fail it. No
# mutation: no git hook runs it. The range reported runs from the merge base
# of the commit pushed and the remote's current tip of that ref (a
# fast-forward's base is that tip); for a new ref, or a tip not fetched here,
# the merge base with the remote's default branch (<remote>/HEAD, else main).
# A deleted ref passes at once. The log is target/logs/push-tests.log. Each
# pushed commit is also held to `proto-breaking` against its merge base with
# the remote's draft (DRAFT_BRANCH), under the same red-on-a-branch rule; its
# log is target/logs/push-breaking.log.
#
# Red tests are allowed on a branch and kept out of the protected ones (the
# default branch and PROTECTED_BRANCHES): pushed to another branch, failing
# tests pass with a warning that the branch cannot merge until they pass;
# pushed to a protected branch they are refused. `lefthook` is what
# lefthook.yml passes to stop lefthook skipping it, and is ignored. To check
# a push to main by hand without pushing:
#
#     echo "refs/heads/B $(git rev-parse HEAD) refs/heads/main 0" | just push-check origin
[positional-arguments]
push-check remote *lefthook:
    #!/usr/bin/env bash
    set -euo pipefail
    top='{{justfile_directory()}}'
    remote=$1
    default=$(git -C "$top" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null) && default=${default#"$remote"/} || default=main
    read -ra protected <<< "$default {{PROTECTED_BRANCHES}}"
    tree="$top/target/push-tree"
    mkdir -p "$top/target/logs"
    log="$top/target/logs/push-tests.log"
    blog="$top/target/logs/push-breaking.log"
    exec 9> "$top/target/.push-tree.lock"
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
        guarded=
        for pattern in "${protected[@]}"; do
            [[ $remote_ref == refs/heads/$pattern ]] && guarded=1
        done
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
            echo "FAIL push-check: $local_ref shares no history with $remote's tip or with $default" >&2
            exit 1
        fi
        range="$(git -C "$top" rev-parse --short "$base")..$(git -C "$top" rev-parse --short "$local_sha") to $remote/$target"
        # The pushed commit's tree, alone, no hook run for it.
        if ! git -C "$tree" rev-parse --git-dir > /dev/null 2>&1; then
            rm -rf "$tree"
            git -C "$top" worktree prune
            git -c core.hooksPath=/dev/null -C "$top" worktree add --quiet --detach --no-checkout "$tree" "$local_sha"
        fi
        git -c core.hooksPath=/dev/null -C "$tree" checkout --quiet --detach --force "$local_sha"
        git -C "$tree" clean -fdq
        rc=0
        (cd "$tree" && just --justfile "$tree/justfile" test) > "$log" 2>&1 9>&- || rc=$?
        if [ "$rc" -ne 0 ]; then
            if [ -z "$guarded" ]; then
                echo "RED  push-check: $range: the tests fail (target/logs/push-tests.log); allowed off ${protected[*]}, which $target cannot merge into until they pass"
                continue
            fi
            echo "FAIL push-check: $range: the tests fail, and $target takes no red tests (full log: target/logs/push-tests.log)" >&2
            grep -E '^(test .* FAILED|failures:|FAIL:|ERROR:|error(\[|:))' "$log" | head -20 >&2 || true
            exit 1
        fi
        echo "ok   push-check ($range): tests pass"
        # Wire compatibility (decision 14.54): the pushed commit's protos
        # against its merge base with the remote's draft, held to the same
        # rule as the tests.
        brc=0
        (cd "$top" && just --justfile "$top/justfile" proto-breaking "$local_sha" "$remote/{{DRAFT_BRANCH}}") > "$blog" 2>&1 9>&- || brc=$?
        if [ "$brc" -ne 0 ]; then
            if [ -z "$guarded" ]; then
                echo "RED  push-check: $range: buf breaking fails (target/logs/push-breaking.log); allowed off ${protected[*]}, which $target cannot merge into until it passes"
                continue
            fi
            echo "FAIL push-check: $range: buf breaking fails, and $target takes no wire break (full log: target/logs/push-breaking.log)" >&2
            tail -20 "$blog" >&2 || true
            exit 1
        fi
        echo "ok   push-check ($range): buf breaking passes"
    done
    [ "$pushed" = 1 ] || echo "ok   push-check (no commit pushed: nothing to test)"
