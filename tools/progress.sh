#!/usr/bin/env bash
# Progress-board helper for docs/progress/.
#
# Priority is derived from dependency edges, not labels:
#   - a ticket is READY when every slug in its `Blocked-by:` line is in done/
#     (or it has no Blocked-by line);
#   - LEVERAGE = how many tickets name a slug in their Blocked-by.
#
# Usage: tools/progress.sh [ready|leverage|board|board-md|check|all]  (default: all)
#   board-md  regenerate the committed docs/progress/BOARD.md (run after changes)
#   check     validate the board; fails on a stale BOARD.md

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
  find "$PROG" -name '*.md' ! -name 'README.md' ! -name 'BOARD.md' -exec cat {} + \
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

# Validate board integrity. Exits non-zero on any problem (CI-friendly).
#   - dangling Blocked-by slugs (typo → ticket blocked forever),
#   - dependency cycles (graph must stay a DAG),
#   - working/ tickets without an Owner,
#   - done/ tickets without a commit reference.
cmd_check() {
  local problems=0
  declare -A exists           # slug -> path of every ticket on the board
  local f s
  while IFS= read -r f; do
    exists["$(slug "$f")"]="$f"
  done < <(find "$PROG" -name '*.md' ! -name 'README.md' ! -name 'BOARD.md')

  # 1. Dangling Blocked-by slugs.
  for s in "${!exists[@]}"; do
    while read -r b; do
      [ -z "$b" ] && continue
      if [ -z "${exists[$b]+x}" ]; then
        echo "DANGLING: $s blocked-by '$b' — no such ticket"; problems=1
      fi
    done < <(blockers_of "${exists[$s]}")
  done

  # 2. Cycle detection via Kahn's algorithm over in-board edges.
  declare -A indeg
  for s in "${!exists[@]}"; do indeg["$s"]=0; done
  for s in "${!exists[@]}"; do
    while read -r b; do
      [ -z "$b" ] && continue
      [ -n "${exists[$b]+x}" ] && indeg["$s"]=$(( indeg["$s"] + 1 ))
    done < <(blockers_of "${exists[$s]}")
  done
  local removed=1 total=${#exists[@]} gone=0
  declare -A done_node
  while [ "$removed" -eq 1 ]; do
    removed=0
    for s in "${!exists[@]}"; do
      [ -n "${done_node[$s]+x}" ] && continue
      if [ "${indeg[$s]}" -eq 0 ]; then
        done_node["$s"]=1; gone=$(( gone + 1 )); removed=1
        # decrement dependents (tickets that list s as a blocker)
        local t
        for t in "${!exists[@]}"; do
          [ -n "${done_node[$t]+x}" ] && continue
          while read -r b; do
            [ "$b" = "$s" ] && indeg["$t"]=$(( indeg["$t"] - 1 ))
          done < <(blockers_of "${exists[$t]}")
        done
      fi
    done
  done
  if [ "$gone" -ne "$total" ]; then
    echo "CYCLE: dependency graph is not a DAG ($(( total - gone )) tickets in a cycle)"; problems=1
  fi

  # 3. working/ needs an Owner; done/ needs a commit reference.
  for f in "$PROG"/working/*.md; do
    [ -e "$f" ] || continue
    if grep -qiE '^\s*-?\s*\*\*Owner:\*\*\s*—?\s*$' "$f"; then
      echo "NO-OWNER: $(slug "$f") is in working/ but has no Owner"; problems=1
    fi
  done
  for f in "$PROG"/done/*.md; do
    [ -e "$f" ] || continue
    if ! grep -qiE 'commit|[0-9a-f]{7,40}' "$f"; then
      echo "NO-COMMIT: $(slug "$f") is in done/ but logs no commit"; problems=1
    fi
  done

  # 4. BOARD.md must be present and match a fresh render (it's committed).
  if [ ! -f "$PROG/BOARD.md" ]; then
    echo "NO-BOARD: docs/progress/BOARD.md missing — run: tools/progress.sh board-md"; problems=1
  elif ! diff -q <(render_board_md) "$PROG/BOARD.md" >/dev/null; then
    echo "STALE-BOARD: docs/progress/BOARD.md out of date — run: tools/progress.sh board-md"; problems=1
  fi

  if [ "$problems" -eq 0 ]; then echo "board OK"; else return 1; fi
}

# Render a kanban grid + ready/leverage as Markdown to stdout. Output is
# deterministic (no timestamp) so the committed BOARD.md diffs cleanly and
# `check` can detect staleness; git history supplies the dates.
render_board_md() {
  local statuses=(urgent working backlog blocked done rejected)
  declare -A cell cnt
  local maxrows=0 st i f
  for st in "${statuses[@]}"; do
    i=0
    while IFS= read -r f; do
      cell["$st,$i"]="$(slug "$f")"; i=$((i+1))
    done < <(find "$PROG/$st" -name '*.md' 2>/dev/null | sort)
    cnt["$st"]=$i
    [ "$i" -gt "$maxrows" ] && maxrows=$i
  done
  echo "# Progress board"
  echo
  echo "_Generated by \`tools/progress.sh board-md\` — regenerate after any board"
  echo "change; \`tools/progress.sh check\` fails if this file is stale. History"
  echo "lives in git, not in a timestamp._"
  echo
  local hdr="|" sep="|"
  for st in "${statuses[@]}"; do hdr+=" $st (${cnt[$st]}) |"; sep+=" --- |"; done
  echo "$hdr"; echo "$sep"
  local r line
  for (( r=0; r<maxrows; r++ )); do
    line="|"
    for st in "${statuses[@]}"; do line+=" ${cell[$st,$r]:-} |"; done
    echo "$line"
  done
  echo
  echo "## Ready (no unmet blocker)"
  echo
  cmd_ready | grep '^  ' | sed 's/^  /- /'
  echo
  echo "## Leverage (tickets each one unblocks)"
  echo
  cmd_leverage | grep -E '^ +[0-9]' | sed -E 's/^ +([0-9]+) (.*)/- **\1** — \2/'
}

cmd_board_md() {
  render_board_md > "$PROG/BOARD.md"
  echo "wrote $PROG/BOARD.md"
}

case "${1:-all}" in
  ready)    cmd_ready ;;
  leverage) cmd_leverage ;;
  board)    cmd_board ;;
  board-md) cmd_board_md ;;
  check)    cmd_check ;;
  all)      cmd_board; echo; cmd_leverage; echo; cmd_ready ;;
  *) echo "usage: $0 [ready|leverage|board|board-md|check|all]" >&2; exit 2 ;;
esac
