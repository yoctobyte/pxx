#!/usr/bin/env bash
# One command that runs a lane's gate to completion and prints ONE summary.
#
# Why this exists: an agent that backgrounds `make test-nilpy` and then polls it
# with `sleep 600; tail log` burns a conversation turn per poll and learns
# nothing. Background THIS script instead — it exits when the gate is done, so
# the completion notification IS the result. One task, one answer.
#
#   tools/gate.sh quick     self-host fixedpoint + testmgr quick  (~30s)
#   tools/gate.sh lib       lib-test (Track B/E)
#   tools/gate.sh full      quick + test-nilpy + make test  (only when T is down)
#   tools/gate.sh check     print what would run, and the box's state
#
# Exit status is the gate's: 0 = green. The summary names every step and its
# result, so a failure does not need the logs to be located first.
set -uo pipefail

MODE="${1:-quick}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

LOGDIR="${TMPDIR:-/tmp}/pxx-gate-$$"
mkdir -p "$LOGDIR"
PINNED="stable_linux_amd64/default/pinned"

# Track T's watcher runs testmgr on whatever box it lives on, and a full matrix
# run saturates the CPU. A gate that would otherwise take 15 minutes takes 45
# next to one, which reads as "hung" if you do not know it is there. Say so up
# front rather than letting the wait be a mystery.
note_contention() {
  local others load
  # pgrep -c PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` appends a
  # second zero and every later `[ "$others" -gt 0 ]` dies with "integer
  # expression expected". Recover on the assignment's status instead.
  others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null) || others=0
  load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo '?')
  if [ "${others:-0}" -gt 0 ]; then
    echo "gate: NOTE Track T tooling is running here ($others process(es)), load $load"
    echo "gate:      expect this to take 2-3x longer than on an idle box"
  else
    echo "gate: box idle-ish (load $load)"
  fi
}

step() {           # step <name> <logfile> <command...>
  local name="$1" log="$2"; shift 2
  local start end
  start=$(date +%s)
  if "$@" > "$log" 2>&1; then
    end=$(date +%s)
    echo "  PASS  $name  ($((end - start))s)"
    return 0
  fi
  end=$(date +%s)
  echo "  FAIL  $name  ($((end - start))s)  log: $log"
  tail -n 15 "$log" | sed 's/^/        /'
  return 1
}

fixedpoint() {     # self-host from the PINNED seed — DELEGATED, not re-implemented
  # This used to open-code three rounds and assert A == B == C, where A is built
  # by pinned and B by A. That demands that PINNED ALREADY EMITS WHAT HEAD EMITS,
  # which is false by construction for any change to the compiler's own codegen —
  # add a builtin and B legitimately gains symbols A lacks. So the gate went RED
  # on the normal case, one generation early, and could not go green again until
  # `make pin` ran.
  #
  # It is the exact mistake the Makefile's $(COMPILER) rule documents as wrong
  # (chore-makefile-selfhost-iterate-to-convergence): "a stale seed legitimately
  # needs an extra round ... demanding one pass is what made a normal bootstrap
  # look like a failure." gate.sh reimplemented the check inline and reintroduced
  # the bug it had already been fixed for elsewhere — so the fix is to stop having
  # a second implementation at all.
  #
  # tools/selfhost_fixedpoint.sh is authoritative: it iterates to MAX_ROUNDS and
  # additionally enforces the anti-Thompson property (the hermetic fixedpoint must
  # equal compiler/pascal26), which the inline version never checked. It also
  # PRINTS ITS REASON — the old function sent every round to /dev/null, so a FAIL
  # line sat above a 0-byte fixedpoint.log and named no cause, which is what turned
  # each occurrence into a manual bisect.
  #
  # Exit 77 is its "no pinned stable" skip and must not read as a gate failure.
  tools/selfhost_fixedpoint.sh
  local rc=$?
  if [ "$rc" = 77 ]; then
    echo "SKIP: no pinned stable to seed from — self-host gate not run"
    return 0
  fi
  [ "$rc" = 0 ] || stale_binary_hint
  return "$rc"
}

