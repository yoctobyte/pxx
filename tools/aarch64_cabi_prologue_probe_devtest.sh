#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Positive controls for tools/aarch64_cabi_prologue_probe.sh.
#
# WHY THIS EXISTS. That probe compares a register list extracted from clang's
# aarch64 asm against one extracted from pxx's. Until 2026-09-22 an oracle that
# produced NOTHING extractable led to a confident verdict in BOTH directions,
# from one root cause, depending only on which branch the empty output landed
# in:
#
#   empty and NOT stack-passed-shaped -> BROKEN row -> rc=1 -> "verdict:
#       DISAGREEMENT", printed three lines under the probe's own correct prose
#       saying "this is an INSTRUMENT failure, not a result". A false
#       ACCUSATION about the compiler. This is borg's observed condition and a
#       peer found it by reading the row's stored reason text.
#
#   empty and stack-passed-shaped -> every signature SKIPped -> rc=0 ->
#       "verdict: pxx's C prologue reads its REGISTER arguments where clang
#       puts them", exit 0, with ZERO signatures compared. A false
#       EXONERATION, and the more dangerous of the two, because nobody
#       investigates a green. Found only by BUILDING this control -- it had
#       never been observed in the wild.
#
# The stack-passed classifier reads clang's OWN shape (deliberately: see the
# probe's comment), so an oracle that emits nothing looks exactly like an
# oracle saying "this signature spills no registers". That is what couples the
# two failure modes to one cause.
#
# HOW THE CONTROL WORKS. A fake clang that is PRESENT, answers -print-targets
# with aarch64 so it passes the probe's capability gate, and writes an EMPTY
# asm file. That is the one input the probe must never render as a verdict.
# Manufacturing it matters: the probe's real failure lives on a host this
# checkout cannot reach, and a control drawn from a working box cannot produce
# the outcome under test.
#
# Run:  tools/aarch64_cabi_prologue_probe_devtest.sh
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROBE="$ROOT/tools/aarch64_cabi_prologue_probe.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILED=0

ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n       %s\n' "$1" "${2-}"; FAILED=$((FAILED + 1)); }

[ -x "$PROBE" ] || { echo "devtest: probe not executable at $PROBE" >&2; exit 2; }

# ---------------------------------------------------------------- fake oracles
mkdir -p "$WORK/bin"

# THE PROBE ASKS FOR ASM ON STDOUT (`-S ... -o -`), so a fake that writes to a
# FILE is not exercising anything. The first version of this file did exactly
# that: it parsed `-o` and wrote to that path, which for `-o -` created a file
# literally named `-` in the repo root and left the probe reading EMPTY STDOUT.
# Both fakes therefore produced the identical condition, and case 3 was not
# testing the branch it claimed -- the control did not reach the subject by the
# route under test. Write to stdout; honour `-o <path>` only if a real path is
# given, so the fakes stay honest if the probe ever changes.
emit_fake() {   # $1 = dest script, $2 = the asm body to emit (may be empty)
    cat > "$1" <<FEOF
#!/bin/sh
case " \$* " in *" -print-targets "*)
  echo "    aarch64     - AArch64 (little endian)"; exit 0 ;;
esac
case " \$* " in *" --version "*) echo "fake clang (devtest oracle)"; exit 0 ;; esac
out="-"; prev=""
for a in "\$@"; do case "\$prev" in -o) out="\$a";; esac; prev="\$a"; done
body=\$(printf '%s' '$2')
if [ "\$out" = "-" ]; then
  [ -n "\$body" ] && printf '%s\n' "\$body"
else
  if [ -n "\$body" ]; then printf '%s\n' "\$body" > "\$out"; else : > "\$out"; fi
fi
exit 0
FEOF
    chmod +x "$1"
}

# (1) present, targets aarch64, emits NOTHING at all. The stack-passed
#     classifier reads clang's own shape, so "no stores" looks exactly like
#     "spills no registers" -- every row SKIPs. This is the false-GREEN branch.
emit_fake "$WORK/bin/clang-empty" ""

# (2) present, targets aarch64, emits a recognisable `f:` prologue containing
#     NO stores, so the extractor returns an empty list WITHOUT the row being
#     classified stack-passed. This is borg's branch: BROKEN, not SKIP, and the
#     one the old code rendered as `verdict: DISAGREEMENT`.
emit_fake "$WORK/bin/clang-garbage" 'f:
	sub	sp, sp, #64
	nop
	ret'

run_probe() {   # $1 = fake clang ; prints exit code, log in $WORK/out
    CLANG="$1" "$PROBE" > "$WORK/out" 2>&1
    echo $?
}

