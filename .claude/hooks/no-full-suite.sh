#!/usr/bin/env bash
# Refuse full regression suites for every lane except Track T.
#
# WHY THIS IS A HOOK AND NOT A NOTE: the rule ("per-fix gate is
# `make compiler/pascal26` + your repro + `tools/gate.sh quick`, Track T sweeps
# the matrix") is written in CLAUDE.md and in agent memory, and an agent still
# reached for `make test-nilpy` twice in one session — once as a `make` target,
# once as a shell loop over `test/test_nilpy_*.npy`, which is the same ten
# minutes wearing a different hat. Advice loses to a plausible-sounding
# rationalisation; a refusal does not.
#
# WHAT IT COSTS WHEN WRONG: nothing irreversible. The escape hatch is one
# environment variable, printed in the refusal itself.
#
# Track T owns the suites — it is the lane whose whole job is running them, and
# its gate genuinely is `--tier full`. It escapes by exporting PXX_TRACK=T.
#
# Reads the PreToolUse hook payload on stdin, answers a permissionDecision.

set -uo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# --- escapes -----------------------------------------------------------------
# Track T's lane, an explicit per-session opt-out, or an inline opt-out on the
# command itself (so the hatch works without restarting the session).
if [ "${PXX_TRACK:-}" = "T" ] || [ "${PXX_ALLOW_FULL_SUITE:-}" = "1" ]; then exit 0; fi
case "$cmd" in *PXX_ALLOW_FULL_SUITE=1*|*PXX_TRACK=T*) exit 0 ;; esac

# READING ABOUT a rule is not running it. Every pattern below matches on the
# command TEXT, so `grep -n "make test-nilpy" Makefile`, `git log --grep`, and a
# commit message that quotes a forbidden command all tripped the refusal — the
# last one silently deleting the message span. A command whose first word is a
# read-only tool cannot start a suite, so it is out of scope entirely.
# (`git` is scoped to its read-only subcommands: `git commit -m "...make test"`
# is a mention, while a hypothetical alias that runs one is not worth guessing.)
first=${cmd%%[[:space:]]*}
first=${first##*/}
case "$first" in
  grep|rg|egrep|fgrep|sed|awk|cat|head|tail|less|more|wc|jq|echo|printf|ls|find|diff|cut|sort|uniq|nl|od|strings) exit 0 ;;
  git)
    case "$cmd" in
      git\ log*|git\ grep*|git\ show*|git\ diff*|git\ status*|git\ blame*|git\ commit*) exit 0 ;;
    esac
    ;;
esac

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

hatch='Track T escapes with PXX_TRACK=T; anything else with PXX_ALLOW_FULL_SUITE=1 in front of the command, and only when the user has asked for it.'
loop='The per-fix gate is: make compiler/pascal26 (that IS the byte-identical self-host fixedpoint), your repro, then tools/gate.sh quick. Track T sweeps the full matrix against the pushed sha and reports back asynchronously.'

# --- 1. make test targets ----------------------------------------------------
# `make test`, `make test-nilpy`, `make test-core`, `make check`, ... but NOT
# `make lib-test` / `make demos` (Track B's own gate, minutes not tens of them)
# and NOT `make compiler/pascal26` / `make pin` / `make stabilize-fast`.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])make[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(test|check)([[:space:]]|$|-[a-z0-9-]+)'; then
  deny "REFUSED: a full regression suite. $loop A hand-run suite buys coverage you already get for free and delays the push — and unpushed work is work Track T cannot see. $hatch"
fi

# --- 2. the heavy gate / testmgr tiers ---------------------------------------
if printf '%s' "$cmd" | grep -Eq 'gate\.sh[[:space:]]+(full|limited)'; then
  deny "REFUSED: the heavy gate modes are the PIN gate, not the dev loop. $loop To bless a binary use: make stabilize-fast && make pin. $hatch"
