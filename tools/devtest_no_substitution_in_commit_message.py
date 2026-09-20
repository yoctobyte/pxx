#!/usr/bin/env python3
"""Controls for .claude/hooks/no-substitution-in-commit-message.sh.

Run:  python3 tools/devtest_no_substitution_in_commit_message.py

WHY THIS FILE EXISTS RATHER THAN A SHELL HARNESS. The hook matches on command
TEXT, so it cannot tell a description of a bad command from the command itself
-- exactly like no-variable-rm.sh, and for the same reason. A harness that
built these cases on a shell command line would be refused by the guard it is
testing. This file is created with the Write tool and run by a command line
that contains no `git commit` at all.

THE MUST-DENY CASES ARE DRAWN FROM REAL COMMITS, NOT INVENTED. A control from
the wrong population passes and certifies a broken instrument, and a control
written from a PREDICTION about the mechanism pins the prediction. Every
deny-case below is a message that actually landed corrupted on origin/master.
"""

import json
import subprocess
import sys
import pathlib

HOOK = pathlib.Path(__file__).resolve().parent.parent / ".claude" / "hooks" / "no-substitution-in-commit-message.sh"

BT = "`"       # spelled indirectly so this file's own text carries no live mark
DOL = "$"


def ask(cmd):
    """Return True if the hook DENIES this command."""
    payload = json.dumps({"tool_input": {"command": cmd}})
    out = subprocess.run(["bash", str(HOOK)], input=payload,
                         capture_output=True, text=True).stdout.strip()
    if not out:
        return False
    try:
        return json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny"
    except Exception:
        return False


# ---------------------------------------------------------------- must DENY
# Each of these is a real shape that corrupted a real commit message.
DENY = [
    # 6353e84ec -- the loss landed in the SUBJECT LINE. The token was eaten and
    # the subject has read "the fourth  instance" ever since.
    ('git commit -m "docs(progress): the fourth ' + BT + 'viaself' + BT + ' instance, and two counting lessons"',
     "6353e84ec: subject-line loss, the worst placement"),

    # 98ce0b129 -- two holes in ONE message. This is the row that has been
    # asserting something stronger than the seat meant for ten days.
    ('git commit -m "Gated with ' + BT + '-dPXX_NOSELF' + BT + ' immediately before the demotion."',
     "98ce0b129:14"),
    ('git commit -m "Every row but ' + BT + 'viaself' + BT + ' is byte-identical to CPython."',
     "98ce0b129:30 -- the exception deleted from a parity claim"),

    # f99707dfb -- same class, different subsystem.
    ('git commit -m "A stale relay agreeing with a ' + BT + 'partly' + BT + ' header"',
     "f99707dfb"),

    # 11a846d4d -- the LOUD form, 1 in 4000. A backticked COMMAND splices its
    # whole output. This is the only member anyone ever noticed.
    ('git commit -m "see ' + BT + 'git show 4c8558c32' + BT + ' for the diff"',
     "11a846d4d: the loud splice"),

    # The other live substitution forms. Same mechanism, same silence.
    ('git commit -m "built against ' + DOL + '(PXX_STABLE) as usual"',
     "$(...) -- and $(PXX_STABLE) is house style"),
    ('git commit -m "restored ' + DOL + 'PATH handling"', "$NAME"),
    ('git commit -m "restored ' + DOL + '{PATH} handling"', "${NAME}"),

    # Long-form spelling of the flag.
    ('git commit --message "a ' + BT + 'token' + BT + ' here"', "--message"),

    # The substitution is in a later segment of a compound command; the message
    # is still built by the same shell invocation.
    ('git add -A && git commit -m "fix ' + BT + 'thing' + BT + '"', "compound"),
]

# --------------------------------------------------------------- must ALLOW
# A guard that refuses the correct spelling teaches people to route around it.
ALLOW = [
    # THE PRESCRIBED REMEDY. If this ever denies, the guard is unusable.
    ('git commit -F /tmp/msg.txt', "the remedy this guard prescribes"),
    ('git commit -q -F "$SCRATCH/msg.txt"', "the remedy, with a variable path"),

    # SINGLE QUOTES ARE ALREADY SAFE -- bash does not expand inside them, so
    # refusing this would be over-refusal of a correct spelling.
    ("git commit -m 'a " + BT + "token" + BT + " inside single quotes'",
     "single-quoted: bash does not expand it"),

    # An ESCAPED backtick in double quotes is literal and safe.
    ('git commit -m "an escaped \\' + BT + ' mark"', "escaped backtick"),

    # Ordinary messages with no substitution at all.
    ('git commit -m "fix(N): a bare read of a method yields a garbage address"',
     "plain message"),
    ('git commit -m "cost 19 hours, 100% of the volume"', "punctuation, no substitution"),

    # No message on the command line -- nothing for this guard to judge.
    ('git commit', "bare commit"),
    ('git commit --amend', "amend via editor"),

    # Not a commit at all. A backtick here is the author's deliberate choice.
    ('echo "today is ' + BT + 'date' + BT + '"', "not a commit"),
    ('git log -1 --format=%B', "read-only git"),
    ('git status --porcelain', "read-only git"),

    # A committed script that commits internally: the hook sees the script name,
    # never the git call inside it. Same property that keeps tools/*.sh clear of
    # no-variable-rm.sh.
    ('tools/sync.sh', "committed script"),
]


# ------------------------------------------------- KNOWN NOT COVERED
# Asserted, so the guard STATES ITS OWN REACH instead of letting a reader assume
# it. A census that does not print the set it enumerates gets read as covering
# whatever the reader had in mind.
#
# The heredoc hazard is REAL and this guard does NOT close it, because the
# dangerous step is writing the message FILE and that command line contains no
# `git commit` at all:
#
#     cat > msg.txt <<EOF          <- UNQUOTED delimiter: substitutes
#     fix the `thing`              <- eaten here, silently
#     EOF
#     git commit -F msg.txt        <- this guard allows it, correctly
#
# Denying `git commit -m` outright would NOT close this either -- it was
# proposed on the grounds that it "closes <<EOF for free", and measured, it does
# not. The only defence is the quoted delimiter, <<'EOF'.
NOT_COVERED = [
    ("cat > msg.txt <<EOF\nfix the " + BT + "thing" + BT + "\nEOF",
     "heredoc writing the message file -- no git commit on this line"),
]


def main():
    if not HOOK.exists():
        print("FAIL: hook not found at %s" % HOOK)
        return 1

    bad = []
    for cmd, why in DENY:
        if not ask(cmd):
            bad.append(("SHOULD DENY but allowed", why, cmd))
    for cmd, why in ALLOW:
        if ask(cmd):
            bad.append(("SHOULD ALLOW but denied", why, cmd))

    total = len(DENY) + len(ALLOW)
    if bad:
        print("FAIL: %d of %d controls wrong" % (len(bad), total))
        for kind, why, cmd in bad:
            print("  %s  [%s]" % (kind, why))
            print("      %s" % cmd)
        return 1

    for cmd, why in NOT_COVERED:
        if ask(cmd):
            print("NOTE: a KNOWN-NOT-COVERED case now denies (%s)." % why)
            print("      Good news, but update the header -- the guard reach has grown.")
            return 1

    print("ok: %d controls green (%d deny, %d allow), both directions"
          % (total, len(DENY), len(ALLOW)))
    print("    NOT covered, asserted so nobody assumes it: %d heredoc case(s)"
          % len(NOT_COVERED))
    print("    every deny-case is a message that really landed corrupted on origin/master")
    return 0


if __name__ == "__main__":
    sys.exit(main())
