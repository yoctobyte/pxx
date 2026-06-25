#!/bin/sh
# file-ticket.sh — land a docs/progress ticket onto master so EVERY track sees
# it, without disturbing your current branch/worktree.
#
# Why: tickets buried on a feature branch are invisible to sister agents working
# on master. Tickets are doc-only, append-mostly, near-zero conflict -> they live
# on master. Code stays on track branches until merged.
#
# Usage:
#   tools/file-ticket.sh <ticket.md> [<more.md> ...]
#
# Each path may be absolute or relative to CWD. If a path contains
# "docs/progress/<bucket>/", that bucket (backlog/unfinished/working/...) is
# preserved on master; otherwise the file lands in docs/progress/backlog/.
#
# Safe by design: operates in a throwaway worktree off origin/master, never
# touches your checkout, uses pull --rebase before pushing, and scoped commits.
set -eu

REMOTE=origin
BRANCH=master

[ $# -ge 1 ] || { echo "usage: $0 <ticket.md> [more.md ...]" >&2; exit 1; }

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
    *docs/progress/*) rel="docs/progress/${f##*docs/progress/}" ;;
    *)                rel="docs/progress/backlog/$(basename "$f")" ;;
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
  git add docs/progress/BOARD.md >/dev/null 2>&1 || true
fi

git commit -q -m "docs(tickets): sync ticket(s) to master

$added"
git pull --rebase -q "$REMOTE" "$BRANCH" || {
  echo "file-ticket: rebase conflict; resolve manually in $WT (NOT auto-cleaned)" >&2
  trap - EXIT INT TERM
  exit 2
}
git push -q "$REMOTE" "HEAD:$BRANCH"
echo "file-ticket: landed on $BRANCH -> $added"