fi
if printf '%s' "$cmd" | grep -Eq 'testmgr\.py.*--tier[[:space:]]+(full|limited)'; then
  deny "REFUSED: the heavy testmgr tiers are Track T's sweep. $loop --tier quick is allowed; to pin, use make stabilize-fast && make pin. $hatch"
fi

# --- 2b. a pin that can silently become a matrix run -------------------------
# `tools/testmgr.py --pin` gates BEFORE it pins, and picks that gate's tier from
# watcher_is_down(). That reads the LOCAL tstate/, so without a `git fetch`
# first it reports your own checkout's staleness rather than Track T's health,
# escalates, and spends MINUTES — including the uforth differential, whose
# timeout alone is 900s — while holding the repo lock every other lane waits on.
# Measured 2026-08-14: it escalated on a stale local tstate while Track T was UP
# the whole time, and the operator killed it as a hang.
#
# Breadth does not belong in a pin. `make stabilize-fast && make pin` is ~35s,
# and the ONE property a bad pin could poison for everyone — a compiler that
# cannot reproduce itself — is exactly what stabilize-fast's
# self->next->fixedpoint chain proves. Track T sweeps the matrix against the
# pushed sha regardless, which is the whole point of having Track T.
#
# An explicit `--tier quick` fixes the tier and cannot escalate, so it stays
# allowed for anyone who wants the interruptible atomic pin.
# Matched at a COMMAND position only. `grep -n "testmgr.py --pin" CLAUDE.md` is
# reading about the rule, not running it, and refusing that is pure noise — the
# first thing this rule did on the day it landed.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*(python3[[:space:]]+)?(\./)?tools/testmgr\.py[^|;&]*--pin' \
   && ! printf '%s' "$cmd" | grep -Eq -- '--tier[[:space:]]+quick'; then
  deny "REFUSED: testmgr --pin chooses its gate tier from watcher_is_down(), which reads the LOCAL tstate/ — so without a fetch it escalates and runs for MINUTES with the repo lock held, blocking every other lane. Pin with: make stabilize-fast && make pin (~35s — that chain IS the self-host fixedpoint, the only property a bad pin could poison for everyone). If you specifically want the interruptible atomic pin, tools/testmgr.py --pin --tier quick cannot escalate and is allowed. $hatch"
fi

# --- 2c. the slow stabilize --------------------------------------------------
# `make stabilize` verifies every cross target (~25 min), and every other track
# — and the human — is blocked while it runs. That belongs to a RELEASE, not to
# a pin (user, 2026-08-09), and it is cheap to undo either way since `make
# revert` moves `pinned` back. `make stabilize-fast` is NOT matched here.
if printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])make[[:space:]]+(-[^[:space:]]+[[:space:]]+)*stabilize([[:space:]]|$)'; then
  deny "REFUSED: make stabilize verifies all cross targets (~25 min) and blocks every other track — and the human — while it runs. Use make stabilize-fast (~35s). Full stabilize is for a RELEASE, or when Track T is PROVEN down: tools/twatch.py --status exiting 1 AFTER a git fetch, or tools/trackt.py health saying DOWN. $hatch"
fi

# --- 3. the same thing wearing a shell loop ----------------------------------
# A glob over the suite driven by for/while/xargs/find -exec is a full
# regression run with extra steps. Naming a handful of files explicitly is not
# a glob and stays allowed.
if printf '%s' "$cmd" | grep -Eq '(test|tests)/[A-Za-z0-9_]*\*[A-Za-z0-9_]*\.(npy|pas|c|py|zig|rs)' \
   && printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|[[:space:]])(for|while|xargs|parallel)([[:space:]]|$)|find[[:space:]]+.*-exec'; then
  deny "REFUSED: a shell loop over a test/ glob is a full regression run with extra steps — same minutes, same waiting. $loop Verify with the repro for THIS change plus, at most, a handful of directly related files named one by one. $hatch"
fi

exit 0
