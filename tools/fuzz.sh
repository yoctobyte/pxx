#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# fuzz.sh — mutation-seeded, cross-target-differential IR correctness fuzzer.
# See devdocs/progress/working/feature-ir-fuzzer.md for the design writeup.
#
# Picks a random seed from test/*.pas, applies a small textual mutation,
# compiles it for x86-64 (native) and i386/aarch64/arm32 (QEMU), runs all
# four, and diffs stdout+exit code. A mismatch against native is a candidate
# real bug (backend/codegen divergence); a compile failure on the mutant is
# expected/uninteresting (mutation produced invalid Pascal) and is skipped,
# not reported.
#
# Usage:
#   tools/fuzz.sh [--minutes N] [--seed-glob 'test/*.pas']
#
# Time-boxed by design (see ticket "no run-forever" note) — always exits
# after the requested budget, reporting a summary either way. A clean run
# (no divergence found) is a valid, useful result, not a failure.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PXX="${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}"
MINUTES=10
# Default seed pool: files the project already designates as fair
# cross-target comparisons (naming convention: test_cross_*.pas, per
# Makefile's cross-bootstrap targets). Deliberately NOT test/*.pas broadly --
# a first run found "divergences" that were actually raw-syscall /
# ESP-specific fixtures (__pxxrawsyscall hardcodes syscall numbers, which
# legitimately differ per architecture ABI) never meant for naive
# same-output-on-every-target comparison. Verify any new glob against that
# false-positive shape before widening the pool.
SEED_GLOB="test/test_cross_*.pas"
FINDINGS_DIR="${FUZZ_FINDINGS_DIR:-/tmp/pxx_fuzz_findings}"
SCRATCH="$(mktemp -d /tmp/pxx_fuzz.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) MINUTES="$2"; shift 2 ;;
    --seed-glob) SEED_GLOB="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

test -x "$PXX" || { echo "no stable compiler at $PXX" >&2; exit 1; }
mkdir -p "$FINDINGS_DIR"

# Collect the seed corpus once (glob against ROOT so relative paths are stable).
mapfile -t SEEDS < <(cd "$ROOT" && grep -L '__pxxrawsyscall\|CPU_XTENSA\|CPU_RISCV32\|PXX_ESP' $SEED_GLOB 2>/dev/null)
if [ "${#SEEDS[@]}" -eq 0 ]; then
  echo "no seeds matched $SEED_GLOB" >&2
  exit 1
fi
echo "fuzz.sh: ${#SEEDS[@]} seed files, budget ${MINUTES}m, findings -> $FINDINGS_DIR"

# --- one small textual mutation, applied to a copy of a seed file --------
# v1 mutation set: tweak a numeric literal by +/-1, or flip a comparison
# operator. Deliberately simple (see ticket's v1 non-goals — no real parser
# involved); most mutants will fail to compile, which is fine and expected.
mutate() {
  local src="$1" dst="$2"
  local kind=$(( RANDOM % 2 ))
  if [ "$kind" -eq 0 ]; then
    # bump the first integer literal found by +1 (best-effort, may no-op)
    awk '
      BEGIN{done=0}
      { if (!done && match($0, /[0-9]+/)) {
          n=substr($0, RSTART, RLENGTH) + 1
          $0 = substr($0,1,RSTART-1) n substr($0,RSTART+RLENGTH)
          done=1
        }
        print
      }' "$src" > "$dst"
  else
    # flip the first comparison operator found
    sed '0,/<>/{s/<>/=/}; 0,/ < /{s/ < / <= /}; 0,/ > /{s/ > / >= /}' "$src" > "$dst"
  fi
}

# --- compile+run one target, echoing "EXIT:<code> OUT:<stdout>" ----------
# A mutant is untrusted code -- a flipped comparison or bumped loop bound can
# trivially turn a terminating loop into an infinite one, so EVERY execution
# (compile is safe/bounded already; running the mutant is not) goes through
# `timeout`. A run that times out is reported as its own distinct exit code
# (124, timeout's convention) rather than hanging the whole fuzz session --
# and a native-vs-cross TIMEOUT/TIMEOUT match is NOT a divergence (both sides
# agreeing "this hangs" is uninteresting), only a mismatched timeout is.
RUN_TIMEOUT="${FUZZ_RUN_TIMEOUT:-5}"

run_target_capture() {
  local arch="$1" src="$2" outbin="$3"
  if [ "$arch" = "x86_64" ]; then
    "$PXX" -Fu"$ROOT/lib/rtl" "$src" "$outbin" >/dev/null 2>&1 || return 2
    local out; out=$(timeout "$RUN_TIMEOUT" "$outbin" 2>&1); local code=$?
  else
    "$PXX" -Fu"$ROOT/lib/rtl" --target="$arch" "$src" "$outbin" >/dev/null 2>&1 || return 2
    local out; out=$(timeout "$RUN_TIMEOUT" "$ROOT/tools/run_target.sh" "$arch" "$outbin" 2>&1); local code=$?
  fi
  if [ "$code" -eq 124 ]; then out="<TIMEOUT>"; fi
  printf 'EXIT:%d OUT:%s' "$code" "$out"
}

START=$(date +%s 2>/dev/null || echo 0)
END=$(( START + MINUTES * 60 ))
TRIALS=0 COMPILED=0 DIVERGED=0

while :; do
  NOW=$(date +%s 2>/dev/null || echo 0)
  [ "$NOW" -ge "$END" ] && break
  TRIALS=$(( TRIALS + 1 ))

  seed="${SEEDS[$((RANDOM % ${#SEEDS[@]}))]}"
  mutant="$SCRATCH/mutant_$TRIALS.pas"
  mutate "$ROOT/$seed" "$mutant"

  native_res=$(run_target_capture x86_64 "$mutant" "$SCRATCH/m${TRIALS}_x86_64")
  [ $? -eq 2 ] && continue   # mutant didn't even compile natively -- uninteresting, skip
  COMPILED=$(( COMPILED + 1 ))
  case "$native_res" in
    *'<TIMEOUT>'*) continue ;;  # native itself hangs (likely a mutated infinite loop) -- uninteresting, skip the cross checks too
  esac

  bad=0
  for arch in i386 aarch64 arm32; do
    res=$(run_target_capture "$arch" "$mutant" "$SCRATCH/m${TRIALS}_${arch}")
    rc=$?
    if [ "$rc" -eq 2 ]; then
      continue   # cross-compile failed for this arch specifically -- log, not a divergence
    fi
    if [ "$res" != "$native_res" ]; then
      bad=1
      echo "DIVERGENCE: seed=$seed trial=$TRIALS arch=$arch"
      echo "  native: $native_res"
      echo "  $arch:  $res"
      cp "$mutant" "$FINDINGS_DIR/trial_${TRIALS}_${arch}.pas"
      {
        echo "seed=$seed arch=$arch"
        echo "native: $native_res"
        echo "$arch: $res"
      } > "$FINDINGS_DIR/trial_${TRIALS}_${arch}.txt"
    fi
  done
  [ "$bad" -eq 1 ] && DIVERGED=$(( DIVERGED + 1 ))
done

echo "fuzz.sh: done. trials=$TRIALS compiled=$COMPILED diverged=$DIVERGED"
if [ "$DIVERGED" -gt 0 ]; then
  echo "fuzz.sh: candidate divergences saved under $FINDINGS_DIR -- minimize + file as a bug ticket"
  exit 1
fi
exit 0
