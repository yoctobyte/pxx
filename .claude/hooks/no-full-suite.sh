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
# ...but only when the command is ONE command. `echo 'make -n' && make test` has
# a read-only first word and a real suite after it, and exempting on the first
# word alone waved it through — the same "an unrelated token defeats the rule"
# shape as the make-variable gap below. A PIPE is still fine: `git log --grep x
# | head` cannot start a suite either way.
first=${cmd%%[[:space:]]*}
first=${first##*/}
# ...but a CHAIN is not one command. `echo 'make -n' && make test` has a
# read-only first word and a real suite after it, and exempting on the first
# word alone waved it through — the same "an unrelated token defeats the rule"
# shape as the make-variable gap below. A PIPE is still fine (`git log --grep x
# | head` cannot start a suite either way), and `git` keeps its exemption
# through a chain on purpose: a commit MESSAGE routinely contains both a
# semicolon and a quoted command, and refusing that is the noisy false positive
# this block was written to stop.
case "$cmd" in
  *"&&"*|*"||"*|*";"*) [ "$first" = git ] || first='' ;;
esac
case "$first" in
  grep|rg|egrep|fgrep|sed|awk|cat|head|tail|less|more|wc|jq|echo|printf|ls|find|diff|cut|sort|uniq|nl|od|strings) exit 0 ;;
  git)
    case "$cmd" in
      git\ log*|git\ grep*|git\ show*|git\ diff*|git\ status*|git\ blame*|git\ commit*) exit 0 ;;
    esac
    ;;
esac

# A DRY RUN executes nothing. `make -n` prints the recipe and exits — measured
# at 0.08s on this repo — so refusing it refuses a READ, not a suite. It is also
# load-bearing: testmgr's own make_dry_run() builds the job list from it, and
# the cheapest proof that a mechanical Makefile change is behaviour-preserving
# is a `make -n` capture across every target, diffed before and after.
#
# Exempted by REMOVING those segments from the text the rules below scan, not by
# exiting early on the whole command: one dry run chained to one real suite is
# still a suite, and an early exit would wave both through. Splitting on the
# shell separators is coarse — a `|` inside a quoted string over-splits — but
# over-splitting can only ever expose MORE text to the rules, never less.
# bug-a-no-full-suite-hook-refuses-make-n-and-misses-half-the-long-tiers
scan=$(printf '%s' "$cmd" \
  | sed -E 's/(&&|\|\||[;&|])/\n/g' \
  | grep -Ev '(^|[[:space:]])make([[:space:]]+[^[:space:]]+)*[[:space:]]+(-n|--dry-run|--just-print|--recon)([[:space:]]|$)' \
  | grep -Ev '(^|[[:space:]])make[[:space:]]+-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)')
# NOTE the segments stay on separate LINES. Joining them with a `;` put that
# character immediately after the target, and every rule below ends its match
# with `([[:space:]]|$)` — so `make test;` matched nothing and the hook waved
# through the exact command it exists to refuse. grep is line-oriented; leave
# it that way.

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
# The token run before the target accepts BOTH `-flag` and `VAR=value`: the old
# pattern allowed only flags, so `make -n --no-print-directory PXX_TMP=/tmp/x
# test-nilpy` fell straight through the rule. A rule a stray make variable
# defeats gets defeated by accident long before anyone defeats it on purpose.
if printf '%s' "$scan" | grep -Eq '(^|[;&|(]|[[:space:]])make[[:space:]]+((-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*(test|check)([[:space:]]|$|-[a-z0-9-]+)'; then
  deny "REFUSED: a full regression suite. $loop A hand-run suite buys coverage you already get for free and delays the push — and unpushed work is work Track T cannot see. $hatch"
fi

# --- 2. the heavy gate / testmgr tiers ---------------------------------------
if printf '%s' "$scan" | grep -Eq 'gate\.sh[[:space:]]+(full|limited)'; then
  deny "REFUSED: the heavy gate modes are the PIN gate, not the dev loop. $loop To bless a binary use: make stabilize-fast && make pin. $hatch"
