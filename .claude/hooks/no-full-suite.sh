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
  deny "REFUSED: gate.sh full/limited is the PIN gate, not the dev loop. $loop To bless a binary use tools/testmgr.py --pin, which is allowed. $hatch"
fi
if printf '%s' "$cmd" | grep -Eq 'testmgr\.py.*--tier[[:space:]]+(full|limited)'; then
  deny "REFUSED: testmgr --tier full/limited is Track T's sweep. $loop --tier quick and --pin are allowed. $hatch"
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