# The check above is honest — "the binary we test with is not the one these
# sources define" is TRUE when compiler/pascal26 is merely old. But its stated
# causes ("local seed contamination, or a self-perpetuating miscompile") send you
# hunting a miscompile, when on a shared checkout the overwhelmingly common cause
# is that a SIBLING landed a compiler change and nobody rebuilt here yet.
#
# It cost two full gate runs on two consecutive days (2026-08-12, -13) before
# anyone noticed the pattern: the gate's own testmgr step rebuilds the binary as
# a side effect, so the FIRST run after a sibling's commit always fails and the
# re-run always passes, which reads as flakiness rather than staleness.
#
# Deliberately a hint, not a fix: gate.sh must NOT rebuild before comparing, or
# it loses the ability to catch a genuinely contaminated binary — which is the
# entire point of the anti-Thompson check.
stale_binary_hint() {
  local newest binmt
  newest=$(git log -1 --format=%ct -- compiler/ 2>/dev/null) || return 0
  binmt=$(stat -c %Y compiler/pascal26 2>/dev/null) || return 0
  [ -n "$newest" ] && [ -n "$binmt" ] || return 0
  if [ "$binmt" -lt "$newest" ]; then
    echo "gate: NOTE compiler/pascal26 is OLDER than the last commit touching"
    echo "gate:      compiler/ ($(git log -1 --format='%h %s' -- compiler/ | cut -c1-60))"
    echo "gate:      That is a STALE BINARY, not a miscompile — a sibling landed a"
    echo "gate:      compiler change and this checkout has not rebuilt."
    echo "gate:      Run 'make compiler/pascal26' (~12s) and re-gate."
  fi
}

# The seam between the pinned binary's FROZEN builtin RTL and the repo's LIVE
# lib/rtl. `make pin` copies compiler/builtin/** into
# stable_linux_amd64/default/builtin/, so from that moment the pinned compiler
# builds a frozen builtin set against whatever lib/rtl says TODAY. A Track A
# change that adds a builtin and uses it from lib/rtl is coherent, self-hosts,
# and passes the whole quick gate -- and breaks every $(PXX_STABLE) build the
# instant it lands, because `pinned` still has the pre-change builtin.
#
# That happened on 97b1812fe: `undefined variable (PXXNilRefHook)`, and Tracks
# B, D and E were dead on master until the next pin. It was found by accident,
# by an unrelated scratch compile. Nothing stood in this seam, because both
# halves of `gate.sh quick` build with the FRESHLY BUILT compiler -- the gate
# was not weak here, it was looking somewhere else entirely.
#
# Compile only; running the program is not the point. Any live-RTL/frozen-
# builtin mismatch IS a compile error, which is the entire failure mode.
# ~1s, so it runs in every mode rather than earning its own tier.
#
# Proven failable before landing (a canary that has never been seen to fail is
# not yet a canary): in a scratch copy of the tree, adding one reference to an
# absent builtin in lib/rtl/sysutils.pas reproduces the original error shape
# and exit 1.
pinned_rtl_canary() {
  local pin=stable_linux_amd64/default/pinned
  local src=test/test_uses_sysutils.pas
  local bin="$LOGDIR/pinned-rtl-canary.bin"
  [ -x "$pin" ] || { echo "gate: (no pinned binary at $pin)"; return 0; }
  [ -f "$src" ] || { echo "gate: (canary fixture $src is gone)"; return 0; }
  "./$pin" "$src" "$bin" || {
    echo "^^ the PINNED binary cannot COMPILE the tree's lib/rtl."
    echo "   An 'undefined variable' naming a lib/rtl unit means a commit added"
    echo "   a builtin and used it from lib/rtl without a pin: coherent, self-"
    echo "   hosts, and breaks every \$(PXX_STABLE) build until someone pins."
    echo "   The change is usually RIGHT and the remedy is a pin, not a revert."
    return 1
  }
  # ...and then RUN it. Near-zero, and it is a different question: the compile
  # answers "does the frozen builtin still satisfy lib/rtl's references", the
  # run answers "does the result work". A pinned RTL that compiles and then
  # dies is just as broken for Track B, and nothing else in the dev loop asks.
  # Reported apart from the compile so triage stays sharp -- a failure here is
  # NOT the frozen-builtin seam.
  "$bin" >/dev/null 2>&1 || {
    echo "^^ the pinned binary COMPILED lib/rtl but the result did not run."
    echo "   That is not the frozen-builtin seam; it is an ordinary runtime"
    echo "   fault in the pinned RTL. Same impact on Track B, different owner."
    return 1
  }
}

echo "gate: mode=$MODE  logs=$LOGDIR"
note_contention

