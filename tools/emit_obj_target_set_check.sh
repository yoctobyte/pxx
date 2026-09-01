#!/usr/bin/env bash
# Assert that every statement of "which targets --emit-obj supports" agrees with
# what the compiler actually DOES.
#
# WHY THIS EXISTS. The set was written down in four places -- the dispatch in
# compiler.pas, the refusal text in elfwriter.inc, the --help line, and
# docs/reference/cli.md -- and three of them were wrong at once on 2026-08-31:
#
#   * the refusal said "only xtensa/riscv32" while x86-64 had had a general
#     writer for hours (the ticket this check closes);
#   * it was then hand-corrected to name x86-64 and was FALSE AGAIN the same
#     day, because i386 got writeELFRel386General while the new sentence still
#     read "i386, arm32 and aarch64 have no object writer";
#   * --help still said "general objects: --target=xtensa|riscv32 only" through
#     both of those corrections.
#
# Each hand-correction was right about the moment it was written. The fix is not
# a fifth careful sentence: the set now lives in ONE predicate
# (TargetHasObjectWriter) and every message is built from it. This check is the
# guard that says so, and it hardcodes NO list -- it compares the compiler's
# behaviour against the compiler's own words, so it stays true when a writer is
# added.
#
# Usage: tools/emit_obj_target_set_check.sh <compiler> [tmpdir]
set -uo pipefail

PXX=${1:?usage: emit_obj_target_set_check.sh <compiler> [tmpdir]}
TMP=${2:-}
if [ -z "$TMP" ]; then TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT; fi
mkdir -p "$TMP"

src=$TMP/eots.pas
cat > "$src" <<'EOF'
program eots;
function AddTwo(a, b: Integer): Integer; cdecl;
begin
  AddTwo := a + b;
end;
begin
end.
EOF

# The enumeration authority is the compiler's own --target= list, not a list
# kept here -- a second list in the checker is the same defect one layer out.
# --list-targets prints the ISA table, then a BLANK LINE, then the ESP SoC
# names -- which are not targets but aliases that imply one (`esp32` selects
# xtensa). Taking them as targets made the check fail on its first run with
# `esp32` in the "actually succeeds" set and not in the refusal's list, which
# is a true statement about the wrong population. Stop at the blank line.
targets=$("$PXX" --list-targets 2>/dev/null \
  | awk 'NR>1 { if (!NF) exit; print $1 }' \
  | sed 's/(default)//' | awk 'NF')
if [ -z "$targets" ]; then
  echo "emit-obj-target-set: FAILED -- --list-targets produced no targets" >&2
  exit 1
fi

works=""
refused=""
claimed=""
nrefusals=0
for t in $targets; do
  out=$("$PXX" --target="$t" --emit-obj "$src" "$TMP/eots_$t.o" 2>&1)
  if [ $? -eq 0 ]; then
    works="$works $t"
  else
    refused="$refused $t"
    nrefusals=$((nrefusals + 1))
    # The refusal must NAME the supported set, and every refusal must name the
    # same one -- they are all built from the one predicate.
    said=$(printf '%s' "$out" | sed -n 's/.*supported: \([^;]*\)$/\1/p' | head -1)
    if [ -z "$said" ]; then
      echo "emit-obj-target-set: FAILED -- the refusal for $t names no supported set:" >&2
      printf '  %s\n' "$out" >&2
      exit 1
    fi
    said=$(printf '%s' "$said" | tr -d ' ')
    if [ -z "$claimed" ]; then claimed=$said
    elif [ "$claimed" != "$said" ]; then
      echo "emit-obj-target-set: FAILED -- two refusals name DIFFERENT sets: '$claimed' vs '$said' (for $t)" >&2
      exit 1
    fi
  fi
done

# A check with nothing to check is not a check. If every target grew a writer
# this would silently pass forever, so say so instead.
if [ "$nrefusals" -eq 0 ]; then
  echo "emit-obj-target-set: every target has an object writer -- no refusal to check." >&2
  echo "  That is good news, but this check now asserts nothing: retire it or give it a new question." >&2
  exit 1
fi

# The spelling --emit-obj accepts and the spelling --list-targets prints are the
# same alphabet EXCEPT for x86-64/x86_64, which is one target with two spellings
# (TargetArchName says x86-64; --target= takes either).
norm() { printf '%s' "$1" | tr ',' '\n' | tr -d ' ' | sed 's/x86_64/x86-64/' | awk 'NF' | sort | paste -sd,; }

actual=$(norm "$(printf '%s' "$works" | tr ' ' ',')")
named=$(norm "$claimed")

if [ "$actual" != "$named" ]; then
  echo "emit-obj-target-set: FAILED -- the diagnostic and the dispatch disagree." >&2
  echo "  --emit-obj actually succeeds on: $actual" >&2
  echo "  the refusal says supported are:  $named" >&2
  echo "  (refused:$refused)" >&2
  exit 1
fi

# ...and --help, the third copy, which was stale through both hand-corrections.
helpset=$("$PXX" --help 2>&1 | sed -n 's/.*general objects: *//p' | head -1)
if [ -z "$helpset" ]; then
  echo "emit-obj-target-set: FAILED -- --help no longer states the general-object target set" >&2
  exit 1
fi
helpnamed=$(norm "$helpset")
if [ "$helpnamed" != "$actual" ]; then
  echo "emit-obj-target-set: FAILED -- --help names a different set than --emit-obj supports." >&2
  echo "  --help says: $helpnamed" >&2
  echo "  actual:      $actual" >&2
  exit 1
fi

# ...and the FOURTH copy, docs/reference/cli.md's --emit-obj row, which said
# "on any target" while the diagnostic said "only xtensa/riscv32" -- both wrong,
# in opposite directions, and the truth in neither.
#
# THE LIMIT OF THIS ONE, stated because a caveat gets believed rather than
# re-tested: prose cannot be derived from a predicate, so this asserts only that
# every supported target is NAMED in that row. It catches the historical failure
# (a target gains a writer and the docs never learn) and does NOT catch
# over-claiming (the row promising a target that refuses). The row is Track D's
# to word; this is a mention check, not a parse.
doc=docs/reference/cli.md
if [ -f "$doc" ]; then
  # The TABLE row, not the first prose mention of the flag: `head -1` on a bare
  # grep picked up a sentence about `.so` output and reported the row as naming
  # no targets at all -- a true statement about the wrong line.
  row=$(grep -- '^| *`--emit-obj`' "$doc" | head -1)
  if [ -z "$row" ]; then
    echo "emit-obj-target-set: FAILED -- $doc no longer documents --emit-obj" >&2
    exit 1
  fi
  missing=""
  for t in $(printf '%s' "$actual" | tr ',' ' '); do
    case "$row" in *"$t"*) ;; *) missing="$missing $t" ;; esac
  done
  if [ -n "$missing" ]; then
    echo "emit-obj-target-set: FAILED -- $doc's --emit-obj row never names:$missing" >&2
    echo "  row: $row" >&2
    exit 1
  fi
fi

echo "emit-obj-target-set: ok -- dispatch, refusal and --help all name $actual (refused:$refused); cli.md names them all"
