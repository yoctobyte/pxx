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

BOARD=devdocs/progress/BOARD.md
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
        # Only BOARD.md may be auto-resolved. Anything else is real content and
        # belongs to a human.
        while true; do
            conflicted=$(git diff --name-only --diff-filter=U)
            [ -z "$conflicted" ] && break
            others=$(printf '%s\n' "$conflicted" | grep -v "^$BOARD$" || true)
            if [ -n "$others" ]; then
                echo "sync: conflicts I will not guess at:" >&2
                printf '  %s\n' $others >&2
                echo "sync: resolve them, then: git rebase --continue" >&2
                exit 1
            fi
            # BOARD.md only — discard both sides and regenerate from the tickets.
            git checkout --ours -- "$BOARD" 2>/dev/null || true
            tools/progress.sh board-md >/dev/null 2>&1 || true
            git add "$BOARD"
            if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
                if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
                    break      # rebase finished (or nothing left to apply)
                fi
            fi
        done
    fi

    # The board can also be merely stale after a clean rebase — regenerate and
    # fold it into the top commit rather than leaving a dangling diff.
    tools/progress.sh board-md >/dev/null 2>&1 || true
    if [ -n "$(git status --porcelain -- "$BOARD")" ]; then
        git add "$BOARD"
        git commit -q --amend --no-edit
    fi
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
    files=$(git grep -l -- PENDING-COMMIT \
            "devdocs/progress/done" "devdocs/progress/decided" 2>/dev/null || true)
    [ -n "$files" ] || return 0

    filled=""
    for f in $files; do
        # The commit that INTRODUCED the placeholder into this file is the
        # resolve commit; -S finds it by the change in occurrence count and is
        # path-limited, so an unrelated later edit cannot claim the citation.
        sha=$(git log -1 --format=%h -S PENDING-COMMIT -- "$f")
        if [ -z "$sha" ]; then
            echo "sync: $f holds PENDING-COMMIT but no commit introduced it — left alone" >&2
            continue
        fi
        sed -i "s/PENDING-COMMIT/$sha/g" "$f"
        git add "$f"
        filled="$filled $f"
    done
    [ -n "$filled" ] || return 0

    git commit -q -m "docs(progress): record the shas the resolves landed as

$(printf '%s\n' $filled)"
    rebase_onto_origin
    git push -q origin master
    echo "sync: filled PENDING-COMMIT —$filled"
}

rebase_onto_origin

if [ "$PUSH" = "1" ]; then
    git push -q origin master
    echo "sync: pushed — $(git log --oneline -1)"
    fill_pending_commits
else
    echo "sync: up to date — $(git log --oneline -1)"
fi