if [ "$MODE" = check ]; then
  echo "gate: would run:"
  case "${2:-quick}" in *) :;; esac
  echo "  quick -> self-host fixedpoint (pinned seed) | testmgr --tier quick   (~30s)"
  echo "  lib   -> make lib-test"
  echo "  full  -> quick + make test-nilpy + make test   (only when Track T is down)"
  # `{ cmd || echo ...; } | sed`, NOT `cmd | sed ... || echo ...`. The second
  # form was here and could never fire: `||` reads the PIPELINE's status, which
  # is sed's, and sed exits 0 on empty input -- so a missing or failing
  # twatch.py printed NOTHING where a status block belongs, and the fallback
  # that exists for exactly that case was unreachable for its whole life.
  # Measured: with the command exiting 3, the old form captured "" and the new
  # one captures the message; a succeeding command still passes through
  # unchanged (both arms asserted). One of three instances of this shape found
  # in one night across three agents -- `!`, `&&`/`||`, a pipe and `2>/dev/null`
  # each replace the exit status you asked for, and none of them says so.
  { tools/twatch.py --status 2>/dev/null || echo "(twatch status unavailable)"; } | sed 's/^/  /'
  # --status answers "is anyone covering the repo"; `trackt health` answers
  # "is the watcher on THIS box trustworthy right now", incl. alive-but-wedged.
  echo "  (watcher health on this box: tools/trackt.py health)"
  exit 0
fi

RC=0

# Before the case, so it covers quick, lib and full alike from ONE place. The
# three-branch version of this was the first draft; a check that has to be
# remembered in each new mode is the check that will be missing from the next
# one.
if [ -x stable_linux_amd64/default/pinned ] && [ -f test/test_uses_sysutils.pas ]
then
  step "pinned builds live lib/rtl" "$LOGDIR/pinned-rtl-canary.log" \
       pinned_rtl_canary                                              || RC=1
else
  echo "  SKIP  pinned builds live lib/rtl (no pinned binary or fixture)"
fi

# THE SEED CANARY. Same placement argument as the block above: before the case,
# so no mode can forget it.
#
# `make compiler/pascal26` compiles compiler.pas WITH PXX. So the per-fix loop --
# and the byte-identical self-host fixedpoint with it, our strongest signal --
# is blind BY CONSTRUCTION to breakage that only FPC sees, because the only
# compiler it ever consults is the one under test. pxx resolves names across the
# whole unit; FPC resolves in source order. A call placed above its declaration
# with no `forward;` therefore self-hosts green and makes `compiler.pas`
# uncompilable by FPC -- which is the path a fresh checkout with NO trusted
# binary must take to exist at all.
#
# Twice in two days, in two unrelated frontends (WasmDataAddr 2026-08-28,
# RExprRecId 2026-08-29), every gate green both times.
#
# tools/forwardlint.py already existed for this and exits 1 correctly. NOTHING
# INVOKED IT -- so it caught both and told no one. A trigger nobody is assigned
# to watch is not a trigger; that, not the missing check, was the defect.
#
# Costs ~5.5s: it reads the include stream, it does not build anything. (Was
# documented as ~1s until 2026-08-30 -- stale by 5x, and it was the figure three
# decide tickets inherited and argued the cost from. Measured three runs on
# plexus: 5.71 / 5.48 / 5.23. It grows with the include stream, so re-measure
# rather than trusting this line.)
if [ -f tools/forwardlint.py ] && [ -f compiler/compiler.pas ]; then
  step "fpc seed compiles (forward decls)" "$LOGDIR/forwardlint.log" \
       python3 tools/forwardlint.py                                   || RC=1
else
  echo "  SKIP  fpc seed compiles (no forwardlint.py or compiler.pas)"
fi

# THE ABI-ORACLE CHECK. Wired for the reason the forwardlint block above gives:
# a trigger nobody is assigned to watch is not a trigger. abi.inc's PREVIOUS
# enforcement was a review grep -- something a human had to remember to run and
# then read -- and it never fired once in its life, because it was calibrated to
# the spelling `IsRef or` rather than to the shape. It ended up matching exactly
# one line in the tree: a COMMENT quoting the rule. So the check was not merely
# dead, it had become actively reassuring.
#
# Runs in well under a second (a regex pass over 7 files; it builds nothing).
#
# It carries a BASELINE of known, filed disagreements rather than suppressing
# them, and it FAILS if a baseline entry matches nothing -- so the file cannot
# outlive its cause the way the grep did. --selftest holds 12 asserted controls.
# bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire
if [ -f tools/abi_oracle_lint.py ]; then
  step "backends ask the ABI oracle" "$LOGDIR/abi-oracle-lint.log" \
       python3 tools/abi_oracle_lint.py                              || RC=1
