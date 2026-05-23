# Reusable submodule-protection recipes.
#
# Imported by consumers that have angzarr-project (or any other submodule)
# checked in. From the consumer's justfile:
#
#   import? 'angzarr-project/submodule.just'
#
# Provides two recipes:
#   - install-submodule-hooks: plants a pre-commit hook inside each
#     registered submodule's .git/modules/<name>/hooks/ that rejects any
#     commit attempted from inside the submodule (detached HEAD = silent
#     data loss).
#   - check-submodules-clean: refuses to proceed if any submodule has a
#     dirty working tree. Pointer-only bumps still pass.
#
# Wire into lefthook in the consumer:
#   post-checkout / post-merge -> install-submodule-hooks
#   pre-commit                 -> check-submodules-clean
# And run check-submodules-clean from CI so --no-verify can't sneak past.
#
# Both recipes are shebang recipes, so they run under bash regardless of the
# importing justfile's `set shell` value.

# Install the in-submodule pre-commit guard into every registered submodule's
# .git/modules/<name>/hooks/ directory. Idempotent. The hook body is inlined
# below — edit it here and re-run.
install-submodule-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root="$(git rev-parse --show-toplevel)"
    [ -f "${repo_root}/.gitmodules" ] || exit 0
    tmp_hook="$(mktemp)"
    trap 'rm -f "${tmp_hook}"' EXIT
    cat >"${tmp_hook}" <<'HOOK'
    #!/bin/sh
    # Auto-installed by `just install-submodule-hooks` in the parent repo.
    # Source of truth lives in angzarr-project/submodule.just — DO NOT edit
    # this copy; it will be overwritten on the next checkout/merge.
    submodule_name="$(basename "$(git rev-parse --show-toplevel)")"
    remote_url="$(git config --get remote.origin.url 2>/dev/null || echo '<unknown>')"
    cat >&2 <<EOF

    ================================================================
      REJECTED: commit attempted inside a git submodule
    ================================================================

    You are about to commit inside the '${submodule_name}' submodule.
    This checkout is a DETACHED HEAD pinned by the parent repository's
    submodule pointer. Any commit you create here is unreachable from
    any branch and CANNOT be pushed to the canonical repository — it
    will be silently discarded the next time the submodule pointer is
    updated.

    Make this change in the canonical location instead:
      ${remote_url}

    Typical workflow:
      1. Clone '${submodule_name}' as a standalone repo (outside this
         parent checkout).
      2. Create a branch, commit, push, open a PR there.
      3. Once merged, bump the submodule pointer in this parent repo
         using the standard bumper tooling.

    Do NOT bypass this check. The check exists because submodule
    commits are silent data loss; --no-verify, LEFTHOOK=0, deleting
    this hook, or any other workaround will lose your work. If you
    believe this hook is firing in error, stop and ask in #angzarr
    before bypassing.

    ================================================================
    EOF
    exit 1
    HOOK
    chmod +x "${tmp_hook}"
    export ANGZARR_HOOK_SRC="${tmp_hook}"
    git submodule --quiet foreach --recursive '
        gd="$(git rev-parse --git-dir)"
        case "${gd}" in /*) abs="${gd}" ;; *) abs="$(pwd)/${gd}" ;; esac
        mkdir -p "${abs}/hooks"
        cp "${ANGZARR_HOOK_SRC}" "${abs}/hooks/pre-commit"
        chmod +x "${abs}/hooks/pre-commit"
        echo "installed pre-commit guard in ${displaypath}"
    '

# Refuse to proceed if any submodule has a dirty working tree. Pointer-only
# bumps (gitlink SHA changes with a clean submodule checkout) pass.
check-submodules-clean:
    #!/usr/bin/env bash
    set -euo pipefail
    repo_root="$(git rev-parse --show-toplevel)"
    [ -f "${repo_root}/.gitmodules" ] || exit 0
    dirty=()
    while IFS= read -r sm_path; do
        [ -n "${sm_path}" ] || continue
        [ -d "${repo_root}/${sm_path}" ] || continue
        status="$(git -C "${repo_root}/${sm_path}" status --porcelain 2>/dev/null || true)"
        if [ -n "${status}" ]; then
            dirty+=("${sm_path}")
        fi
    done < <(git config -f "${repo_root}/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
    if [ "${#dirty[@]}" -eq 0 ]; then
        exit 0
    fi
    {
        echo
        echo "================================================================"
        echo "  REJECTED: parent commit blocked by dirty submodule(s)"
        echo "================================================================"
        echo
        echo "The following submodule(s) have uncommitted changes or untracked"
        echo "files in their working tree. These are git submodules — fix"
        echo "the changes in the canonical origin repo (URL listed), then"
        echo "bump the submodule pointer here:"
        echo
        for sm in "${dirty[@]}"; do
            url="$(git -C "${repo_root}/${sm}" config --get remote.origin.url 2>/dev/null || echo '<unknown>')"
            echo "  - ${sm}"
            echo "      origin: ${url}"
        done
        echo
        echo "A submodule checkout is a DETACHED HEAD pinned by this repo. Any"
        echo "edits made inside it cannot be pushed to the canonical repository"
        echo "and will be silently lost on the next pointer update."
        echo
        echo "Make these changes in the canonical location instead. For each"
        echo "listed submodule:"
        echo "  1. Clone it as a standalone repo."
        echo "  2. Commit + push your change there, open a PR."
        echo "  3. After it merges, bump the submodule pointer here via the"
        echo "     standard bumper tooling."
        echo
        echo "To discard the local edits and unblock this commit:"
        echo "  git -C <submodule> checkout -- ."
        echo "  git -C <submodule> clean -fdx     # only if you also have untracked files"
        echo
        echo "Do NOT bypass this check with --no-verify, LEFTHOOK=0, or by"
        echo "removing the hook. The same check runs in CI and will fail your PR."
        echo
        echo "================================================================"
    } >&2
    exit 1
