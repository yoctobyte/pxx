#!/usr/bin/env bash
# Refuse `git commit -m` whose message argument contains a LIVE shell
# substitution -- a backtick, `$(...)`, or `$NAME` outside single quotes.
#
# WHY THIS IS A HOOK AND NOT A NOTE. This repo's house style quotes identifiers,
# paths and flags in backticks, and a commit message is the one place that style
# meets a shell. The substitution is performed by bash BEFORE git ever sees the
# string, so the corruption is already committed by the time anything could
# review it. Measured 2026-09-20 across 4000 commits on origin/master:
#
#   11a846d4d  the LOUD form: a backticked git command spliced 103 lines --
#              diff, author, date and all -- into the message. Unmissable.
#   f99707dfb  "agreeing with a  header that means 'partly"       0 backticks
#   98ce0b129  "Gated with  immediately before the demotion."     0 backticks
#              "Every row but  is byte-identical to CPython."  <- same message
#   6353e84ec  SUBJECT LINE: "the fourth  instance"              0 backticks
#
# THE LOUD ONE IS THE RARE ONE, 1 IN 4000, AND IT IS THE ONLY ONE ANYONE NOTICED.
# A backticked COMMAND splices and screams. A backticked IDENTIFIER -- which is
# what house style actually produces -- is `command not found`, substitutes to
# EMPTY, and closes up leaving a double space. The marks and their contents are
# gone together, so NOTHING IN THE TREE RECORDS THAT ANYTHING WAS LOST. The
# three silent ones contain zero backticks; they were found by grepping for the
# residue, not for the cause.
#
# IT IS NOT COSMETIC. 98ce0b129 has been in the record for ten days reading
# "Every row but  is byte-identical to CPython" -- a load-bearing exception
# deleted from a claim about parity. The lost token is recoverable only because
# the same message spells `viaself` again later without backticks. A commit
# message that asserts something STRONGER than the seat meant is the failure
# here, and it is silent in both directions: git reports success, and nobody
# reads a message back after a green push.
#
# TREAT 4 AS A FLOOR, NOT A COUNT. The census can only see losses that left a
# double space. A backticked token at a line end, or one whose removal closes up
# cleanly, leaves no residue at all and is unfindable by construction.
#
# WHY A HOOK CAN CATCH THIS AT ALL, since two seats asserted it could not:
# PreToolUse receives the command TEXT as written, before any shell runs it.
# That is the same property no-variable-rm.sh relies on to match an unexpanded
# `$VAR`, and the reason that hook also refuses commit messages ABOUT the rm
# rule. The guard runs UPSTREAM of the damage, not downstream.
#
# THE REMEDY IS BETTER THAN THE THING IT REPLACES, WHICH IS WHY THERE IS NO ENV
# ESCAPE. `git commit -F <file>`: no quoting rules at all, multi-line messages
# without `$'\n'`, and the message is reviewable as a file before it lands.
# Write the file with the Write tool, or a heredoc with a QUOTED delimiter.
# Measured, all four forms:  "..." substitutes.  '...' does not.
#   <<EOF SUBSTITUTES  <-- the trap for anyone who thinks "heredoc" is the safe
#   <<'EOF' does not        word rather than the QUOTING.
#
# THIS GUARD REFUSES ITS OWN COMMIT MESSAGE AND ITS OWN CONTROLS, AND THAT IS
# CORRECT -- the same property, and the same reasoning, as no-variable-rm.sh. It
# matches on command text and cannot tell a description from an invocation. So
# the controls live in `tools/devtest_no_substitution_in_commit_message.py`, run
# by a command line that contains no `git commit` at all, and this file's own
# commit message went in via `-F`.
#
# Reads the PreToolUse hook payload on stdin, answers a permissionDecision.

set -uo pipefail

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Cheap pre-filter: nothing to do unless this is a git commit carrying -m.
printf '%s' "$cmd" | grep -q 'git[[:space:]]\+commit' || exit 0

verdict=$(printf '%s' "$cmd" | python3 -c '
import sys

cmd = sys.stdin.read()

# Walk the command tracking shell quote state, so a backtick inside SINGLE
# quotes -- which bash does not expand -- is correctly ignored. Anything else
# would over-refuse the one spelling that is already safe.
def scan(s):
    i, n = 0, len(s)
    single = double = False
    hits = []
    while i < n:
        c = s[i]
        if single:
            if c == "'\''":
                single = False
        elif double:
            if c == "\\":
                i += 2
                continue
            if c == '\''"'\'':
                double = False
            elif c == "`":
                hits.append(("backtick", i))
            elif c == "$" and i + 1 < n and s[i+1] == "(":
                hits.append(("$(...)", i))
            elif c == "$" and i + 1 < n and (s[i+1].isalpha() or s[i+1] in "_{"):
                hits.append(("$NAME", i))
        else:
            if c == "\\":
                i += 2
                continue
            if c == "'\''":
                single = True
            elif c == '\''"'\'':
                double = True
            elif c == "`":
                hits.append(("backtick", i))
        i += 1
    return hits

# Only judge a command that actually passes a message on the command line.
# `git commit -F file`, `git commit --amend` with an editor, and a bare
# `git commit` carry no message text here and are none of this guard business.
import re
if not re.search(r"git\s+commit\b[^\n]*\s-(m|-message)\b", cmd):
    sys.exit(0)

hits = scan(cmd)
if hits:
    kinds = sorted({k for k, _ in hits})
    print(",".join(kinds))
' 2>/dev/null)

[ -z "$verdict" ] && exit 0

reason="REFUSED: a \`git commit -m\` message containing a live shell substitution ($verdict). Bash performs it BEFORE git sees the string, so the corruption lands in the permanent record and nothing in the tree shows anything was lost. Measured across 4000 commits: the loud form spliced 103 lines of \`git show\` output into a message; the THREE silent ones had zero backticks left -- a backticked identifier is 'command not found', substitutes to EMPTY and closes up, and one of them has read 'Every row but  is byte-identical to CPython' for ten days, with the exception deleted from the claim. USE \`git commit -F <file>\`: no quoting rules, multi-line without \$'\\n', and the message is reviewable before it lands. Write the file with the Write tool, or a heredoc with a QUOTED delimiter -- measured: \"...\" substitutes, '...' does not, <<EOF DOES, <<'EOF' does not. Single-quoting the -m argument also works and this guard already allows it. Do not rephrase to slip past this: the substitution is silent and permanent, and a guard you route around is a guard nobody has."

jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
