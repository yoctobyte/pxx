#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: COMPILER_PATH_RE must consume the WHOLE relative prefix.

testmgr rewrites every recipe invocation of the HEAD compiler onto the run's
private snapshot, so two runs on one box cannot interleave in each other's
self-host chains. The pattern was `\\./compiler/pascal26(?![-\\w])`, unanchored
on the left, and `../../compiler/pascal26` CONTAINS `./compiler/pascal26` at
offset 4 -- so the leading `..` survived and the row was rewritten to
`.././tmp/testmgr-<id>/compiler/pascal26`, which does not exist.

WHY IT WAS INVISIBLE, and why the guard is here rather than in a test/ row:
the one recipe that spells it that way carries a leading `!`, so the missing
binary made the compile step EXIT 0 and PASS while writing a log whose only
content was `No such file or directory`. The next row is a bare `grep -q` for
a note that is therefore absent, and `grep -q` prints nothing when it fails.
So the job was RED under testmgr, GREEN under gate.sh quick and bare make, and
its log was 0 bytes -- the one instrument that could see it was the one that
could not say what it saw.

THE `pin_built` ROW IS THE ONE THAT MATTERS MOST and it is the one the ticket
got backwards. The same constant decides Job.pin_built via
`not COMPILER_PATH_RE.search(body)`. The ticket predicted the widening would
reclassify `../../` rows from pinned to HEAD-built. It cannot: the OLD pattern
already MATCHED those rows -- matching a suffix of the prefix is precisely why
it mangled them -- so `bool(search)` never moved. Measured over all 42 tier
targets and 5987 recipe lines naming compiler/pascal26: one substitution
result moved, zero `bool(search)` moved, zero substitutions were lost.
That census is expensive (42 `make -n`); what is asserted here is the property
it established, on the spellings that produce it.

bug-t-testmgr-rewrites-a-relative-compiler-path-into-a-nonexistent-one
Run: tools/testmgr_compiler_path_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm",
                                              os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

RUN = tm.RUN_COMPILER
# The pattern as it stood, kept verbatim so the guards below can state what
# CHANGED rather than only what is true now.
OLD = __import__("re").compile(r"\./compiler/pascal26(?![-\w])")

# The real row, as `make -n` expands it. Not a paraphrase: the `cd` and the
# leading `!` are both load-bearing and both are why this went unnoticed.
LIBMANIFEST = ("cd test/libmanifest && ! ../../compiler/pascal26 "
               "unitalias_no_row.pas /tmp/t/out > /tmp/t/out.log 2>&1")
PLAIN = "./compiler/pascal26 test/x.pas /tmp/t/x"


def t_a_two_level_prefix_is_consumed_whole():
    got = tm.COMPILER_PATH_RE.sub(RUN, LIBMANIFEST)
    assert RUN in got, "the snapshot path is not in the result at all"
    assert ".." not in got.split(RUN)[0].split("!")[-1], (
        "a relative prefix survived the substitution: %s" % got)
    assert os.path.isabs(got.split("! ")[1].split()[0]), (
        "the rewritten invocation is not absolute: %s" % got)
    return "../../ is replaced entirely, result is absolute"


def t_the_old_pattern_is_what_produced_the_broken_path():
    """The positive control, and it must keep failing.

    Without it this file asserts that the new pattern works and says nothing
    about whether the bug was real -- a guard that cannot distinguish a fix
    from a no-op.
    """
    broke = OLD.sub(RUN, LIBMANIFEST)
    invoked = broke.split("! ")[1].split()[0]
    # `../.` survives, not `..`: the old pattern matched at offset 4 of
    # `../../compiler/pascal26`, so it consumed `./compiler/pascal26` and left
    # the first FOUR characters behind. The exact residue is the evidence --
    # asserting only "it is relative" would pass on a pattern that broke it a
    # different way.
    assert invoked == "../." + RUN, (
        "the old pattern no longer reproduces the defect; this control has "
        "stopped controlling: %s" % invoked)
    assert not os.path.isabs(invoked), "the broken path was absolute after all"
    return "old pattern still yields ../. + snapshot — control fires"


def t_the_ordinary_spelling_is_unchanged():
    assert tm.COMPILER_PATH_RE.sub(RUN, PLAIN) == OLD.sub(RUN, PLAIN), (
        "the 5720 rows spelling it ./$(COMPILER) must be untouched")
    return "./compiler/pascal26 rewrites exactly as before"


def t_the_managed_and_debug_binaries_are_still_excluded():
    for suffix in ("-managed", "-debug"):
        ln = "./compiler/pascal26%s test/x.pas /tmp/t/x" % suffix
        assert tm.COMPILER_PATH_RE.sub(RUN, ln) == ln, (
            "pascal26%s was rewritten onto the snapshot" % suffix)
    return "-managed and -debug still never match"


def t_bool_search_does_not_move_so_pin_built_cannot():
    """THE INVARIANT THE TICKET GOT BACKWARDS.

    pin_built reads `not COMPILER_PATH_RE.search(body)`. If the widening ever
    changes bool(search) for a spelling that occurs, a job silently flips
    between 'the pin compiled this' and 'HEAD compiled this', and twatch uses
    that to refute a bisect. Asserted on every spelling in the tree plus the
    two that must never match.
    """
    for ln in (LIBMANIFEST, PLAIN,
               "../compiler/pascal26 x.pas o",
               "./compiler/pascal26-managed x.pas o",
               "./compiler/pascal26-debug x.pas o",
               "make demos",
               "stable_linux_amd64/default/pinned x.pas o"):
        assert bool(OLD.search(ln)) == bool(tm.COMPILER_PATH_RE.search(ln)), (
            "bool(search) moved for %r — pin_built can now flip" % ln)
    return "bool(search) identical on all 7 spellings; pin_built pinned"


def t_the_real_recipe_row_still_exists_and_still_spells_it_that_way():
    """AIM THE GUARD. Everything above tests a string literal; if the Makefile
    row were respelled `./$(COMPILER)` to dodge the regex -- which the ticket
    explicitly forbids, because the `cd` is the point of that test -- these
    guards would all pass while guarding nothing.
    """
    mk = os.path.join(os.path.dirname(HERE), "Makefile")
    with open(mk, errors="replace") as f:
        text = f.read()
    assert "cd test/libmanifest && ! ../../$(COMPILER)" in text, (
        "the libmanifest row no longer invokes ../../$(COMPILER) — either it "
        "was respelled to suit the harness (do not), or it moved")
    return "test/libmanifest still compiles from inside its own directory"


def main():
    rc = 0
    for fn in (t_a_two_level_prefix_is_consumed_whole,
               t_the_old_pattern_is_what_produced_the_broken_path,
               t_the_ordinary_spelling_is_unchanged,
               t_the_managed_and_debug_binaries_are_still_excluded,
               t_bool_search_does_not_move_so_pin_built_cannot,
               t_the_real_recipe_row_still_exists_and_still_spells_it_that_way):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("compiler_path OK" if rc == 0 else "compiler_path BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
