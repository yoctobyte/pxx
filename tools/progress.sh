#!/usr/bin/env bash
# Progress-board helper for devdocs/progress/.
#
# Priority is derived from dependency edges, not labels:
#   - a ticket is READY when every slug in its `Blocked-by:` line is in done/
#     (or it has no Blocked-by line);
#   - LEVERAGE = how many tickets name a slug in their Blocked-by.
#
# Usage: tools/progress.sh [ready|leverage|board|board-md|check|all] [--track A|B|C|D] [--strict]
#        tools/progress.sh claim <slug> <owner>
#        tools/progress.sh resolve <slug> <commit>
#   ready --track B  list ready Track-B tickets only
#   board-md  regenerate the committed devdocs/progress/BOARD.md (run after changes)
#   check     validate the board; fails on a stale BOARD.md
#   claim     git-mv a ticket to working/, stamp Status/Owner (no commit)
#   resolve   git-mv a ticket to done/, stamp Status + a Log line (no commit)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROG="$ROOT/devdocs/progress"
[ -d "$PROG" ] || { echo "no $PROG" >&2; exit 1; }
# Self-heal the canonical status dirs. Git does not track empty directories, so
# a status dir with no tickets (e.g. unfinished/) disappears on a fresh checkout.
# Under `set -o pipefail` a `find` over a missing dir then aborts the whole
# script mid-render, truncating BOARD.md. Recreating them up front keeps every
# `find "$PROG/<status>"` call site safe.
for _st in urgent working unfinished blocked backlog rainy-day done-followup done rejected; do
  mkdir -p "$PROG/$_st"
done
TRACK_FILTER=""
STRICT_CHECK=0

slug() { basename "$1" .md; }

# Slugs that are completed (Blocked-by satisfied if all blockers live here).
done_slugs() {
  find "$PROG/done" -name '*.md' 2>/dev/null -exec basename {} .md \;
}

# --- Ticket field extraction -------------------------------------------------
# Two ticket formats are accepted (agents differ; both are first-class):
#   A) YAML frontmatter between leading `---` lines:
#        summary: "..."   owner: name   blocked-by: [a, b]  (or a block list)
#   B) Markdown bullets:  `- **Blocked-by:** a, b`, `- **Owner:** name`,
#      with the H1 `# Title` as the summary.
# Frontmatter wins for scalar fields when both are present; Blocked-by slugs
# are merged from both sources.

# Print the YAML frontmatter body (empty if the file has none).
frontmatter_of() {
  awk 'NR==1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$1"
}

# Scalar frontmatter value for key $2 (surrounding quotes stripped).
fm_field() {
  frontmatter_of "$1" | awk -v key="$2" '
    !found && index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      found = 1; print v
    }' \
    | sed -E "s/^\"(.*)\"$/\1/; s/^'(.*)'$/\1/"
}