# ----------------------------------------------------- 1. the real oracle
echo "case 1: the REAL clang on this box -- the probe must still work"
if command -v clang >/dev/null 2>&1 \
   && clang -print-targets 2>/dev/null | grep -q '^ *aarch64 '; then
    rc=$(run_probe clang)
    # THE GATE ABOVE CHECKS ONE DEPENDENCY AND THIS ASSERTED AN OUTCOME THAT
    # NEEDS TWO. The probe needs clang AND a working disassembler; `command -v
    # clang` says nothing about the second, and on the box this was written on
    # llvm-objdump-21 is installed, so the gap was SILENT BY CONSTRUCTION where
    # it was developed. It reddened borg's full tier on 2026-09-22 -- the host
    # with no llvm-objdump-21, which is precisely the condition the probe's
    # `exit 2` was created to report. A guard that calls a correctly-reported
    # instrument failure a failure is the three-outcomes hole one level up,
    # inside the thing written to close it.
    #
    # PRINT THE rc BEFORE ROUTING IT, and do not put the print on the failure
    # branch: once 2 is a SKIP that branch is not taken on the only host where
    # this fires, and the two repairs would cancel exactly where both are
    # needed. The value is the whole point -- 2 means "the instrument cannot
    # run here" and corroborates the missing-disassembler candidate for
    # test-aarch64#00 on a host nobody has to visit; 1 means a REAL pxx/clang
    # disagreement there and points somewhere else entirely. Failing on `rc !=
    # 0` cannot tell those apart, so the old row was evidence of nothing.
    if [ "$rc" != 0 ]; then
        printf '       probe exit=%s -- %s\n' "$rc" \
               "$(grep -iE 'verdict|does not run|INSTRUMENT' "$WORK/out" | tail -1)"
    fi
    case "$rc" in
      0) ok "real clang: exit 0"
         grep -q 'agree with clang' "$WORK/out" \
             && ok "real clang: printed a comparison" \
             || bad "real clang: no comparison line" ;;
      2) echo "  SKIP real clang present but the probe cannot run here (exit 2:"
         echo "       instrument failure, almost certainly no llvm-objdump). NOT a"
         echo "       pass and NOT a pxx result -- the rc is printed above so the"
         echo "       next reader can tell 2 from 1 without re-running." ;;
      *) bad "real clang: exit $rc, expected 0 or a clean SKIP at 2" \
             "$(tail -3 "$WORK/out")" ;;
    esac
    # A green here must have compared something. This is the guard that the
    # false-exoneration bug defeated.
    if grep -qE '^aarch64 C-ABI prologue: 0 signature' "$WORK/out" \
       && [ "$rc" = 0 ]; then
        bad "real clang: exit 0 with ZERO signatures compared" \
            "that is the false-green bug this file exists for"
    else
        ok "real clang: a green means signatures were compared"
    fi
else
    echo "  SKIP real clang absent or cannot target aarch64 -- and note this"
    echo "       is NOT a pass: the cases below are the ones that matter, and"
    echo "       they do not need a real clang."
fi

# ------------------------------- 2. POSITIVE CONTROL: empty, stack-shaped
echo "case 2: POSITIVE CONTROL -- oracle emits nothing (false-GREEN branch)"
rc=$(run_probe "$WORK/bin/clang-empty")
[ "$rc" = 2 ] && ok "exit 2 (instrument error)" \
              || bad "exit $rc, expected 2" "$(tail -3 "$WORK/out")"
grep -qi 'verdict: NOT VERIFIED\|INSTRUMENT FAILURE' "$WORK/out" \
    && ok "verdict names it as unverified/instrument failure" \
    || bad "verdict does not say unverified" "$(grep -i verdict "$WORK/out")"
grep -qi "reads its REGISTER arguments where clang puts them" "$WORK/out" \
    && bad "CLAIMED THE GREEN VERDICT with a dead oracle" \
           "this is exactly the pre-2026-09-22 behaviour" \
    || ok "does NOT claim the green verdict"
grep -qi 'verdict: DISAGREEMENT' "$WORK/out" \
    && bad "blamed pxx for a dead oracle" "$(grep -i verdict "$WORK/out")" \
    || ok "does NOT blame pxx"

# ----------------------- 3. POSITIVE CONTROL: unreadable, not stack-shaped
echo "case 3: POSITIVE CONTROL -- oracle emits unreadable asm (borg's branch)"
rc=$(run_probe "$WORK/bin/clang-garbage")
[ "$rc" = 2 ] && ok "exit 2 (instrument error)" \
              || bad "exit $rc, expected 2" "$(tail -4 "$WORK/out")"
grep -qi 'verdict: DISAGREEMENT' "$WORK/out" \
    && bad "verdict says DISAGREEMENT for an instrument failure" \
           "this is the defect found on borg 2026-09-22" \
    || ok "does NOT say DISAGREEMENT"
grep -qi "reads its REGISTER arguments where clang puts them" "$WORK/out" \
    && bad "claimed the green verdict" || ok "does NOT claim the green verdict"

# --------------------------------------------- 4. the exit codes are distinct
echo "case 4: the three exits mean three different things"
a=$(run_probe "$WORK/bin/clang-empty")
b=$(run_probe "$WORK/bin/clang-garbage")
[ "$a" = 2 ] && [ "$b" = 2 ] \
    && ok "both instrument failures exit 2, never 1" \
    || bad "instrument failures did not both exit 2" "got $a and $b"

