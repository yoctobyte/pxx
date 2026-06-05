#!/usr/bin/env bash
# Progress-board helper for docs/progress/.
#
# Priority is derived from dependency edges, not labels:
#   - a ticket is READY when every slug in its `Blocked-by:` line is in done/
#     (or it has no Blocked-by line);
#   - LEVERAGE = how many tickets name a slug in their Blocked-by.
#
# Usage: tools/progress.sh [ready|leverage|board|all]   (default: all)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROG="$ROOT/docs/progress"
[ -d "$PROG" ] || { echo "no $PROG" >&2; exit 1; }

slug() { basename "$1" .md; }

# Slugs that are completed (Blocked-by satisfied if all blockers live here).
done_slugs() {
  find "$PROG/done" -name '*.md' 2>/dev/null -exec basename {} .md \;
}

# Print the `Blocked-by:` slugs of a ticket file, one per line (empty if none).
blockers_of() {
  grep -iE '^\s*-?\s*\*\*Blocked-by:\*\*' "$1" 2>/dev/null \
    | sed -E 's/.*\*\*Blocked-by:\*\*//; s/[`*]//g; s/,/ /g' \
    | tr ' ' '\n' | sed '/^$/d'
}

cmd_ready() {
  echo "== READY (no unmet blocker; pull from here) =="
  local done_list; done_list="$(done_slugs)"
  local f s b unmet
  for f in "$PROG"/backlog/*.md "$PROG"/urgent/*.md; do
    [ -e "$f" ] || continue
    unmet=0
    while read -r b; do
      [ -z "$b" ] && continue
      grep -qxF "$b" <<<"$done_list" || unmet=1
    done < <(blockers_of "$f")
    if [ "$unmet" -eq 0 ]; then
      s="$(slug "$f")"
      case "$f" in *"/urgent/"*) printf '  [urgent] %s\n' "$s";; *) printf '  %s\n' "$s";; esac
    fi
  done
}

cmd_leverage() {
  echo "== LEVERAGE (how many tickets each slug unblocks) =="
  find "$PROG" -name '*.md' ! -name 'README.md' -exec cat {} + \
    | grep -iE '^\s*-?\s*\*\*Blocked-by:\*\*' \
    | sed -E 's/.*\*\*Blocked-by:\*\*//; s/[`*]//g; s/,/ /g' \
    | tr ' ' '\n' | sed '/^$/d' | sort | uniq -c | sort -rn \
    | sed 's/^/  /'
}

cmd_board() {
  echo "== BOARD (tickets per status) =="
  local d n
  for d in urgent working backlog blocked done rejected; do
    n=$(find "$PROG/$d" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
    printf '  %-9s %s\n' "$d" "$n"
  done
}

case "${1:-all}" in
  ready)    cmd_ready ;;
  leverage) cmd_leverage ;;
  board)    cmd_board ;;
  all)      cmd_board; echo; cmd_leverage; echo; cmd_ready ;;
  *) echo "usage: $0 [ready|leverage|board|all]" >&2; exit 2 ;;
esac