# Blocked-by slugs from frontmatter: inline `[a, b]`, scalar, or block list.
fm_blockers() {
  frontmatter_of "$1" | awk '
    /^blocked-by:[[:space:]]*\[/ {
      s = $0
      sub(/^blocked-by:[[:space:]]*\[/, "", s); sub(/\].*/, "", s)
      gsub(/,/, " ", s); print s; next
    }
    /^blocked-by:[[:space:]]*$/    { inlist = 1; next }
    /^blocked-by:[[:space:]]*[^[]/ {
      s = $0; sub(/^blocked-by:[[:space:]]*/, "", s)
      gsub(/,/, " ", s); print s; next
    }
    inlist && /^[[:space:]]*-[[:space:]]*/ {
      s = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", s); print s; next
    }
    inlist { inlist = 0 }
  ' | tr ' ' '\n' | sed 's/[`"'"'"']//g; /^$/d'
}

# Print the Blocked-by slugs of a ticket file, one per line (empty if none).
# Union of the bullet line and the frontmatter list, deduplicated.
# (greps are ||-guarded: "no match" must not trip set -e / pipefail.)
blockers_of() {
  {
    { grep -iE '^\s*-?\s*\*\*Blocked-by:\*\*' "$1" 2>/dev/null || true; } \
      | sed -E 's/.*\*\*Blocked-by:\*\*//; s/[`*]//g; s/,/ /g' \
      | tr ' ' '\n'
    fm_blockers "$1"
  } | sed '/^$/d' | sort -u
}

# Owner from frontmatter or bullet (frontmatter wins); empty when unset or `—`.
ticket_owner() {
  local o
  o="$(fm_field "$1" owner)"
  if [ -z "$o" ]; then
    o="$(grep -m1 -iE '^\s*-?\s*\*\*Owner:\*\*' "$1" 2>/dev/null \
      | sed -E 's/.*\*\*Owner:\*\*[[:space:]]*//' || true)"
  fi
  [ "$o" = "—" ] && o=""
  echo "$o"
}

normalize_track() {
  echo "$1" | tr '[:lower:]' '[:upper:]' \
    | sed -E 's/TRACK//g; s/[^ABCD+\/]//g; s#A/B#A+B#g; s#B/A#A+B#g'
}

# Track from frontmatter/bullet, then a conservative fallback. A+B means the
# ticket crosses the compiler/library boundary and should show up for both.
ticket_track() {
  local f="$1" s t line
  t="$(fm_field "$f" track)"
  if [ -z "$t" ]; then
    line="$(grep -m1 -iE '^\s*-?\s*\*\*Track:\*\*' "$f" 2>/dev/null || true)"
    if [ -n "$line" ]; then
      # Take only the first token after the label (e.g. `B`, `A+B`, `A/B`); any
      # trailing prose like `B — lib/rtl ...` otherwise leaks its A/B/slash
      # letters into normalize_track and garbles the value.
      t="$(echo "$line" | sed -E 's/.*\*\*Track:\*\*[[:space:]]*//; s/[[:space:]].*//')"
    fi
  fi
  t="$(normalize_track "$t")"
  if [ -n "$t" ]; then echo "$t"; return; fi

  s="$(slug "$f")"
  line="$(grep -m1 -iE '^\s*-?\s*\*\*Type:\*\*' "$f" 2>/dev/null || true)"
  if echo "$line" | grep -qiE '\bTrack[ -]?A/B\b|\bTrack[ -]?B/A\b'; then
    echo "A+B"; return
  fi
  if echo "$line" | grep -qiE '\bTrack[ -]?B\b'; then
    echo "B"; return
  fi
  if echo "$line" | grep -qiE '\bTrack[ -]?A\b'; then
    echo "A"; return
  fi

  case "$s" in
    lib-*|feature-*-library|feature-rtl-*|feature-terminal-*|feature-png-*|\
    feature-image-*|feature-adventure-*|feature-demo-*|idea-demo-*|\
    feature-platform-abstraction-layer|feature-c-runtime-library|\
    feature-networking|feature-sat-solver-library)
      echo "B"; return ;;
    bug-*|feature-*compiler*|feature-*parser*|feature-*syntax*|\
    feature-*codegen*|feature-*lower*|feature-*abi*|feature-cross-*|\
    feature-target-*|feature-*target*|feature-asm-*|feature-*-asm-*|\
    feature-elf-*|feature-empty-class-shorthand|feature-directive-*|\
    feature-c-source-frontend|\
    feature-array-of-const|feature-explicit-typecasts|feature-class-is-as|\
    feature-for-*|feature-forin-*|feature-int-to-float-assign|\
    feature-interface-*|feature-managed-exception-cleanup|\
    feature-procedural-types|feature-short-circuit-eval|\
    goal-compile-fpc-compiler)
      echo "A"; return ;;
  esac

  if grep -qiE '\bTrack[ -]?A/B\b|\bTrack[ -]?B/A\b' "$f"; then
    echo "A+B"; return
  fi
  if grep -qiE '\bTrack[ -]?B\b' "$f"; then
    echo "B"; return
  fi
  if grep -qiE '\bTrack[ -]?A\b' "$f"; then
    echo "A"; return
  fi

  case "${s%%-*}" in
    lib|meta|idea) echo "B" ;;
    *) echo "A" ;;
  esac
}

