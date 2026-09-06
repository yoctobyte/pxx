#!/usr/bin/env python3
"""Every case a devtest DEFINES must also be RUN by that devtest.

WHY THIS EXISTS
===============

A Track T devtest defines its cases as top-level `t_*` functions and then runs
them from a hand-maintained list -- `TESTS = (t_a, t_b, ...)` at module level,
or the same tuple written inline in `main()`. Nothing connects the two. Add a
case and forget the list and the case is defined, imported, syntactically
perfect, and never executed.

Measured 2026-09-05 (frankA, `33408ba9b`): four cases added to
`silent_assertion_check_devtest.py` were defined and never ran. **Nothing
errored.** The harness printed `silent-assertion devtest (12 guards)` and
`silent-assertion OK`, which is what it printed the day before. The only tell
was a number that did not move, and a number that does not move is invisible
unless you happen to have remembered the previous one.

That is the same family `devtest_report`'s own docstring is about, and the same
family as a lint whose regex cannot see two of the tools it is meant to police:
**a thing that looks registered and is not executed, where the signal is not an
error but a count that quietly fails to include something.** A count is an
instrument, and a count missing a member reads exactly like a count of
everything.

WHAT IT CHECKS, AND WHAT IT DELIBERATELY DOES NOT
=================================================

For each `tools/*devtest*.py`: every top-level `def t_*` must be REFERENCED
somewhere outside the body of another `t_*` -- as a bare name in a list, tuple,
dict or call, or as a string. That covers the module-level `TESTS =` spelling
and the inline-tuple-in-`main()` spelling equally, which matters: 22 harnesses
use the first and 21 use the second, and a check written for `TESTS =` alone
sees only half the population. Asked that way first, it reported three files
as broken and all three were the inline spelling.

A module that discovers its own cases is exempt, because there the list cannot
drift by construction -- but the test for that is NOT "it calls `globals()`". A
harness may call `globals()` to self-check a hand-maintained list, which is the
guard this lint exists to spread, and keying the exemption on the call made the
first harness to adopt that guard exempt from the lint. True auto-discovery
never NAMES a case; the exemption requires both the call and zero named cases.

The check is deliberately loose in ONE direction: a `t_*` mentioned only inside
another `t_*` still counts as referenced, so a case invoked exclusively as a
helper by a sibling is not flagged. That errs toward silence, which is the
wrong direction for a completeness check -- but the alternative flags every
harness that composes cases, and a guard that flags everything is as empty as
one that never fires. If that becomes the hiding place, tighten it here rather
than adding a second checker.

It says nothing about whether a case is a GOOD case, whether it can fail, or
whether it is aimed at anything. Registration only.

THE APERTURE, WHICH THIS FILE GOT WRONG ABOUT ITSELF
====================================================

Two naming conventions are in use, not one. This lint knew only `t_*` and was
therefore **blind to 20 harnesses and 149 cases** that name their cases `case_*`
-- among them every guard three seats have written this week. It did not error,
did not warn, and did not report a smaller number: `audit()` returns 0 cases for
a file it cannot read and `main()` skips it, so 20 harnesses left the denominator
silently and the summary said `OK -- 404 case(s) across 45 harness(es)`, which is
a true sentence about a population that excludes the files in question.

**That is verbatim the failure this file's own docstring is about** -- *"a count
missing a member reads exactly like a count of everything"* -- committed by the
count that names it. Found 2026-09-06 when a new `case_*` harness was passed to
it explicitly and it answered `NO HARNESSES MATCHED`; the aggregate run had been
answering OK about the other 45 the whole time.

Both prefixes are now recognised (65 harnesses, 553 cases, and **nothing new was
flagged** -- the 20 were correctly registered all along, merely unaudited). And
because a third convention would arrive exactly as silently, the summary now
prints how many `*devtest*.py` files defined **zero** recognised cases. That
number is the aperture: it is 79 today, all of them genuinely single-assertion
scripts or helper tools (checked -- no third convention has three or more
same-prefixed top-level functions anywhere), and a convention appearing tomorrow
makes it rise instead of hiding.
"""

import ast
import glob
import os
import sys


# Both conventions in use. A prefix this tuple does not name is INVISIBLE -- the
# file is silently counted as having no cases -- which is why the summary reports
# the zero-case file count rather than only the harnesses it understood.
CASE_PREFIXES = ("t_", "case_")


def _case_defs(tree):
    return sorted(n.name for n in tree.body
                  if isinstance(n, ast.FunctionDef)
                  and n.name.startswith(CASE_PREFIXES))


