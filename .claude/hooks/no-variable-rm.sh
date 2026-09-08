#!/usr/bin/env bash
# Refuse an interactive `rm` whose target is a VARIABLE or a GLOB.
#
# WHY THIS IS A HOOK AND NOT A NOTE: CLAUDE.md has said "NEVER issue `rm` as a
# Bash tool call with a VARIABLE or a GLOB in the path" since 2026-09-04, and it
# is a rule rather than a preference precisely because the owner had already
# asked once in his own words -- "can you stop doing rm with environment vars
# please". On 2026-09-07 he reported it was STILL happening. Measured the same
# hour across the fleet's transcripts: ~170 such calls in ten sessions over four
# days, the most recent 51 minutes earlier. A prose rule in a 65KB file loses to
# whatever the agent is concentrating on; a refusal does not.
#
# WHAT IT ACTUALLY COSTS: not the keystroke. `rm -rf "$T/$n"` trips Claude
# Code's BUILT-IN dangerous-rm prompt, and that prompt STALLS THE SESSION until
# the owner personally clears it -- frankA sat on one for 19 HOURS, and a
# blocked session and a working session look identical from outside. This hook
# turns a silent multi-hour stall into an instant, self-explaining refusal the
# agent can act on without anyone being woken up.
#
# THERE IS NO ENV ESCAPE, AND THAT IS DELIBERATE. CLAUDE.md: "The fix is not to
# rephrase the command so it slips past the guard ... a guard you route around
# is a guard the owner no longer has." The way through is to do the correct
# thing instead, and all three are cheaper than the rm:
#   1. Do not delete at all. mktemp -d yields a directory the OS reaps; /tmp is
#      aged at 6h (/etc/tmpfiles.d/tmp.conf). Walking away is nearly always right.
#   2. If a loop writes per-iteration artefacts, clean up inside the loop from a
#      COMMITTED script with `trap ... EXIT` -- reviewed once, run as a unit.
#      That is why tools/*.sh never trip this: the hook sees `tools/foo.sh`, not
#      the rm inside it.
#   3. If you must delete interactively, SPELL THE PATH LITERALLY. That is the
#      escape hatch, it is the rule's own instruction, and it cannot be abused.
#
# THE GUARD REFUSES ITS OWN TEST HARNESS AND ITS OWN COMMIT MESSAGES, AND THAT IS
# CORRECT. It matches on command TEXT, so a Bash heredoc listing the cases -- or
# a commit message describing the rule -- is refused exactly like a command about
# to run. It cannot tell them apart and must not try. So: the controls live in
# `tools/devtest_no_variable_rm.py`, created with the Write tool and run as
# `python3 tools/devtest_no_variable_rm.py`, a command line that names no
# deleter; and a commit message about this rule goes to a file via Write, then
# `git commit -F`. 25 controls, both directions. Do NOT weaken the hook to make
# authoring convenient -- the next person hits this within a minute, and this
# comment is the answer.
#
# Reads the PreToolUse hook payload on stdin, answers a permissionDecision.

set -uo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Split on shell separators so each segment is judged on its own. Over-splitting
# can only expose MORE text to the rules, never less -- the same reasoning as
# no-full-suite.sh, and the segments deliberately stay on separate LINES.
scan=$(printf '%s' "$cmd" | sed -E 's/(&&|\|\||[;&|])/\n/g')