track_matches_filter() {
  local t="$1"
  [ -z "$TRACK_FILTER" ] && return 0
  case "$t" in
    *"$TRACK_FILTER"*) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_ready() {
  if [ -n "$TRACK_FILTER" ]; then
    echo "== READY (Track $TRACK_FILTER; no unmet blocker; pull from here) =="
  else
    echo "== READY (no unmet blocker; pull from here) =="
  fi
  local done_list; done_list="$(done_slugs)"
  local f s b unmet tr
  for f in "$PROG"/backlog/*.md "$PROG"/urgent/*.md; do
    [ -e "$f" ] || continue
    tr="$(ticket_track "$f")"
    track_matches_filter "$tr" || continue
    unmet=0
    while read -r b; do
      [ -z "$b" ] && continue
      grep -qxF "$b" <<<"$done_list" || unmet=1
    done < <(blockers_of "$f")
    if [ "$unmet" -eq 0 ]; then
      s="$(slug "$f")"
      case "$f" in *"/urgent/"*) printf '  [urgent] [%s] %s\n' "$tr" "$s";; *) printf '  [%s] %s\n' "$tr" "$s";; esac
    fi
  done
}

cmd_leverage() {
  echo "== LEVERAGE (how many not-yet-done tickets each slug unblocks) =="
  local f b done_list
  # A done blocker provides no leverage (it is already satisfied), and a
  # done/rejected source ticket needs no unblocking — exclude both so the count
  # reflects only real, remaining unblocking work. Uses the same done set as the
  # READY computation for consistency.
  done_list="$(done_slugs)"
  while IFS= read -r f; do
    case "$f" in
      "$PROG"/done/*|"$PROG"/rejected/*) continue ;;
    esac
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      printf '%s\n' "$done_list" | grep -qxF "$b" && continue
      printf '%s\n' "$b"
    done < <(blockers_of "$f")
  done < <(find "$PROG" -name '*.md' ! -name 'README.md' ! -name 'BOARD.md') \
    | sort | uniq -c | sort -rn | sed 's/^/  /'
}

cmd_board() {
  echo "== BOARD (tickets per status) =="
  local d n
  for d in urgent working unfinished blocked backlog rainy-day done-followup done rejected; do
    n=$(find "$PROG/$d" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
    printf '  %-9s %s\n' "$d" "$n"
  done
}

# Validate board integrity. Exits non-zero on structural problems (CI-friendly).
#   - dangling Blocked-by slugs (typo → ticket blocked forever),
#   - dependency cycles (graph must stay a DAG),
#   - working/ tickets without an Owner,
#   - stale BOARD.md.
#
# In normal mode, historical hygiene findings are warnings so old ticket debt
# does not make every current documentation or board edit fail. Use --strict to
# make those findings fatal:
#   - Track A/C tickets parked in unfinished/,
#   - done/ tickets without a commit reference.
cmd_check() {
  local problems=0
  local warning_count=0
  declare -A exists           # slug -> path of every ticket on the board
  local f s
  while IFS= read -r f; do
    exists["$(slug "$f")"]="$f"
  done < <(find "$PROG" -name '*.md' ! -name 'README.md' ! -name 'BOARD.md')

  # Build the blocker graph once. The old cycle check repeatedly rescanned every
  # ticket while removing nodes, which made check time grow quadratically.
  declare -A indeg dependents
  for s in "${!exists[@]}"; do
    indeg["$s"]=0
    dependents["$s"]=""
  done

  # 1. Dangling Blocked-by slugs.
  for s in "${!exists[@]}"; do
    while read -r b; do
      [ -z "$b" ] && continue
      if [ -z "${exists[$b]+x}" ]; then
        echo "DANGLING: $s blocked-by '$b' — no such ticket"; problems=1
      else
        dependents["$b"]+="$s"$'\n'
        indeg["$s"]=$(( indeg["$s"] + 1 ))
      fi
    done < <(blockers_of "${exists[$s]}")
  done

  # 2. Cycle detection via Kahn's algorithm over in-board edges.
  local total=${#exists[@]} gone=0 head=0 tail=0
  local -a queue=()
  for s in "${!exists[@]}"; do
    if [ "${indeg[$s]}" -eq 0 ]; then
      queue[tail]="$s"; tail=$(( tail + 1 ))
    fi
  done

  local t
  while [ "$head" -lt "$tail" ]; do
    s="${queue[$head]}"; head=$(( head + 1 ))
    gone=$(( gone + 1 ))
    while read -r t; do
      [ -z "$t" ] && continue
      indeg["$t"]=$(( indeg["$t"] - 1 ))
      if [ "${indeg[$t]}" -eq 0 ]; then
        queue[tail]="$t"; tail=$(( tail + 1 ))
      fi
    done <<<"${dependents[$s]}"
  done

  if [ "$gone" -ne "$total" ]; then
    echo "CYCLE: dependency graph is not a DAG ($(( total - gone )) tickets in a cycle)"; problems=1
  fi

  # 3. working/ needs an Owner; done/ needs a commit reference.
  for f in "$PROG"/working/*.md; do
    [ -e "$f" ] || continue
    if [ -z "$(ticket_owner "$f")" ]; then
      echo "NO-OWNER: $(slug "$f") is in working/ but has no Owner"; problems=1
    fi
  done
  # 3b. unfinished/ = a halted WIP with no active owner (working = the live lock,
  # released here). Track B/D parked unfinished is fine, but a Track A (Pascal
  # compiler) or Track C (C frontend) ticket left unfinished is CRITICAL: both
  # edit the compiler binary, so a half-applied change can break the
  # stable-binary boundary / self-host gate, and must not sit silently.
  for f in "$PROG"/unfinished/*.md; do
    [ -e "$f" ] || continue
    case "$(ticket_track "$f")" in
      A|*A+*|*+A*)
        warning_count=$(( warning_count + 1 ))
        if [ "$STRICT_CHECK" -eq 1 ]; then
          echo "WARN-UNFINISHED-A: $(slug "$f") is Track A in unfinished/ — compiler work is parked; resolve before treating Track A as clean"
        fi
        [ "$STRICT_CHECK" -eq 1 ] && problems=1
        ;;
    esac
    case "$(ticket_track "$f")" in
      C|*C+*|*+C*)
        warning_count=$(( warning_count + 1 ))
        if [ "$STRICT_CHECK" -eq 1 ]; then
          echo "WARN-UNFINISHED-C: $(slug "$f") is Track C (C frontend) in unfinished/ — compiler work is parked; resolve before treating Track C as clean"
        fi
        [ "$STRICT_CHECK" -eq 1 ] && problems=1
        ;;
    esac
  done
  for f in "$PROG"/done/*.md; do
    [ -e "$f" ] || continue
    if ! grep -qiE 'commit|[0-9a-f]{7,40}' "$f"; then
      warning_count=$(( warning_count + 1 ))
      if [ "$STRICT_CHECK" -eq 1 ]; then
        echo "WARN-NO-COMMIT: $(slug "$f") is in done/ but logs no commit"
      fi
      [ "$STRICT_CHECK" -eq 1 ] && problems=1
    fi
  done

  # 4. BOARD.md must be present and match a fresh render (it's committed).
  if [ ! -f "$PROG/BOARD.md" ]; then
    echo "NO-BOARD: devdocs/progress/BOARD.md missing — run: tools/progress.sh board-md"; problems=1
  elif ! diff -q <(render_board_md) "$PROG/BOARD.md" >/dev/null; then
    echo "STALE-BOARD: devdocs/progress/BOARD.md out of date — run: tools/progress.sh board-md"; problems=1
  fi

  if [ "$problems" -eq 0 ]; then
    if [ "$warning_count" -eq 0 ]; then
      echo "board OK"
    else
      echo "WARNINGS: $warning_count historical hygiene findings; run tools/progress.sh check --strict for details"
      echo "board OK with warnings"
    fi
  else
    return 1
  fi
}

# Type (filename prefix) of a ticket.
ticket_type() { local s; s="$(slug "$1")"; echo "${s%%-*}"; }

# One-line summary: frontmatter `summary:` if present, else the ticket's
# `# Title`. Table-breaking pipes escaped.
ticket_summary() {
  local s
  s="$(fm_field "$1" summary)"
  if [ -z "$s" ]; then
    s="$(grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^# //' || true)"
  fi
  echo "$s" | sed 's/|/\\|/g'
}

# Comma-joined Blocked-by slugs, or em dash when none.
ticket_blockers_csv() {
  local b out=""
  while read -r b; do
    [ -z "$b" ] && continue
    out="${out:+$out, }$b"
  done < <(blockers_of "$1")
  [ -z "$out" ] && out="—"
  echo "$out"
}

# Render a per-status board (ticket / track / type / summary / blocked-by) plus the
# ready queue and leverage, as Markdown to stdout. Deterministic (no timestamp)
# so the committed BOARD.md diffs cleanly and `check` can detect staleness; git
# history supplies the dates.
render_board_md() {
  local statuses=(urgent working unfinished blocked backlog rainy-day done-followup done rejected)
  echo "# Progress board"
  echo
  echo "_Generated by \`tools/progress.sh board-md\` — regenerate after any board"
  echo "change; \`tools/progress.sh check\` fails if this file is stale. History"
  echo "lives in git, not in a timestamp._"
  echo
  local st f n s
  for st in "${statuses[@]}"; do
    n=$(find "$PROG/$st" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
    echo "## $st ($n)"
    echo
    if [ "$n" -eq 0 ]; then
      echo "_none_"; echo; continue
    fi
    echo "| Ticket | Track | Type | Summary | Blocked-by |"
    echo "| --- | --- | --- | --- | --- |"
    while IFS= read -r f; do
      s="$(slug "$f")"
      echo "| $s | $(ticket_track "$f") | $(ticket_type "$f") | $(ticket_summary "$f") | $(ticket_blockers_csv "$f") |"
    done < <(find "$PROG/$st" -name '*.md' ! -name 'README.md' 2>/dev/null | sort)
    echo
  done
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

# Locate a single ticket .md by slug across every status dir. Echoes its path;
# fails (and explains) on a missing or ambiguous slug.
find_ticket() {
  local slug="$1" matches n
  matches="$(find "$PROG" -name "$slug.md" ! -name 'BOARD.md' 2>/dev/null || true)"
  n="$(printf '%s\n' "$matches" | grep -c . || true)"
  if [ "$n" -eq 0 ]; then echo "no ticket with slug: $slug" >&2; return 1; fi
  if [ "$n" -gt 1 ]; then
    echo "ambiguous slug $slug — matches:" >&2; printf '%s\n' "$matches" >&2; return 1
  fi
  printf '%s\n' "$matches"
}

# Move a ticket file, staging the move. Uses `git mv` when the source is already
# tracked; falls back to plain `mv` + `git add` for a freshly-authored ticket
# that has not been committed yet (the common claim case).
move_ticket() {
  local src="$1" dst="$2"
  if git ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git mv "$src" "$dst"
  else
    mv "$src" "$dst"; git add "$dst" >/dev/null 2>&1 || true
  fi
}

# Rewrite the first `- **<Marker>:** ...` bullet's value in place. No-op if the
# field is absent (older tickets that omit it).
set_field() {
  local file="$1" marker="$2" value="$3"
  if grep -qiE "^[[:space:]]*-?[[:space:]]*\*\*$marker:\*\*" "$file"; then
    sed -i -E "0,/(\*\*$marker:\*\*[[:space:]]*).*/s//\1$value/" "$file"
  fi
}

