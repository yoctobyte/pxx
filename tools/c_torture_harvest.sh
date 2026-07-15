#!/usr/bin/env bash
# One-time gcc c-torture MISCOMPILE HARVEST for pxx (Track T tool).
#
# NOT a gate, NOT a runner, NOT wired into any tier — a manual one-shot that finds
# pxx miscompiles in the vendored gcc c-torture execute corpus and buckets them for
# triage into the owning lane (IR/codegen -> A, cfront -> C, crtl -> B). See
# devdocs/progress/backlog/feature-t-gcc-torture-runner.md (downscoped: the permanent
# runner + skip-file ratchet was dropped as dialect-gap busywork).
#
# Method: compile each self-checking program with pxx; a COMPILE failure is a
# dialect/GNU-extension gap (skip, not a bug); a COMPILE HANG (non-termination) or a
# nonzero RUN exit is a candidate. Then CROSS-CHECK candidates against gcc.
#
# CRITICAL RULE (user, 2026-07-15): do NOT auto-dismiss a candidate just because gcc
# "also fails". gcc is a cross-check, not ground truth. A naive `gcc <f>` fails to
# LINK libm at -O0 (floor/sin/... need -lm) and folds them away at -O2 — so a real
# pxx bug (float-floor.c: a double global initializer folding to 0.0) once got dropped
# as "gcc also fails". So: retry gcc with -O2 AND -lm before believing gcc fails, and
# when gcc genuinely fails too, put the program in a BOTH-FAIL bucket to INVESTIGATE
# (a shared bug, a gcc bug, or a feature the program itself requires) — never a silent
# discard. Same "earn the dismissal" discipline pasmith applies to its FPC oracle.
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CC="$ROOT/compiler/pascal26"
SUITE="$ROOT/library_candidates/gcc-torture/execute"
OUT="${1:-/tmp/c_torture_harvest}"
mkdir -p "$OUT"
: > "$OUT/pxx_only.txt"          # gcc passes, pxx wrong  -> real pxx bug (the queue)
: > "$OUT/both_fail.txt"         # gcc ALSO fails (even -O2 -lm) -> INVESTIGATE, not drop
: > "$OUT/feature_gap.txt"       # program declares a dg-options flag pxx lacks (legit)
: > "$OUT/compilefail.txt"       # pxx compile gap (dialect) -> not a bug
bin="$OUT/b"; g="$OUT/g"; log="$OUT/clog"
n=0; pass=0; cfail=0; pxxonly=0; both=0; fgap=0

gcc_passes() {  # try hard before believing gcc fails: -O2 and -O0, each with -lm
  local f="$1"
  for opt in -O2 -O0; do
    if timeout 25 gcc -w $opt "$f" -lm -o "$g" 2>/dev/null && timeout 15 "$g" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

for f in "$SUITE"/*.c; do
  n=$((n+1)); rm -f "$bin"
  timeout 25 "$CC" -I"$ROOT/lib/crtl/include" -I"$ROOT/lib/crtl/src" "$f" "$bin" > "$log" 2>&1
  crc=$?
  base=$(basename "$f")
  if [ "$crc" -eq 124 ]; then                       # pxx compile HANG = candidate
    if gcc_passes "$f"; then echo "$base	compile-hang" >> "$OUT/pxx_only.txt"; pxxonly=$((pxxonly+1))
    else echo "$base	compile-hang	gcc-also-fails" >> "$OUT/both_fail.txt"; both=$((both+1)); fi
    continue
  fi
  if [ "$crc" -ne 0 ] || [ ! -x "$bin" ]; then       # pxx compile gap (dialect)
    cfail=$((cfail+1)); echo "$base	$(grep -m1 -iE 'error' "$log" | head -c 140)" >> "$OUT/compilefail.txt"; continue
  fi
  timeout 15 "$bin" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then pass=$((pass+1)); continue; fi
  case $rc in 124) t=timeout;; 134) t=abort;; 139) t=segv;; 136) t=fpe;; *) t="exit$rc";; esac
  if gcc_passes "$f"; then
    pxxonly=$((pxxonly+1)); echo "$base	$t" >> "$OUT/pxx_only.txt"
  elif grep -qE 'dg-options|dg-require' "$f"; then     # program declares a needed feature
    fgap=$((fgap+1)); echo "$base	$t	$(grep -m1 -oE 'dg-(options|require)[^*]*' "$f" | head -c 80)" >> "$OUT/feature_gap.txt"
  else
    both=$((both+1)); echo "$base	$t	gcc-also-fails-INVESTIGATE" >> "$OUT/both_fail.txt"
  fi
done
echo "=== c-torture harvest: $n programs ==="
echo "  pass=$pass  dialect-compile-gap=$cfail"
echo "  pxx-only miscompiles (the queue) = $pxxonly  -> $OUT/pxx_only.txt"
echo "  BOTH-fail (investigate, NOT dropped) = $both  -> $OUT/both_fail.txt"
echo "  feature-gap (program requires a dg flag) = $fgap  -> $OUT/feature_gap.txt"
