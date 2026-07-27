#!/usr/bin/env bash
# One command that runs a lane's gate to completion and prints ONE summary.
#
# Why this exists: an agent that backgrounds `make test-nilpy` and then polls it
# with `sleep 600; tail log` burns a conversation turn per poll and learns
# nothing. Background THIS script instead — it exits when the gate is done, so
# the completion notification IS the result. One task, one answer.
#
#   tools/gate.sh quick     test-nilpy + self-host fixedpoint + testmgr quick
#   tools/gate.sh lib       lib-test (Track B/E)
#   tools/gate.sh full      quick + make test  (only when Track T is down)
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
  others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null || echo 0)
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

fixedpoint() {     # self-host from the PINNED seed: A == B == C, byte for byte
  local a="$LOGDIR/sh-A" b="$LOGDIR/sh-B" c="$LOGDIR/sh-C"
  "$PINNED" compiler/compiler.pas "$a" >/dev/null 2>&1 || return 1
  "$a" compiler/compiler.pas "$b" >/dev/null 2>&1 || return 1
  "$b" compiler/compiler.pas "$c" >/dev/null 2>&1 || return 1
  cmp -s "$a" "$b" && cmp -s "$b" "$c"
}

echo "gate: mode=$MODE  logs=$LOGDIR"
note_contention

if [ "$MODE" = check ]; then
  echo "gate: would run:"
  case "${2:-quick}" in *) :;; esac
  echo "  quick -> make test-nilpy | self-host fixedpoint (pinned seed) | testmgr --tier quick"
  echo "  lib   -> make lib-test"
  echo "  full  -> quick + make test"
  tools/twatch.py --status 2>/dev/null | sed 's/^/  /' || echo "  (twatch status unavailable)"
  exit 0
fi

RC=0
case "$MODE" in
  quick|full)
    step "make test-nilpy"      "$LOGDIR/test-nilpy.log" make test-nilpy || RC=1
    step "self-host fixedpoint" "$LOGDIR/fixedpoint.log" fixedpoint      || RC=1
    step "testmgr --tier quick" "$LOGDIR/quick.log" \
         tools/testmgr.py --tier quick                                   || RC=1
    if [ "$MODE" = full ]; then
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