# claim <slug> <owner>: move the ticket into working/ and stamp Status/Owner.
# No commit — the move + Owner must land in one agent-authored commit.
cmd_claim() {
  local slug="${1:-}" owner="${2:-}" f dest
  if [ -z "$slug" ] || [ -z "$owner" ]; then
    echo "usage: $0 claim <slug> <owner>" >&2; return 2
  fi
  f="$(find_ticket "$slug")" || return 1
  dest="$PROG/working/$slug.md"
  if [ "$f" = "$dest" ]; then echo "$slug already in working/" >&2; return 1; fi
  move_ticket "$f" "$dest"
  set_field "$dest" Status working
  set_field "$dest" Owner "$owner"
  git add "$dest"
  echo "claimed $slug -> working/ (owner: $owner)." >&2
  echo "staged, not committed. regenerate the board ($0 board-md) and commit the move + edits together." >&2
}

# resolve <slug> <commit>: move the ticket into done/, stamp Status, append a
# Log line referencing the commit. No commit — the agent writes it.
cmd_resolve() {
  local slug="${1:-}" commit="${2:-}" f dest
  if [ -z "$slug" ] || [ -z "$commit" ]; then
    echo "usage: $0 resolve <slug> <commit>" >&2; return 2
  fi
  f="$(find_ticket "$slug")" || return 1
  dest="$PROG/done/$slug.md"
  if [ "$f" = "$dest" ]; then echo "$slug already in done/" >&2; return 1; fi
  move_ticket "$f" "$dest"
  set_field "$dest" Status done
  if ! grep -qE '^## Log' "$dest"; then printf '\n## Log\n' >> "$dest"; fi
  printf -- '- %s — resolved, commit %s.\n' "$(date +%F)" "$commit" >> "$dest"
  git add "$dest"
  echo "resolved $slug -> done/ (commit $commit)." >&2
  echo "staged, not committed. regenerate the board ($0 board-md) and commit." >&2
}