deny() {
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

fix='Three ways through, all cheaper than the rm. (1) Do not delete: mktemp -d gives you a directory the OS reaps and /tmp is aged at 6h -- walking away is nearly always right. (2) If a loop writes per-iteration artefacts, clean up INSIDE the loop from a committed script with `trap ... EXIT`; that is why tools/*.sh never trip this. (3) If you must delete interactively, SPELL THE PATH LITERALLY -- that is the hatch, and it is the rule itself.'

why='This is not about the keystroke. `rm -rf "$T/$n"` trips Claude Code built-in dangerous-rm prompt, which STALLS THE SESSION until the owner personally clears it -- one seat sat on such a prompt for 19 hours, and from outside a blocked session and a working session look identical. Do not rephrase to slip past this: a guard you route around is a guard the owner no longer has.'

# Only judge segments where `rm` is in COMMAND position: start of the segment, or
# after sudo/xargs/time/env-assignments. `grep -n 'rm '` and heredoc prose are
# not rm calls and must pass.
rmlines=$(printf '%s' "$scan" \
  | grep -E '^[[:space:]]*(\{[[:space:]]*|\([[:space:]]*|do[[:space:]]+|then[[:space:]]+|else[[:space:]]+|sudo[[:space:]]+|xargs[[:space:]]+|time[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*rm([[:space:]]|$)' \
  | grep -Ev '^[[:space:]]*#')
# TARGETS THAT NEVER APPEAR IN argv AT ALL. `find ... | xargs -0 rm -rf` and
# `find ... -exec rm -rf {} +` carry neither a $variable nor a glob on the rm
# command line -- the paths arrive on stdin or from find -- so every rule above
# passes them, and they are the shape with the LEAST review available: the
# command names nothing a reader can check, and what gets deleted depends on a
# search that ran a moment ago. Found 2026-09-08 by frank-seven asking whether
# its ad-hoc /tmp reaper would trip this; it would not have, and the honest
# answer was that the guard could not see it. My own controls had no case from
# this population -- the exact failure this file warns about, in the guard
# written to enforce it.
#
# A committed script is the answer here and frank-seven reached it independently:
# a reaper that runs regularly belongs in tools/ with a trap, reviewed once.
if printf '%s' "$scan" | grep -Eq '(^|[[:space:]])xargs([[:space:]]+(-[^[:space:]]+|[0-9]+))*[[:space:]]+rm([[:space:]]|$)'; then
  deny "REFUSED: \`xargs ... rm\` -- the targets never appear in the command, so nothing here names what will be deleted and no reviewer can check it. $fix"
fi
if printf '%s' "$scan" | grep -Eq 'find[^|;&]*-exec[[:space:]]+rm([[:space:]]|$)'; then
  deny "REFUSED: \`find ... -exec rm\` -- the targets come from the search, not the command, so nothing here names what will be deleted. $fix"
fi

[ -z "$rmlines" ] && exit 0

# A GLOB anywhere in an rm target. Includes the non-recursive case: `rm -f
# $W/g/*.npy` is one bad expansion away from the recursive one and reads the same.
if printf '%s' "$rmlines" | grep -Eq 'rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^|;&]*[*?]'; then
  deny "REFUSED: \`rm\` with a GLOB in the path. $why $fix"
fi

# RECURSIVE rm with a variable anywhere in the target -- the worst shape and the
# one the owner named. `rm -rf "$S"`, `rm -rf $T/$n`, `rm -r ${WORK}/x`.
if printf '%s' "$rmlines" | grep -Eq 'rm([[:space:]]+-[^[:space:]]*[rR][^[:space:]]*)+([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^|;&]*\$'; then
  deny "REFUSED: recursive \`rm\` with a VARIABLE in the path. $why $fix"
fi

# A bare variable as the whole target, recursive or not: `rm -f "$out"`. One
# empty expansion from deleting the wrong thing, and it names nothing a reader
# can check.
if printf '%s' "$rmlines" | grep -Eq 'rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?([[:space:]]|$)'; then
  deny "REFUSED: \`rm\` whose whole target is a bare variable. An empty expansion here deletes the wrong thing, and the command names nothing a reviewer can check. $fix"
fi

# ANY variable in an rm target, recursive or not. This is CLAUDE.md's rule as
# WRITTEN -- "a VARIABLE or a GLOB in the path" -- and the narrower reading
# (only the shapes that stall a session) was tried first and rejected: the owner
# named the pattern, not the stalling subset, and `rm -f $SP/suite24.log` is one
# of the calls he was reporting. Two rules that disagree is worse than one that
# occasionally costs a literal path.
if printf '%s' "$rmlines" | grep -Eq 'rm([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^|;&]*\$'; then
  deny "REFUSED: \`rm\` with a VARIABLE in the path. $why $fix"
fi

exit 0
