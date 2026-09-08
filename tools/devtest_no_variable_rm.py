#!/usr/bin/env python3
"""Controls for .claude/hooks/no-variable-rm.sh, both directions.

WHY THIS FILE EXISTS AND WHY IT IS PYTHON:  the hook refuses any Bash command
whose TEXT contains a variable-or-glob `rm`, and it is right to -- it cannot
tell a heredoc of test cases from a command about to run.  So the controls
cannot be written or driven from a Bash heredoc: the harness refuses itself.
That is not a reason to weaken the guard.  Create this file with the Write tool
and run it with `python3 tools/devtest_no_variable_rm.py`, a command line that
contains no `rm` at all.

The next person to extend the hook will hit this within one minute of trying.

BOTH DIRECTIONS ARE REQUIRED.  The first version of this hook failed one case in
each: prose inside an `echo` fired the guard (fixed by requiring `rm` in true
command position), and a plain `rm -f $SP/x.log` did not fire at all.  A guard
that over-fires on a quoted string is the grep-for-a-literal hazard CLAUDE.md
already names; a guard that misses the owner's actual complaint is not a guard.

The `xargs` and `find -exec` rows are the population my own controls originally
lacked -- frank-seven asked whether its ad-hoc /tmp reaper would trip the hook,
and the honest answer was that the guard could not see it, because the targets
arrive on stdin and never appear in argv.  Controls drawn from the wrong
population pass and certify a broken instrument.
"""
import json
import subprocess
import sys

HOOK = ".claude/hooks/no-variable-rm.sh"

MUST_DENY = [
    # targets that never appear in argv -- the shape with the least review
    "find /tmp -maxdepth 1 -mtime +1 -print0 | xargs -0 -r rm -rf",
    "find $T -print0 | xargs -0 rm -rf",
    'find . -name "*.o" -exec rm -f {} +',
    "find /tmp/x -exec rm {} \\;",
    # the owner's named shape
    'rm -rf "$T/$n"',
    "rm -rf ${BUILD}/obj",
    "cd /tmp && rm -rf $D",
    # non-recursive with a variable: CLAUDE.md's rule is "a VARIABLE or a GLOB",
    # not "a variable in a recursive rm". Measured from the fleet's transcripts.
    "rm -f $SP/suite22.log",
    "for f in a b; do rm -f $S/$f; done",
    # globs, recursive or not
    "rm -rf $WORK/*",
    "rm -f $W/g/*.npy 2>/dev/null",
    # a bare variable as the whole target: one empty expansion from disaster
    'rm -f "$out"',
]

MUST_ALLOW = [
    # literal paths are the hatch, and the hatch must actually work
    "rm -f /tmp/claude-1000/scratch/foo.log",
    "rm -rf /tmp/claude-1000/xyz/scratchdir",
    "rmdir /tmp/emptydir",
    # prose ABOUT rm is not rm -- this row is why the guard checks command position
    'echo "never rm -rf $VAR in a tool call"',
    'grep -n "rm " tools/gate.sh',
    # git rm is a different verb
    "git rm --cached foo.txt",
    # find's own deleter, and xargs feeding something harmless
    'find . -name "*.tmp" -delete',
    "xargs -0 ls",
    "find . -name x -print0 | xargs -0 grep foo",
    # committed scripts are exempt BY CONSTRUCTION: the hook sees the script
    # name, not the rm inside it. This is the intended cleanup route.
    "tools/sync.sh",
    "tools/gate.sh quick",
    "make compiler/pascal26",
    "python3 tools/progress.py board-md",
]


def denies(cmd):
    p = subprocess.run(["bash", HOOK],
                       input=json.dumps({"tool_input": {"command": cmd}}),
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit("hook exited %d on %r: %s" % (p.returncode, cmd, p.stderr))
    return '"deny"' in p.stdout


def main():
    bad = 0
    for label, cases, want in (("MUST DENY", MUST_DENY, True),
                               ("MUST ALLOW", MUST_ALLOW, False)):
        print("===", label)
        for c in cases:
            ok = denies(c) == want
            bad += not ok
            print("  %-12s %s" % ("ok" if ok else "*** FAIL ***", c))
    total = len(MUST_DENY) + len(MUST_ALLOW)
    if bad:
        print("\n*** %d of %d controls FAILED ***" % (bad, total))
        return 1
    print("\nall %d controls pass" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main())