cmd="${1:-all}"
if [ "$#" -gt 0 ]; then shift; fi

# claim/resolve take positional args (slug, owner|commit), not the --track flag
# the other commands parse — dispatch them before the flag loop.
case "$cmd" in
  claim)   cmd_claim "$@"; exit $? ;;
  resolve) cmd_resolve "$@"; exit $? ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --track)
      [ "$#" -ge 2 ] || { echo "--track needs A, B, C, or D" >&2; exit 2; }
      TRACK_FILTER="$(normalize_track "$2")"; shift 2 ;;
    --track=*)
      TRACK_FILTER="$(normalize_track "${1#--track=}")"; shift ;;
    --strict)
      STRICT_CHECK=1; shift ;;
    *) echo "usage: $0 [ready|leverage|board|board-md|check|all] [--track A|B|C|D] [--strict]" >&2; exit 2 ;;
  esac
done
case "$TRACK_FILTER" in
  ""|A|B|C|D) ;;
  *) echo "--track must be A, B, C, or D" >&2; exit 2 ;;
esac

case "$cmd" in
  ready)    cmd_ready ;;
  leverage) cmd_leverage ;;
  board)    cmd_board ;;
  board-md) cmd_board_md ;;
  check)    cmd_check ;;
  all)      cmd_board; echo; cmd_leverage; echo; cmd_ready ;;
  *) echo "usage: $0 [ready|leverage|board|board-md|check|all] [--track A|B|C|D] [--strict]" >&2
     echo "       $0 claim <slug> <owner> | resolve <slug> <commit>" >&2; exit 2 ;;
esac
