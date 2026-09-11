#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# file-ticket.sh — land a devdocs/progress ticket onto master so EVERY track sees
# it, without disturbing your current branch/worktree.
#
# Why: tickets buried on a feature branch are invisible to sister agents working
# on master. Tickets are doc-only, append-mostly, near-zero conflict -> they live
# on master. Code stays on track branches until merged.
#
# Usage:
#   tools/file-ticket.sh [--replace] <ticket.md> [<more.md> ...]
#
# Each path may be absolute or relative to CWD. If a path contains
# "devdocs/progress/<bucket>/", that bucket (backlog/unfinished/working/...) is
# preserved on master; otherwise the file lands in devdocs/progress/backlog/.
#
# Safe by design: operates in a throwaway worktree off origin/master, never
# touches your checkout, uses pull --rebase before pushing, and scoped commits.
set -eu

REMOTE=origin
BRANCH=master

REPLACE=0
if [ "${1:-}" = "--replace" ]; then REPLACE=1; shift; fi

[ $# -ge 1 ] || { echo "usage: $0 [--replace] <ticket.md> [more.md ...]" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel)

# Pre-resolve every source path against CWD / repo root before we cd away.
SRCS=""
DESTS=""
for f in "$@"; do
  src=$f
  [ -f "$src" ] || src="$ROOT/$f"
  [ -f "$src" ] || { echo "file-ticket: not found: $f" >&2; exit 1; }
  src=$(readlink -f "$src")
  case "$f" in
    *devdocs/progress/*) rel="devdocs/progress/${f##*devdocs/progress/}" ;;
    *)                rel="devdocs/progress/backlog/$(basename "$f")" ;;
  esac
  SRCS="$SRCS$src
"
  DESTS="$DESTS$rel
"
done

WT=$(mktemp -d)
cleanup() {
  cd "$ROOT" 2>/dev/null || true
  git worktree remove --force "$WT" 2>/dev/null || true
  git worktree prune 2>/dev/null || true
  rm -rf "$WT"
}
trap cleanup EXIT INT TERM

git fetch -q "$REMOTE" "$BRANCH"
git worktree add -f "$WT" "$REMOTE/$BRANCH" >/dev/null
cd "$WT"
git checkout -q -b "ticket-sync-$$"

# REFUSE TO CLOBBER. The copy below is a bare `cp`, so without this a ticket filed
# at a slug that already exists on master silently REPLACES origin's version --
# reverting whatever anyone else wrote there -- and commits it under this script's
# generic "sync ticket(s) to master" subject. `git status` calls that M, not A, so
# nothing about the result looks like an overwrite. Added 2026-09-11 after frankS
# hit the manual form of this by hand (cp over frankH's TExecuteFlags ticket, which
# had the better diagnosis) and caught it only by reading the diff before committing.
# The right move on a collision is almost always to APPEND a dated section to the
# existing ticket, which is what frankS then did.
# THE `if` BELOW MUST STAY AN `if`, not `[ -e "$rel" ] && printf ...`. `set -e` is
# INHERITED BY THE COMMAND-SUBSTITUTION SUBSHELL, so a false test as the last command
# of the loop body aborts that subshell -- and it is false exactly when there is NO
# conflict, i.e. on every ordinary filing. The first version of this guard had the
# `&&` form and broke normal ticket filing while BOTH refusal rows still passed; a
# trailing `; :` does not rescue it, because the subshell is already dead before the
# `:` runs (`x=$(false; :)` exits under dash too -- measured 2026-09-11). An `if`
# whose condition is false is status 0, so it is safe. Caught by row 1 of
# tools/file_ticket_clobber_devtest.sh, which exists to assert that this guard does
# not over-block; the two rows testing the refusal were green throughout.
conflicts=$(printf '%s' "$DESTS" | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ -e "$rel" ]; then printf '%s\n' "$rel"; fi
done)
if [ -n "$conflicts" ] && [ "$REPLACE" -ne 1 ]; then
  echo "file-ticket: REFUSING to overwrite ticket(s) that already exist on $BRANCH:" >&2
  printf '%s\n' "$conflicts" | sed 's/^/  /' >&2
  echo "" >&2
  echo "A ticket at this slug is already filed. Overwriting it would revert whatever" >&2
  echo "is there now, as a commit whose subject says 'sync ticket(s) to master'." >&2
  echo "" >&2
  echo "Almost always what you want instead:" >&2
  echo "  1. read the existing ticket -- it may have a better diagnosis than yours" >&2
  echo "  2. APPEND a dated section to it, and fix its summary if yours makes it stale" >&2
  echo "  3. if it is genuinely a different bug, pick a slug that says how it differs" >&2
  echo "" >&2
  echo "To replace deliberately: $0 --replace <file> ...  (the commit will say so)" >&2
  exit 3
fi

# Copy + stage each ticket (paired SRCS/DESTS lines).
added=""
i=1
echo "$DESTS" | while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src=$(echo "$SRCS" | sed -n "${i}p")
  mkdir -p "$(dirname "$rel")"
  cp "$src" "$rel"
  git add "$rel"
  i=$((i + 1))
done
# Re-derive the staged list (the while ran in a subshell).
added=$(git diff --cached --name-only | tr '\n' ' ')
[ -n "$added" ] || { echo "file-ticket: nothing staged" >&2; exit 1; }

# Best-effort BOARD refresh (skip silently if generator absent).
if [ -x tools/progress.sh ]; then
  tools/progress.sh board-md >/dev/null 2>&1 || true
  git add devdocs/progress/BOARD.md >/dev/null 2>&1 || true
fi

if [ "$REPLACE" -eq 1 ] && [ -n "$conflicts" ]; then
  # Never let a replacement ride under the routine subject -- that is the whole
  # reason the overwrite was invisible in the first place.
  git commit -q -m "docs(tickets): REPLACE existing ticket(s) on master

Replaced in full (previous content discarded, not merged):
$(printf '%s\n' "$conflicts" | sed 's/^/  /')

$added"
else
  git commit -q -m "docs(tickets): sync ticket(s) to master

$added"
fi
git pull --rebase -q "$REMOTE" "$BRANCH" || {
  echo "file-ticket: rebase conflict; resolve manually in $WT (NOT auto-cleaned)" >&2
  trap - EXIT INT TERM
  exit 2
}
git push -q "$REMOTE" "HEAD:$BRANCH"
echo "file-ticket: landed on $BRANCH -> $added"