def _referenced(tree):
    """Every case NAME mentioned outside the body of a case function.

    A BARE PREFIX IS NOT A NAME, and treating it as one broke the exemption
    below in the direction that flags a correct harness. A prefix-discovering
    harness spells its discovery `k.startswith("case_")`, so the string
    `"case_"` is present in every such file BY CONSTRUCTION -- it is the
    discovery mechanism, not a hand-maintained reference. Collected as a name it
    made `referenced` non-empty, `_self_discovering` returned False, and the
    file was reported as having four unrun cases while running all four.
    Measured 2026-09-06: `tools/park_superseded_devtest.py`, RED in every lane's
    `gate.sh quick`.
    """
    seen = set()
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name.startswith(CASE_PREFIXES):
            continue
        for sub in ast.walk(node):
            if isinstance(sub, ast.Name) and sub.id.startswith(CASE_PREFIXES):
                seen.add(sub.id)
            elif (isinstance(sub, ast.Constant) and isinstance(sub.value, str)
                  and sub.value.startswith(CASE_PREFIXES)
                  and sub.value not in CASE_PREFIXES):
                seen.add(sub.value)
    return seen


def _self_discovering(tree, referenced):
    """True only for a harness that DERIVES its run list from `globals()`.

    Keying this on "the module mentions globals()" was wrong, and it was wrong
    in the direction that hides the defect: a harness can call `globals()` for a
    SELF-CHECK -- exactly the guard this file exists to spread -- while still
    hand-maintaining its list. `silent_assertion_check_devtest.py` is the first
    such harness and it silently became exempt from its own lesson the moment it
    grew the guard. Caught by a control that stopped controlling.

    A harness that truly discovers its cases never NAMES one. So: it calls
    globals(), and it references no case THAT IT DEFINES by name.

    `referenced` is asked for the intersection with this module's own cases
    rather than for emptiness. Emptiness was the first spelling and it is too
    strong: any case-prefixed string in the file defeated the exemption, and a
    prefix-discovering harness carries its own prefix by construction. The
    motivating case is unaffected -- a harness that calls globals() for a
    self-check while hand-maintaining its list NAMES the cases in that list, so
    the intersection is non-empty and it is correctly not exempt.
    """
    if referenced & set(_case_defs(tree)):
        return False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and getattr(node.func, "id", "") == "globals":
            return True
    return False


def audit(path):
    """(n_cases, [unlisted names], self_discovering) for one harness.

    n_cases is 0 for a file that defines none, which the caller skips -- a file
    with nothing to register cannot be a finding, and counting it would inflate
    the denominator with files the question does not apply to.
    """
    try:
        tree = ast.parse(open(path, encoding="utf-8").read())
    except SyntaxError as exc:
        raise SystemExit("devtest-case-registration: cannot parse %s: %s" % (path, exc))
    defs = _case_defs(tree)
    if not defs:
        return 0, [], False
    ref = _referenced(tree)
    if _self_discovering(tree, ref):
        return len(defs), [], True
    return len(defs), [d for d in defs if d not in ref], False


def main(argv):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    paths = argv[1:] or sorted(glob.glob(os.path.join(root, "tools", "*devtest*.py")))

    harnesses = cases = auto = nocases = 0
    bad = []
    for p in paths:
        n, missing, disc = audit(p)
        if not n:
            # NOT nothing: a file whose cases use a prefix CASE_PREFIXES does not
            # name lands here and leaves the denominator without a sound. Counted
            # so the aperture is printed rather than assumed.
            nocases += 1
            continue
        harnesses += 1
        cases += n
        if disc:
            auto += 1
        if missing:
            bad.append((p, missing))

    if not harnesses:
        # A zero over an empty population is not a pass. Whatever glob or
        # argument list produced this asked about nothing.
        print("devtest-case-registration: NO HARNESSES MATCHED -- the population is "
              "empty, so a clean result here means nothing. Check the glob.")
        return 1

    for p, missing in bad:
        print("devtest-case-registration: %s defines %d case(s) that nothing runs:"
              % (os.path.relpath(p, root), len(missing)))
        for m in missing:
            print("    %s" % m)
    if bad:
        print("devtest-case-registration: add each to the harness's case list. "
              "The harness will still print OK without them -- with a smaller "
              "count, which is the only thing that changes.")
        return 1

    print("devtest-case-registration: OK -- %d case(s) across %d harness(es) are all "
          "run (%d harness(es) discover their own)." % (cases, harnesses, auto))
    print("devtest-case-registration: prefixes audited %s; %d file(s) matched the "
          "glob and defined no case under them -- if that number JUMPS, a new "
          "naming convention has appeared and is unaudited."
          % ("/".join(CASE_PREFIXES), nocases))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