else
  echo "  SKIP  backends ask the ABI oracle (no abi_oracle_lint.py)"
fi

# IR OP NAME COVERAGE. IROpName's one load-bearing caller is the "unsupported
# node in IR codegen" error every backend raises, so an op it does not name
# reports itself as `unknown` on EVERY target and the only way to find out which
# op is missing is to edit the backend and self-compile. Seven of 75 were
# unnamed until 2026-08-31; IR_CLASSREF was found that expensive way, on xtensa.
#
# The gap could open because nothing counted -- the count that found it was a
# parser run once by hand. This is that parser, wired, so the eighth cannot open
# silently. Sub-second; it parses two files and builds nothing.
# bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown
if [ -f tools/iropname_lint.py ]; then
  step "IROpName names every IR op" "$LOGDIR/iropname-lint.log" \
       python3 tools/iropname_lint.py                                 || RC=1
else
  echo "  SKIP  IROpName names every IR op (no iropname_lint.py)"
fi

# THE UNWIRED-TEST CANARY. Same placement argument as the two blocks above --
# before the case, so no mode can forget it -- and the same failure it fixes as
# the forwardlint block: the checker already existed, already exited 1, and was
# invoked by nothing anyone reads in time.
#
# tools/check_test_wiring.py runs in limited+full as part of tools-devtest,
# which is right for the CENSUS (47 unwired files today, most in deferred lanes,
# expensive to act on) and useless for the author: frankwasm wrote nine tests on
# 2026-08-30, the checker named all nine and exited 1 all day, and one of them
# was a campaign's ACCEPTANCE test -- the fcl-json line the campaign existed for,
# quoted to three agents -- executed by nothing but its author's hand.
#
# This asks the cheap half instead: did THIS push add a file under test/ that no
# rule references? Scoped to origin/$BRANCH..HEAD, so it names what you just
# wrote and nobody inherits a backlog. The agent who wrote the file still has
# the oracle in their head; a sweep three weeks later has to reconstruct it.
#
# ~0.7s (measured three runs on plexus: 0.70 / 0.66 / 1.29, ~2-4% of quick's
# ~30s budget). Re-measure rather than trusting this line -- it scans the
# Makefile and tools/, so it grows with both.
#
# SKIPs loudly without an origin ref rather than passing: a check that reports
# success by not running is the exact defect check_test_wiring.py exists to
# remove, and `--since` returns 2 rather than 0 when it cannot scope.
GATE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)
if [ -f tools/check_test_wiring.py ] \
   && git rev-parse --verify -q "origin/$GATE_BRANCH" >/dev/null 2>&1; then
  step "this push wires the tests it adds" "$LOGDIR/test-wiring.log" \
       python3 tools/check_test_wiring.py --since "origin/$GATE_BRANCH" || RC=1
else
  echo "  SKIP  this push wires the tests it adds (no origin/$GATE_BRANCH ref)"
fi

