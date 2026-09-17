#!/bin/sh
# A/B the FPC corpus across TWO COMPILER BINARIES at ONE TREE, and join per unit.
#
# WHY THIS EXISTS: the join keeps not happening. umbrella-pxx-compiles-fpc-itself
# records three sweeps on 2026-09-17 and a per-unit join on NONE of them, and the
# one time a join did happen it was because a pre-fix sweep happened to still be
# sitting in the same scratch directory. Ad-hoc each time means skipped most
# times, so the discipline is a committed script rather than a habit.
#
# WHAT A JOIN BUYS OVER THREE NUMBERS: equal totals are satisfiable by a
# regression and a gain that CANCEL. An aggregate first-failure table cannot see
# two units swapping inside one error class; a per-unit join reports zero verdict
# changes in either direction rather than an unchanged count.
#
# THE TREE IS HELD, NOT THE DATE. Both legs run against ONE tree, in one session.
# Joining today's pinned run against yesterday's HEAD rows credits the PIN with
# every commit that landed in between -- measured 2026-09-17: a nine-commit,
# all-Track-P gap sat under a baseline that was still "alive", and alive was
# established while what-tree-made-it was not. The favourable direction is the
# one nobody checks (CLAUDE.md), and a pin is where it is most flattering.
#
# WHAT PXXBIN=<pinned> ACTUALLY MEASURES, and it is the right thing for the floor
# question rather than a caveat: lib/rtl reaches from the LIVE tree even for the
# pinned binary, so that leg is the OLD compiler against the CURRENT RTL -- which
# is exactly what a Track B consumer building with $(PXX_STABLE) experiences.
#
# THE POSITIVE CONTROL IS BUILT IN: two legs run with the SAME binary cannot
# produce a verdict change, so an A/B that cannot tell its legs apart is a guard
# that cannot fail. This refuses when the two sha256s are equal.
#
# READ THE TOKEN, NOT THE EXIT CODE. A full sweep is ~8 min per leg, so this is
# meant to be backgrounded -- and a backgrounded wrapper reports the WRAPPER:
# gate.sh said `exit code 0` over `gate: RED` three times in one day, and
# busybox_diff.sh reported `completed (exit code 0)` at a 10-minute cap while the
# real run carried on. Grep the log for FPC-CORPUS-AB-COMPLETE. It re-execs a
# copy of itself for the same reason busybox_diff.sh does: /bin/sh reads a script
# INCREMENTALLY, so a peer's `git pull` mid-run corrupts it, and the step a
# corrupted script loses first is the SUMMARY, because it is last.
#
# Usage: tools/fpc_corpus_ab.sh <binA> <binB> [outdir] [fpc-compiler-dir]
#        PXX_CORPUS_AB_LIST=<file>  restrict both legs to these units (one path
#                                   per line) -- use a 3-unit list to prove the
#                                   harness before spending 16 minutes on it.
set -u

# THE RE-EXEC MOVES $0 AND THEREFORE MOVES THE REPO ROOT, which is how the first
# run of this script produced two EMPTY legs: the copy lives in a mktemp dir, so
# `dirname $0/..` resolved to /tmp, the probe was looked for at
# /tmp/tools/fpc_compiler_corpus_probe.sh, and both legs wrote nothing. Capture
# the root BEFORE the re-exec and carry it across.
if [ -n "${FPC_CORPUS_AB_ROOT:-}" ]; then
  R=$FPC_CORPUS_AB_ROOT
else
  R=$(cd "$(dirname "$0")/.." && pwd)
fi

# Re-exec from a copy so a pull cannot rewrite this file underneath the run.
if [ "${FPC_CORPUS_AB_REEXEC:-}" != "1" ]; then
  C=$(mktemp -d)
  trap 'rm -rf "$C"' EXIT
  cp "$0" "$C/ab.sh" || exit 2
  FPC_CORPUS_AB_REEXEC=1; export FPC_CORPUS_AB_REEXEC
  FPC_CORPUS_AB_ROOT=$R; export FPC_CORPUS_AB_ROOT
  sh "$C/ab.sh" "$@"
  exit $?
fi

