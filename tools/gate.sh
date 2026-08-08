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
  return "$rc"
}

echo "gate: mode=$MODE  logs=$LOGDIR"
note_contention

if [ "$MODE" = check ]; then
  echo "gate: would run:"
  case "${2:-quick}" in *) :;; esac
  echo "  quick -> self-host fixedpoint (pinned seed) | testmgr --tier quick   (~30s)"
  echo "  lib   -> make lib-test"
  echo "  full  -> quick + make test-nilpy + make test   (only when Track T is down)"
  tools/twatch.py --status 2>/dev/null | sed 's/^/  /' || echo "  (twatch status unavailable)"
  # --status answers "is anyone covering the repo"; `trackt health` answers
  # "is the watcher on THIS box trustworthy right now", incl. alive-but-wedged.
  echo "  (watcher health on this box: tools/trackt.py health)"
  exit 0
fi

RC=0
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
    seed_pid=
    if command -v fpc >/dev/null 2>&1 && \
       ! git diff --quiet HEAD -- compiler/ 2>/dev/null; then
      ( rm -rf "$LOGDIR/seed_u" && mkdir -p "$LOGDIR/seed_u" && \
        fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU"$LOGDIR/seed_u" \
            -FE"$LOGDIR/seed_u" -o"$LOGDIR/seed26" compiler/compiler.pas \
        ) >"$LOGDIR/fpc-seed.log" 2>&1 &
      seed_pid=$!
    fi

    step "self-host fixedpoint" "$LOGDIR/fixedpoint.log" fixedpoint      || RC=1
    step "testmgr --tier quick" "$LOGDIR/quick.log" \
         tools/testmgr.py --tier quick                                   || RC=1

    if [ -n "$seed_pid" ]; then
      if wait "$seed_pid"; then
        echo "  PASS  FPC seed canary (concurrent)"
      else
        echo "  FAIL  FPC seed canary (concurrent)  $LOGDIR/fpc-seed.log"
        # The error is thousands of lines above the tail — FPC keeps warning
        # after the error that stopped it — so surface it rather than the tail.
        grep -E "Error:|Fatal:" "$LOGDIR/fpc-seed.log" | head -5 | sed 's/^/        /'
        echo "        a routine is called from an include EARLIER in compiler.pas"
        echo "        than the file defining it — add a forward, see"
        echo "        bug-a-fpc-seed-drift-emitasmx64-forward"
        RC=1
      fi
    elif command -v fpc >/dev/null 2>&1; then
      echo "  SKIP  FPC seed canary (no uncommitted compiler/ changes)"
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

if [ "$RC" = 0 ]; then echo "gate: GREEN"; else echo "gate: RED"; fi
exit "$RC"