# ------------------------------- 5. the DISASSEMBLER gate, which was ungated
# `pxx_regs` disassembles with a hard-coded `llvm-objdump-21`. Nothing checked
# it existed, so on a host with an older toolchain the PXX side came back empty
# for every signature and the run blamed the compiler. These two rows are the
# control for that gate, and they exist because the FIRST version of the gate
# checked that the NAME was non-empty rather than that the TOOL RAN -- which an
# explicit LLVM_OBJDUMP=/nonexistent satisfies, reproducing the exact defect
# within minutes of the fix.
echo "case 5: disassembler NAMED but absent -- must not blame pxx"
LLVM_OBJDUMP=/nonexistent/llvm-objdump "$PROBE" > "$WORK/out" 2>&1
rc=$?
[ "$rc" = 2 ] && ok "exit 2" || bad "exit $rc, expected 2" "$(tail -3 "$WORK/out")"
# The `does not run` arm of this alternation is DEAD as of 2026-09-24 -- the
# probe emits "does not DECODE" for both this case and case 6, and `does not
# run` occurs zero times in it. Dropped rather than left in place: an
# alternation whose arms are not all live makes a guard look broader than it
# is, and the dead arm is invisible because the surviving arm carries the row.
# Found by grepping the SIBLING assertion while fixing case 6, not by a red.
grep -qi 'INSTRUMENT failure' "$WORK/out" \
    && ok "names it an instrument failure" || bad "no instrument-failure line"
grep -qi 'pxx-side broken' "$WORK/out" \
    && bad "blamed pxx for a missing disassembler" "$(tail -3 "$WORK/out")" \
    || ok "does NOT blame pxx"

echo "case 6: disassembler RUNS but is not a disassembler (/bin/true)"
# The nastiest shape: the tool exists, exits 0, and emits nothing. pxx compiles
# both objects fine, so only an assertion that the DISASSEMBLY is non-empty can
# tell this from a broken prologue.
# One spelling, used for both the invocation and the assertion below, so the
# two cannot silently drift apart into testing different tools.
BADDUMP=/bin/true
LLVM_OBJDUMP="$BADDUMP" "$PROBE" > "$WORK/out" 2>&1
rc=$?
[ "$rc" = 2 ] && ok "exit 2" || bad "exit $rc, expected 2" "$(tail -4 "$WORK/out")"
grep -qi 'verdict: DISAGREEMENT' "$WORK/out" \
    && bad "blamed pxx for a tool that emits nothing" "$(grep -i verdict "$WORK/out")" \
    || ok "does NOT say DISAGREEMENT"
# WHAT THIS ROW IS FOR, STATED AS A PROPERTY BECAUSE IT USED TO BE A WORD.
# Until 2026-09-24 the assertion was `grep -qi 'DISASSEMBLER'`, and it went RED
# on `b5140a1f0` -- a commit that IMPROVED this message, replacing the word with
# a precise statement of what the tool failed to do ("does not DECODE a pxx
# aarch64 image"). Every property the row exists to protect was satisfied and
# the guard still failed, because it pinned the old message's SPELLING.
#
# The shape is the guarded commit's own lesson one level up: `b5140a1f0`
# replaced selecting the disassembler BY NAME with selecting it BY CAPABILITY,
# and the guard over it still asserted on a name. An assertion that pins a
# diagnostic's wording fails on every improvement to that wording, and it fails
# in the direction that reads as a regression in the thing that improved.
#
# AND IT WAS WRONG IN BOTH DIRECTIONS, WHICH IS WHY THIS IS NOT MERELY A STALE
# STRING. Measured against four synthetic outputs: the old assertion FAILED on
# the correct improved message (the false red T bisected) and PASSED on a
# message reading "the disassembler produced no instructions" -- which names no
# tool and identifies no side. The word it pinned was incidental to the
# property, so it tracked the message's VOCABULARY, which correlates with the
# property only by convention. The two rows below fail independently of each
# other (verified: one control breaks each), and both fail together on a
# message that blames pxx, which is the defect this case exists for.
#
# So: two orthogonal properties, each separately falsifiable. Note case 5 above
# was already written this way -- the sibling arm was correct and this one was
# not, which is why grepping for the OTHER SPELLING'S HANDLER beats grepping for
# the feature.
grep -qF "$BADDUMP" "$WORK/out" \
    && ok "names the offending tool by its value" \
    || bad "does not name which tool failed" "$(tail -4 "$WORK/out")"
grep -qi 'INSTRUMENT failure' "$WORK/out" \
    && ok "attributes the failure to the INSTRUMENT, not to pxx" \
    || bad "does not identify which side failed" "$(tail -4 "$WORK/out")"

echo
if [ "$FAILED" -gt 0 ]; then
    echo "FAILED: $FAILED row(s)"
    exit 1
fi
echo "all aarch64-prologue control rows pass"