if [ $# -lt 2 ]; then echo "usage: $0 <binA> <binB> [outdir] [fpc-dir]" >&2; exit 2; fi
A=$1; B=$2
O=${3:-$R/.corpus-ab}
F=${4:-/home/neo/src/fpc-trunk/compiler}

for b in "$A" "$B"; do
  [ -x "$b" ] || { echo "not executable: $b" >&2; exit 2; }
done

SA=$(sha256sum "$A" | cut -c1-12)
SB=$(sha256sum "$B" | cut -c1-12)
if [ "$SA" = "$SB" ]; then
  echo "REFUSED: both legs are the same binary ($SA) -- an A/B that cannot tell" >&2
  echo "         its legs apart is a guard that cannot fail." >&2
  exit 2
fi

mkdir -p "$O" || exit 2

# THE TREE IDENTITY, TAKEN TWICE. testmgr's repo_tree_state shape, and the point
# of re-taking it is that a commit MOVES THE TREE for anything comparing against
# a pre-run stamp -- it does not change a file's CONTENT, which is why it feels
# safe. This one runs in THIS checkout, which is the object a reader forgets to
# name: `git rev-parse` answers about the tree it is run in and no other. There
# are twenty checkouts on this box and a push moves none of their HEADs.
tree_state() {
  printf '%s+%s' \
    "$(cd "$R" && git rev-parse --short=12 HEAD)" \
    "$(cd "$R" && git status --porcelain -- compiler lib | sha256sum | cut -c1-8)"
}
T0=$(tree_state)

echo "tree      $T0   (this checkout: $R)"
echo "leg A     $A  sha $SA"
echo "leg B     $B  sha $SB"
echo "corpus    $F"

run_leg() {
  _bin=$1; _out=$2
  if [ -n "${PXX_CORPUS_AB_LIST:-}" ]; then
    PXXBIN="$_bin" PXX_CORPUS_LIST="$PXX_CORPUS_AB_LIST" \
      "$R/tools/fpc_compiler_corpus_probe.sh" "$F" > "$_out" 2>"$_out.stderr"
  else
    PXXBIN="$_bin" \
      "$R/tools/fpc_compiler_corpus_probe.sh" "$F" > "$_out" 2>"$_out.stderr"
  fi
}

echo "--- leg A running"
run_leg "$A" "$O/legA.txt"
echo "--- leg B running"
run_leg "$B" "$O/legB.txt"

# ASSERT THE PRECONDITION, NOT JUST THE COMPARISON -- and this guard exists
# because the first run of this script did exactly what it guards against. Both
# legs wrote ZERO rows, the join compared two empty files, found no difference in
# either direction, printed `identical=0 moved=0 gained=0 regressed=0`, exited 0
# and emitted FPC-CORPUS-AB-COMPLETE. The header three screens up tells the
# reader to trust that token over the exit code, and the token was GREEN ON AN
# EMPTY RUN: a completion token is a claim about the SCRIPT REACHING THE END, not
# about the data. A join whose inputs were never proven to exist cannot fail, so
# the token is now emitted only after they are.
for leg in A B; do
  eval "_f=\$O/leg$leg.txt"
  if [ ! -s "$_f" ]; then
    echo "FAILED: leg $leg produced NO rows -- see $_f.stderr" >&2
    sed 's/^/  /' "$_f.stderr" >&2
    exit 1
  fi
  if ! grep -q '^SUMMARY' "$_f"; then
    echo "FAILED: leg $leg has no SUMMARY line -- the sweep did not finish" >&2
    exit 1
  fi
done

T1=$(tree_state)
if [ "$T0" != "$T1" ]; then
  echo "WARNING   the source tree MOVED during this run ($T0 -> $T1)."
  echo "WARNING   lib/rtl reaches from the live tree, so the two legs may not"
  echo "WARNING   have been measured against the same RTL. Re-run from a settled tree."
fi

# THE JOIN. Keyed on unit, which is the only column both legs agree on by
# construction; the first-error text is what MOVES and is therefore the payload.
# Deliberately NOT keyed on the line number: a conditional-directive refusal
# reported the LEXER's position until ec8a4d88c, so rows from either side of that
# fix differ in a column that says nothing about the corpus.
awk '
  FNR==NR {
    if ($1 == "SUMMARY") { sumA = sumA $0; next }
    u = $1; v = $2
    if (u != "BOTH-OK" && u != "ORACLE-NO" && u != "PXX-FAIL") next
    $1 = ""; $2 = ""; sub(/^[ \t]+/, "")
    vA[v] = u; msgA[v] = $0
    next
  }
  {
    if ($1 == "SUMMARY") { sumB = sumB $0; next }
    vb = $1; u = $2
    if (vb != "BOTH-OK" && vb != "ORACLE-NO" && vb != "PXX-FAIL") next
    $1 = ""; $2 = ""; sub(/^[ \t]+/, "")
    mb = $0
    seen[u] = 1
    if (!(u in vA)) { printf "ONLY-IN-B  %-16s %s\n", u, vb; nonly++; next }
    if (vA[u] != vb) {
      tag = (vA[u] == "BOTH-OK") ? "REGRESSED" : ((vb == "BOTH-OK") ? "GAINED" : "VERDICT")
      printf "%-10s %-16s A=%s  B=%s\n", tag, u, vA[u], vb
      if (tag == "REGRESSED") nreg++; else if (tag == "GAINED") ngain++; else nverd++
      next
    }
    if (msgA[u] != mb) {
      printf "MOVED      %-16s\n  A: %s\n  B: %s\n", u, msgA[u], mb
      nmoved++; next
    }
    nsame++
  }
  END {
    for (u in vA) if (!(u in seen)) { printf "ONLY-IN-A  %-16s %s\n", u, vA[u]; nonly++ }
    printf "\nJOIN       identical=%d moved=%d gained=%d regressed=%d other-verdict=%d only-in-one=%d\n",
           nsame+0, nmoved+0, ngain+0, nreg+0, nverd+0, nonly+0
    printf "A          %s\n", sumA
    printf "B          %s\n", sumB
  }
' "$O/legA.txt" "$O/legB.txt" | tee "$O/join.txt"

echo "rows      $O/legA.txt  $O/legB.txt  $O/join.txt"
echo "FPC-CORPUS-AB-COMPLETE"