fi
# EVERYTHING EXCEPT quick, rather than an enumeration of the heavy ones. The old
# pattern named full|limited and so allowed `native` (what the watcher runs
# continuously), `slow` (which exists to hold test-uforth#blocktest, 594s in ONE
# job) and `opt` (the optdiff sweep) — each of them the ten minutes this hook was
# written to prevent. `slow` had been created the same day the gap was found,
# which is exactly how a maintained list goes stale.
if printf '%s' "$scan" | grep -Eq 'testmgr\.py.*--tier[[:space:]]+[a-z]+' \
   && ! printf '%s' "$scan" | grep -Eq -- '--tier[[:space:]]+quick([[:space:]]|$)|--quick([[:space:]]|$)'; then
  deny "REFUSED: every testmgr tier except quick is Track T's sweep — native, slow and opt cost the same ten minutes as full and limited. $loop --tier quick is allowed; to pin, use make stabilize-fast && make pin. $hatch"
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
# allowed for anyone who wants the interruptible atomic pin. `--quick` is the
# shorthand testmgr resolves to exactly that, before anything reads the tier —
# so it is allowed here on the same grounds, not as a courtesy.
# Matched at a COMMAND position only. `grep -n "testmgr.py --pin" CLAUDE.md` is
# reading about the rule, not running it, and refusing that is pure noise — the
# first thing this rule did on the day it landed.
if printf '%s' "$scan" | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*(python3[[:space:]]+)?(\./)?tools/testmgr\.py[^|;&]*--pin' \
   && ! printf '%s' "$scan" | grep -Eq -- '--tier[[:space:]]+quick|--quick([[:space:]]|$)'; then
  deny "REFUSED: testmgr --pin chooses its gate tier from watcher_is_down(), which reads the LOCAL tstate/ — so without a fetch it escalates and runs for MINUTES with the repo lock held, blocking every other lane. Pin with: make stabilize-fast && make pin (~35s — that chain IS the self-host fixedpoint, the only property a bad pin could poison for everyone). If you specifically want the interruptible atomic pin, tools/testmgr.py --pin --tier quick (or --pin --quick, the same thing) cannot escalate and is allowed. $hatch"
fi

# --- 2c. the slow stabilize --------------------------------------------------
# `make stabilize` verifies every cross target (~25 min), and every other track
# — and the human — is blocked while it runs. That belongs to a RELEASE, not to
# a pin (user, 2026-08-09), and it is cheap to undo either way since `make
# revert` moves `pinned` back. `make stabilize-fast` is NOT matched here.
if printf '%s' "$scan" | grep -Eq '(^|[;&|(]|[[:space:]])make[[:space:]]+((-[^[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*stabilize([[:space:]]|$)'; then
  deny "REFUSED: make stabilize verifies all cross targets (~25 min) and blocks every other track — and the human — while it runs. Use make stabilize-fast (~35s). Full stabilize is for a RELEASE, or when Track T is PROVEN down: tools/twatch.py --status exiting 1 AFTER a git fetch, or tools/trackt.py health saying DOWN. $hatch"
fi

# --- 3. the same thing wearing a shell loop ----------------------------------
# A glob over the suite driven by for/while/xargs/find -exec is a full
# regression run with extra steps. Naming a handful of files explicitly is not
# a glob and stays allowed.
if printf '%s' "$scan" | grep -Eq '(test|tests)/[A-Za-z0-9_]*\*[A-Za-z0-9_]*\.(npy|pas|c|py|zig|rs)' \
   && printf '%s' "$scan" | grep -Eq '(^|[;&|(]|[[:space:]])(for|while|xargs|parallel)([[:space:]]|$)|find[[:space:]]+.*-exec'; then
  deny "REFUSED: a shell loop over a test/ glob is a full regression run with extra steps — same minutes, same waiting. $loop Verify with the repro for THIS change plus, at most, a handful of directly related files named one by one. $hatch"
fi

exit 0
