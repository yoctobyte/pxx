#!/bin/sh
# How far did a fail-fast tier actually GET?
#
# `make test-core` is ONE recipe and stops at the first failing line, so a run
# that dies early and a run that dies late produce the same shaped output: one
# named failure and a stopped make. Nothing in it says "and the following
# eleven thousand assertions did not run", and the natural reading -- "one known
# red, the rest is behind it" -- turns *behind it* into *fine*.
#
# Measured 2026-09-05: a stale refusal fixture at step 6 of 15 held test-core to
# 279 executed assertion rows. With it fixed the same tier ran 1629. Nobody was
# reading a lie; everybody was reading a green about the first sixth of a tier.
# In a fail-fast recipe THE COST OF A RED IS ITS INDEX, NOT ITS SEVERITY, and
# no ticket field records where in a recipe a failure sits.
#
# Usage:
#   tools/tier_coverage.sh RUN.log [REFERENCE.log]
#
# Counts the assertion rows a run actually executed (make echoes each command
# before running it, so the log carries them) and, given a reference log from a
# run known to have reached the end, reports the fraction.
#
# WHY NOT `make -n` FOR THE DENOMINATOR. It was tried and it is an UPPER BOUND,
# not a target: it prints both arms of shell conditionals and every prerequisite
# as if nothing were up to date, so a complete green run scores 1629 against its
# 1734 and a reader would meet a 94% that means nothing is wrong. 43 of the gap
# were checked by name -- gcc-oracle rows inside `if` blocks, and file targets
# already satisfied. A denominator that cannot be reached on a healthy tree is
# the same animal as a gate that cannot pass, so it is not used here.
set -eu

log=${1:-}
ref=${2:-}
[ -n "$log" ] && [ -f "$log" ] || { echo "usage: $0 RUN.log [REFERENCE.log]" >&2; exit 2; }

count_rows() {
  # expect_same rows and asserted-refusal greps: the two shapes that carry a
  # verdict. Compiles are counted separately -- a compile is work, not a claim.
  grep -cE '^[[:space:]]*(tools/expect_same\.sh |grep -q )' "$1" || true
}
count_compiles() {
  grep -cE '^[[:space:]]*@?\./(compiler/pascal26|\$\(COMPILER\)) ' "$1" || true
}

rows=$(count_rows "$log")
comps=$(count_compiles "$log")

# Did it reach the end, or stop? A stopped recipe leaves make's own error line.
if grep -qE '^make: \*\*\* ' "$log"; then
  stopped=yes
else
  stopped=no
fi

echo "tier coverage for $log"
echo "  assertion rows executed : $rows"
echo "  compiles executed       : $comps"
echo "  recipe stopped early    : $stopped"

if [ "$stopped" = yes ]; then
  echo "  stopped at              : $(grep -E '^make: \*\*\* ' "$log" | head -1)"
  last=$(grep -E '^[[:space:]]*(tools/expect_same\.sh |grep -q )' "$log" | tail -1 | cut -c1-100)
  echo "  last assertion reached  : $last"
fi

if [ -n "$ref" ]; then
  [ -f "$ref" ] || { echo "reference log $ref not found" >&2; exit 2; }
  rrows=$(count_rows "$ref")
  if [ "$rrows" -lt 1 ]; then
    # A reference with no assertion rows would make every run look complete.
    echo "  reference $ref has no assertion rows -- it is not a reference." >&2
    exit 2
  fi
  pct=$(( rows * 100 / rrows ))
  echo "  reference               : $ref ($rrows rows)"
  echo "  fraction of the tier seen: ${pct}%"
  if [ "$pct" -lt 90 ]; then
    echo ""
    echo "  ^^ this run saw ${pct}% of what the reference run saw. The rest did"
    echo "     not fail -- it DID NOT RUN. Do not read the difference as green."
  fi
fi