case "$MODE" in
  quick|full)
    # QUICK = the native confirm CLAUDE.md actually prescribes: testmgr --tier
    # quick + self-host byte-identical, ~30s. It used to also run
    # `make test-nilpy`, which spent 625 of its 649 seconds in one suite -- a
    # full gate wearing the fast gate's name, in the mode agents are told to
    # reach for BETWEEN EDITS. Two 554s runs in one session, both green, both
    # finding nothing, is what filed this.
    #
    # Dropping it is safe now in a way it was not before:
    #   - `testmgr --tier quick` carries dense NilPy and C canaries as of
    #     feature-t-quick-canary-for-nilpy-and-c, so a gross NilPy break is
    #     still caught here, in ~1s;
    #   - the whole test-nilpy suite is enrolled in Track T's limited/full
    #     matrix, so it IS run -- offloaded, which is the entire point;
    #   - ten minutes is also long enough to overlap another build, which is
    #     the window bug-t-selfhost-build-uses-fixed-tmp-paths-colliding and
    #     feature-t-snapshot-compiler-binary-per-run are about.
    # FPC seed canary, started FIRST and in the BACKGROUND so it overlaps the
    # steps below instead of adding to them. Four separate "Identifier not
    # found" breaks landed on master in three days (PyMakeTruthy, PyBytesCi,
    # PyWiden, EmitAsmX64) — every one a routine called from an include that
    # sits EARLIER in compiler.pas than the file defining it. pxx's own
    # frontend resolves all of them; FPC is single-pass and does not, so the
    # property is invisible to every other check a dev runs, and the watcher
    # only reports it hours later.
    #
    # It is affordable precisely because it is concurrent: the seed build takes
    # ~11s against this gate's ~14-30s, so wall time is max() rather than sum()
    # and the gate stays the thing you run between edits. Skipped when compiler
    # sources are untouched (nothing else can break the seed) and when FPC is
    # absent, which must be a SKIP and never a failure — the watcher boxes are
    # not required to have it.
    #
    # ARMED AGAINST THE MERGE-BASE, not against HEAD. `git diff HEAD` only sees
    # an UNCOMMITTED change, and the loop this gate belongs to is edit -> gate
    # -> commit -> push OR edit -> commit -> gate -> push. In the second order
    # the canary skipped precisely when it mattered: the change is finished, it
    # is about to be pushed, and the tree is clean, so the check that exists to
    # catch it reported "no uncommitted compiler/ changes" and stood down. That
    # is the hole this canary was added to close, reopened one step later.
    # The merge-base is the right question — "what have I changed that origin
    # has not seen", covering committed-but-unpushed — and it deliberately does
    # NOT arm for a sibling's compiler commit that I merely have not pulled:
    # their push already ran this, and arming on it would fire on nearly every
    # gate in a repo this busy.
    #
    # SECOND ARMING RULE, added 2026-08-29. The paragraph above is right that a
    # sibling's pushed compiler commit should not be re-gated on every run, but
    # it justified that with "their push already ran this" -- and the gate is
    # deliberately OPTIONAL per fix (CLAUDE.md). So "already on origin" means
    # nobody objected, not proven green, and the gap is not theoretical: a
    # duplicate forward in rparser.inc sat broken on master for hours while
    # clean trees printed PASS, then surfaced inside an unrelated Track A gate
    # naming Track R's file. Invisible where it landed, misattributed where it
    # showed up.
    #
    # So the canary also arms when origin/master's compiler/ has moved past the
    # last sha THIS CLONE actually proved. The state file is untracked and
    # per-clone on purpose: "seed-green" is a property of a box that ran fpc,
    # not of a commit, and tracking it would let one box's green silence every
    # other box. Cost stays one seed build per origin/master advance -- still
    # concurrent, still ~11s -- and a repo sitting still still pays nothing.
    seed_pid=
    seed_base=$(git merge-base origin/master HEAD 2>/dev/null) || seed_base=HEAD
    seed_green_file="$(git rev-parse --git-dir 2>/dev/null)/pxx-seed-green"
    seed_green=$(cat "$seed_green_file" 2>/dev/null || true)
    seed_arm=no
    seed_mine=no          # is there a local compiler/ change that could be the cause?
    if ! git diff --quiet "$seed_base" -- compiler/ 2>/dev/null; then
      seed_arm=yes; seed_mine=yes
    elif [ -z "$seed_green" ] || ! git cat-file -e "$seed_green^{commit}" 2>/dev/null; then
      seed_arm=yes       # nothing proved on this clone yet
    elif ! git diff --quiet "$seed_green" HEAD -- compiler/ 2>/dev/null; then
      seed_arm=yes       # pulled compiler/ commits this clone has never seeded
    fi
    if command -v fpc >/dev/null 2>&1 && [ "$seed_arm" = yes ]; then
      ( rm -rf "$LOGDIR/seed_u" && mkdir -p "$LOGDIR/seed_u" && \
        fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU"$LOGDIR/seed_u" \
            -FE"$LOGDIR/seed_u" -o"$LOGDIR/seed26" compiler/compiler.pas \
        ) >"$LOGDIR/fpc-seed.log" 2>&1 &
      seed_pid=$!
    fi

    # Under a second, and it is the ONLY layer that survives `git add -f`.
    # .gitignore is advisory and the fetchers' own guards only cover the roots
    # they know about; this one derives the roots from the fetchers, so a new
    # fetcher cannot quietly escape it. Cheap enough for the per-fix gate, which
    # is the point — a check that only runs nightly cannot stop a push.
    step "no vendor tracked" "$LOGDIR/no-vendor.log" \
         tools/check_no_vendor_tracked.sh                                || RC=1

    # Under a second, same reason as the vendor check above: a stated invariant
    # that only a nightly notices cannot stop a push. CLAUDE.md scopes
    # per-backend optimisation to x86-64 + aarch64, and for most of the -O3
    # campaign nothing checked whether that scope was being MET -- it drifted to
    # 22 : 6 while the prose said both were in scope, because "aarch64 is in
    # scope" and "aarch64 got 6 of 22" are consistent statements. This does not
    # forbid a one-armed slice; it forbids one nobody noticed was one-armed, by
    # making the widened delta an edit in the same commit.
    # feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen
    step "-O3 backend parity" "$LOGDIR/o3-parity.log" \
         tools/check_o3_backend_parity.py                                || RC=1

    step "self-host fixedpoint" "$LOGDIR/fixedpoint.log" fixedpoint      || RC=1
    step "testmgr --tier quick" "$LOGDIR/quick.log" \
         tools/testmgr.py --tier quick                                   || RC=1

    if [ -n "$seed_pid" ]; then
      if wait "$seed_pid"; then
        echo "  PASS  FPC seed canary (concurrent)"
        # Record only when the tree's compiler/ IS the commit -- with local
        # edits in flight, what we just proved is not any sha, and stamping
        # HEAD would suppress the next run for a state never built.
        if git diff --quiet HEAD -- compiler/ 2>/dev/null; then
          git rev-parse HEAD > "$seed_green_file" 2>/dev/null || true
        fi
      else
        echo "  FAIL  FPC seed canary (concurrent)  $LOGDIR/fpc-seed.log"
        # The error is thousands of lines above the tail — FPC keeps warning
        # after the error that stopped it — so surface it rather than the tail.
        grep -E "Error:|Fatal:" "$LOGDIR/fpc-seed.log" | head -5 | sed 's/^/        /'
        # Say WHOSE break it is before saying what it might be. When there is
        # no local compiler/ change, the answer is not "what did I do" and an
        # agent reading a failure inside its own gate will assume it is.
        if [ "$seed_mine" = yes ]; then
          echo "        this tree has local compiler/ changes — likely yours"
        else
          echo "        NOT YOUR CHANGE: no local compiler/ edits — this break is"
          echo "        already on origin/master. Do not bisect your own work."
        fi
        echo "        two shapes both fail only under FPC (pxx accepts both):"
        echo "          - MISSING forward: a routine called from an include EARLIER"
        echo "            in compiler.pas than the one defining it — add a forward,"
        echo "            see bug-a-fpc-seed-drift-emitasmx64-forward"
        echo "          - DUPLICATE forward: the same routine forwarded twice in one"
        echo "            file — delete the later one, see"
        echo "            bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build"
        RC=1
      fi
    elif command -v fpc >/dev/null 2>&1; then
      echo "  SKIP  FPC seed canary (compiler/ unchanged, and seeded green at ${seed_green:0:12})"
    else
      echo "  SKIP  FPC seed canary (fpc not installed)"
    fi
    if [ "$MODE" = full ]; then
      step "make test-nilpy"    "$LOGDIR/test-nilpy.log" make test-nilpy || RC=1
      step "make test"          "$LOGDIR/test.log" make test             || RC=1
    fi
    ;;
  lib)
    step "make lib-test"        "$LOGDIR/lib-test.log" make lib-test     || RC=1
    ;;
  *)
    echo "gate: unknown mode '$MODE' (quick | lib | full | check)"
    exit 2
    ;;
esac

# PUBLISH THE STATUS IN THE LINE, not only in $?. gate.sh has been reported as
# "printed RED and exited 0" three times by three different lanes — and each
# time the tool was correct and the CALLER lost the status to a trailing
# command: `| tail`, `; echo "exit=$?"`, `&& cp`, a cleanup line. That is not a
# shell gotcha anyone outgrows; it is the general rule ("trust the exit code")
# having a domain where it is exactly backwards, so the well-trained reflex
# fires wrong.
#
# gate.sh cannot fix its caller's shell. What it CAN do is stop being the
# ambiguous half: printing the code it is about to return puts the verdict and
# the status in the same line, so a wrapper reporting 0 over `gate: RED (exit
# 1)` is visibly the wrapper's error rather than a suspected bug in here. Same
# property as the seed canary naming the sha it stands on — publish the evidence
# you rely on, so a reader can check the claim instead of trusting it.
if [ "$RC" = 0 ]; then echo "gate: GREEN (exit 0)"; else echo "gate: RED (exit $RC)"; fi
exit "$RC"
