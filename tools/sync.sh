#!/bin/sh
# sync.sh — land your commits on origin/master without hand-resolving the board.
#
# Why this exists: BOARD.md is GENERATED, so any two agents that both touched
# tickets conflict on it every single time (four times in one afternoon on
# 2026-07-31). The resolution is always identical and always mechanical —
# discard both sides, regenerate from the tickets, continue. Doing that by hand
# is pure tax, and doing it wrong (merging the two halves) produces a board that
# matches neither box.
#
# Also fixes the quieter one: a background `git fetch` racing a foreground
# `git pull` corrupts FETCH_HEAD and yields "Cannot rebase onto multiple
# branches". We always fetch with an explicit refspec and never rely on
# FETCH_HEAD.
#
# Usage:
#   tools/sync.sh            # pull --rebase (auto-resolving BOARD.md), then push
#   tools/sync.sh --no-push  # just get current; leave pushing to the caller
#
# Safe to run with nothing to push. Exits non-zero if a conflict it does NOT
# know how to resolve needs a human — it never guesses at real content.
set -eu

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

# EVERY generated board file, not just BOARD.md. `board-md` also writes
# BOARD-brief.md and BOARD-done.md (done/ alone was 190KB of BOARD.md, so the
# archived tables were split out) — and the moment a second generated file
# existed, sync.sh stopped being able to finish a rebase: it auto-resolved
# BOARD.md, then refused at BOARD-brief.md and handed a mechanical conflict to
# a human. The pattern must match whatever board-md emits, so it is a glob.
BOARD_GLOB='devdocs/progress/BOARD*.md'
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "sync: working tree is dirty — commit or stash first" >&2
    git status --short | head -10 >&2
    exit 1
fi

rebase_onto_origin() {
    git fetch --no-write-fetch-head -q origin master

    if ! git rebase -q origin/master 2>/dev/null; then
        # Only the GENERATED board files may be auto-resolved. Anything else is
        # real content and belongs to a human.
        while true; do
            conflicted=$(git diff --name-only --diff-filter=U)
            [ -z "$conflicted" ] && break
            others=$(printf '%s\n' "$conflicted" \
                     | grep -v '^devdocs/progress/BOARD.*\.md$' || true)
            if [ -n "$others" ]; then
                echo "sync: conflicts I will not guess at:" >&2
                printf '  %s\n' $others >&2
                echo "sync: resolve them, then: git rebase --continue" >&2
                exit 1
            fi
            # Generated boards only — discard both sides, regenerate from the
            # tickets. The resolution is always identical and always mechanical.
            git checkout --ours -- $BOARD_GLOB 2>/dev/null || true
            tools/progress.sh board-md >/dev/null 2>&1 || true
            git add $BOARD_GLOB
            if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
                if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
                    break      # rebase finished (or nothing left to apply)
                fi
            fi
        done
    fi

    # The boards can also be merely stale after a clean rebase — regenerate and
    # fold them into the top commit rather than leaving a dangling diff.
    tools/progress.sh board-md >/dev/null 2>&1 || true
    if [ -n "$(git status --porcelain -- $BOARD_GLOB)" ]; then
        git add $BOARD_GLOB
        git commit -q --amend --no-edit
    fi
}

# Push, re-rebasing on a race. The daemon publishes tstate every few minutes,
# so origin can move between our fetch and our push — a plain `push` then fails
# with "fetch first" and the caller has to run sync.sh again by hand (observed
# 2026-08-03 landing the ticket below). Rebase and retry is exactly what that
# rerun does, minus the human.
push_with_retry() {
    tries=0
    while [ "$tries" -lt 3 ]; do
        if git push -q origin master 2>/dev/null; then
            return 0
        fi
        tries=$((tries + 1))
        echo "sync: push raced another writer — rebasing and retrying ($tries/3)" >&2
        rebase_onto_origin
    done
    git push origin master          # let the real error out
}

# Fill in the commit citation of every ticket resolved without one.
#
# `progress.sh resolve <slug>` writes PENDING-COMMIT rather than a sha, because
# the only sha available at resolve time is the PRE-rebase one and this repo
# rebases on nearly every sync (the watcher daemon publishes tstate every few
# minutes). Cited shas were therefore rewritten out of existence the moment
# they were pushed — four in one session, none of them lookupable from the
# other box (bug-t-resolve-cites-a-sha-the-rebase-then-rewrites).
#
# Called AFTER the push, so the resolve commit is on origin and its sha is now
# final. The fill commit itself may still be rebased by a later push — that is
# harmless, since it cites shas that already landed, never its own.
fill_pending_commits() {
    # Every BUCKET, not just done/ + decided/: a resolved ticket can be filed
    # onward the same commit (done-followup/ when it spawned a follow-up, which
    # is what the first ticket resolved through this path did), and a
    # placeholder left in any bucket is a citation nobody can look up.
    #
    # The `*/*.md` glob is load-bearing: it keeps the board's own docs
    # (devdocs/progress/README.md, which DOCUMENTS the placeholder by name, and
    # BOARD.md) out of reach. Widening this to the whole directory rewrote the
    # README's prose into a sha on 2026-08-03.
    # ONE definition of "owes a citation", and it lives in progress.py. This
    # used to be a grep literal here and a substring test there; the two drifted
    # apart and neither tool could see the other disagreeing, so `check` reported
    # 17 forever while this function filled nothing
    # (bug-t-sync-fills-one-spelling-of-pending-commit-and-check-counts-two).
    # `pending` prints "<path>\t<sha>" per ticket, sha empty if undeterminable.
    pending=$(python3 "$(dirname "$0")/progress.py" pending 2>/dev/null || true)
    [ -n "$pending" ] || return 0

    filled=""
    while IFS="$(printf '\t')" read -r f sha; do
        [ -n "$f" ] || continue
        if [ -z "$sha" ]; then
            echo "sync: $f owes a citation but its resolve commit could not be determined — left alone" >&2
            continue
        fi
        # BOTH live spellings: the frontmatter field workers write by hand, and
        # the Log line `resolve` writes. Filling one and counting two is the bug.
        # Anchored to line start for the same reason progress.py's PENDING_RE is
        # — a ticket that QUOTES the placeholder mid-line is prose, not a
        # citation, and this bug's own ticket does exactly that.
        sed -i -e "s/^commit:[[:space:]]\{1,\}PENDING-COMMIT/commit: $sha/" \
               -e "s/^\(-[[:space:]].*commit\)[[:space:]]\{1,\}PENDING-COMMIT/\1 $sha/" "$f"
        git add "$f"
        filled="$filled $f"
    done <<EOF
$pending
EOF
    [ -n "$filled" ] || return 0

    git commit -q -m "docs(progress): record the shas the resolves landed as

$(printf '%s\n' $filled)"
    rebase_onto_origin
    push_with_retry
    echo "sync: filled PENDING-COMMIT —$filled"
}

rebase_onto_origin

if [ "$PUSH" = "1" ]; then
    push_with_retry
    echo "sync: pushed — $(git log --oneline -1)"
    fill_pending_commits
else
    echo "sync: up to date — $(git log --oneline -1)"
fi
