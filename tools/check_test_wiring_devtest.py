#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: what counts as EVIDENCE that something runs a test file.

`check_test_wiring.py` answers one question -- does any rule run this file --
and it answers it textually, which is right (a reference is a reference
whichever variable expands around it) and was too broad in two ways:

1. **A comment counted as wiring.** A commented-out or merely descriptive
   mention marked an orphan WIRED, so the checker reported nothing. That is
   the bad failure direction: the gap it exists to surface stays invisible,
   and there is no output to notice.

2. **A tools/ mention counted as PROOF, and drove a STALE verdict.** The
   stale-exemption report says "this entry now only hides future gaps", which
   invites a deletion -- and deleting a correct exemption re-opens the gap it
   was covering. It fired on `test/csqlite_file_probe.c`, whose only live
   reference in the tree is a data tuple in
   `tools/testmgr_hardcoded_tmp_devtest.py` that asserts about the file's
   CONTENT and never builds it. The exemption was correct.

The second is deliberately NOT fixed by guessing whether a script "looks like
a runner" -- a devtest listing test files as data mentions them exactly like a
runner that executes them, and a heuristic there goes stale silently. The fix
is to grade the evidence and hand the reader the citation.

Guards run over a throwaway git tree, so every branch is PROVEN to fire
rather than inferred from live data that happens to have no instance.

Run: tools/check_test_wiring_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def _mod(root):
    """Load the checker rebound to a scratch tree."""
    spec = importlib.util.spec_from_file_location(
        "ctw", os.path.join(HERE, "check_test_wiring.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.ROOT = root
    m.EXEMPT = os.path.join(root, "test", "UNWIRED.txt")
    return m


def _tree(makefile="", tools=None, tests=None, unwired=""):
    """A minimal repo: a Makefile, some tools/ scripts, some test/ subjects."""
    root = tempfile.mkdtemp()
    os.makedirs(os.path.join(root, "test"))
    os.makedirs(os.path.join(root, "tools"))
    open(os.path.join(root, "Makefile"), "w").write(makefile)
    for name, body in (tools or {}).items():
        open(os.path.join(root, "tools", name), "w").write(body)
    for name in (tests or []):
        full = os.path.join(root, "test", name)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write("x\n")
    open(os.path.join(root, "test", "UNWIRED.txt"), "w").write(unwired)
    for cmd in (["git", "init", "-q"],
                ["git", "add", "-A"]):
        subprocess.run(cmd, cwd=root, capture_output=True)
    return root


def _run(root):
    """(exit code, stdout) of one check over that tree."""
    m = _mod(root)
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = m.main()
    return rc, buf.getvalue()


# ------------------------------------------------ 1. a comment is not wiring --

def t_a_commented_mention_does_not_wire_a_file():
    """The original defect, in its smallest form."""
    root = _tree(makefile="# same shape as test/orphan.pas\nall:\n\techo hi\n",
                 tests=["orphan.pas"])
    rc, out = _run(root)
    assert "test/orphan.pas" in out, \
        "a mention inside a Makefile COMMENT was accepted as a build rule: %s" % out
    assert rc == 1
    return "a Makefile comment does not count as wiring"


def t_a_hash_comment_inside_a_recipe_body_does_not_wire():
    """A recipe line is indented; the comment marker still leads the line."""
    root = _tree(makefile="all:\n\t# test/orphan.pas is the same shape\n\techo hi\n",
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" in out, out
    return "a `#` line inside a recipe body does not count as wiring"


def t_a_real_rule_still_wires():
    """The fix must not swing the other way and report wired files."""
    root = _tree(makefile="all:\n\t./run test/orphan.pas\n", tests=["orphan.pas"])
    rc, out = _run(root)
    assert "test/orphan.pas" not in out, \
        "a live recipe line stopped counting as wiring: %s" % out
    assert rc == 0, out
    return "a live recipe line still wires its file"


def t_a_trailing_comment_is_still_counted_and_that_is_deliberate():
    """The stated aperture, guarded so it cannot change silently.

    `#` is legal inside a recipe's shell quoting, so cutting a line at the
    first one would drop REAL references -- the worse direction. A guard on
    documented-but-imperfect behaviour is what stops it drifting into
    accidental behaviour.
    """
    root = _tree(makefile="all:\n\techo hi   # test/orphan.pas\n",
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" not in out, \
        "trailing comments are now stripped -- intended, but update the " \
        "documented aperture in wired_paths() and this guard together"
    return "a TRAILING comment still counts (documented aperture)"


# --------------------------------------- 2. how strong is the stale evidence --

def t_a_makefile_wired_exemption_is_hard_stale():
    root = _tree(makefile="all:\n\t./run test/ex.pas\n", tests=["ex.pas"],
                 unwired="test/ex.pas  no longer true\n")
    rc, out = _run(root)
    assert "STALE" in out and "test/ex.pas" in out, out
    assert rc == 1
    return "an exemption the Makefile really wires is hard STALE"


def t_a_missing_file_is_hard_stale():
    root = _tree(unwired="test/gone.pas  file was deleted\n")
    rc, out = _run(root)
    assert "STALE" in out and "test/gone.pas" in out, out
    assert rc == 1
    return "an exemption for a file that no longer exists is hard STALE"


def t_a_tools_only_mention_is_ADVISORY_not_stale():
    """The measured false positive: a devtest naming a file as DATA."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    rc, out = _run(root)
    assert "STALE" not in out, \
        "a bare mention in a tools/ script was reported as STALE, which " \
        "invites deleting a correct exemption: %s" % out
    assert "verify before deleting" in out, out
    return "a tools/-only mention is advisory, not STALE"


def t_the_advisory_cites_its_evidence():
    """A verdict a reader cannot check is a verdict they must take on faith."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    _, out = _run(root)
    assert "tools/x_devtest.py:1" in out, \
        "the advisory does not say WHERE the reference was found: %s" % out
    return "the advisory cites file:line"


def t_an_advisory_alone_does_not_fail_the_check():
    """Severity has to reach the exit code, or it is only a wording change."""
    root = _tree(tools={"x_devtest.py": 'CASES = [("test/ex.c", "/tmp/p.db")]\n'},
                 tests=["ex.c"], unwired="test/ex.c  needs a gitignored corpus\n")
    rc, _ = _run(root)
    assert rc == 0, "an advisory-only run failed the check (exit %d)" % rc
    return "an advisory alone does not fail the check"


def t_a_real_unwired_file_still_fails():
    """The check's whole purpose, guarded against every narrowing above."""
    root = _tree(makefile="all:\n\techo hi\n", tests=["orphan.pas"])
    rc, out = _run(root)
    assert rc == 1 and "nothing runs them" in out, out
    return "an genuinely unwired subject still fails the check"


def t_a_reasonless_exemption_is_still_refused():
    root = _tree(tests=["ex.pas"], unwired="test/ex.pas\n")
    rc, out = _run(root)
    assert rc == 1 and "no REASON" in out, out
    return "an exemption with no reason is still refused"


# ---------------------------------- 5. a DIRECTORY reference vs a truncation --
#
# `-Futest/case_units` names a directory and never the unit inside it, so
# crediting the whole directory is right. The rule that implemented it -- a
# token with a `/` and no extension -- was satisfied just as well by a path the
# collector could not finish reading, because its pattern excludes `$`:
#
#     local src="$ROOT/test/gui/$name.pas"      ->  token `test/gui/`
#
# which blanketed all 26 files under test/gui while gui_suite.sh ran eleven of
# them. Five were run by nothing and the report said zero. These guards pin
# each arm, because the arms are one character apart and the wrong one fails
# SILENTLY -- it can only remove entries from the report, never add one.


def t_a_variable_truncated_path_does_not_blanket_its_directory():
    """The defect, in its smallest form."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'},
                 tests=["gui/ran.pas", "gui/orphan.pas"])
    rc, out = _run(root)
    assert "test/gui/orphan.pas" in out, \
        "a path truncated at a shell variable blanketed its whole directory " \
        "-- the false all-clear this classifier exists to stop: %s" % out
    assert rc == 1
    return "a path truncated at a variable does not blanket its directory"


def t_a_bare_stem_in_the_same_script_credits_that_file_only():
    """The other half: the script DOES supply $name, as a bare word."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'
                                    'run_gui_test ran\n'},
                 tests=["gui/ran.pas", "gui/orphan.pas"])
    _, out = _run(root)
    assert "test/gui/ran.pas" not in out, \
        "a file whose stem the same script names as a bare word was reported " \
        "unwired -- a false RED, which trains people to skip the check: %s" % out
    assert "test/gui/orphan.pas" in out, out
    return "a bare stem in the same script credits that file, and only it"


def t_a_same_stem_path_component_elsewhere_does_not_credit():
    """Measured, not hypothetical: gui_suite.sh names apps/ide/eliah/main.pas,
    which credited test/gui/helloworld/main.pas -- a different file that merely
    shares a stem. A path component naming something else is not evidence."""
    root = _tree(tools={"suite.sh": 'src="$ROOT/test/gui/$name.pas"\n'
                                    'other="$ROOT/apps/eliah/main.pas"\n'},
                 tests=["gui/main.pas"])
    _, out = _run(root)
    assert "test/gui/main.pas" in out, \
        "a same-stem PATH COMPONENT for an unrelated file was accepted as " \
        "evidence that this one runs: %s" % out
    return "a same-stem path component elsewhere is not evidence"


def t_a_glob_over_a_directory_still_blankets_it():
    """The one truncation that IS a directory reference: it runs them all."""
    root = _tree(makefile="all:\n\tfor p in test/corpus/*.pas; do ./run $$p; done\n",
                 tests=["corpus/a.pas", "corpus/b.pas"])
    rc, out = _run(root)
    assert "test/corpus" not in out, \
        "a glob over a directory stopped counting as running its contents: %s" % out
    assert rc == 0, out
    return "a glob over a directory still blankets it"


def t_a_search_path_flag_still_blankets_its_directory():
    """The case the rule was written for must not regress."""
    root = _tree(makefile="all:\n\t./pxx -Futest/units test/main.pas\n",
                 tests=["units/helper.pas", "main.pas"])
    rc, out = _run(root)
    assert "test/units/helper.pas" not in out, \
        "-Fu<dir> stopped crediting the units inside it: %s" % out
    assert rc == 0, out
    return "a -Fu<dir> search path still blankets its directory"


def t_the_checker_does_not_scan_its_own_source():
    """A tool must not be its own witness.

    The checker lives in tools/ and scans tools/, so its own SKIP_DIRS literal
    was collected as a reference to the directories it names. Nothing was lost
    at the time -- those directories are skipped anyway -- but a literal path
    written into this file would silently exempt whatever it named, with no
    rule behind it.
    """
    root = _tree(tools={"check_test_wiring.py": 'SKIP = ("test/orphan.pas",)\n'},
                 tests=["orphan.pas"])
    _, out = _run(root)
    assert "test/orphan.pas" in out, \
        "the checker credited a path named in its own source: %s" % out
    return "the checker does not read its own source as evidence"


TESTS = [t_a_commented_mention_does_not_wire_a_file,
         t_a_hash_comment_inside_a_recipe_body_does_not_wire,
         t_a_real_rule_still_wires,
         t_a_trailing_comment_is_still_counted_and_that_is_deliberate,
         t_a_makefile_wired_exemption_is_hard_stale,
         t_a_missing_file_is_hard_stale,
         t_a_tools_only_mention_is_ADVISORY_not_stale,
         t_the_advisory_cites_its_evidence,
         t_an_advisory_alone_does_not_fail_the_check,
         t_a_real_unwired_file_still_fails,
         t_a_reasonless_exemption_is_still_refused,
         t_a_variable_truncated_path_does_not_blanket_its_directory,
         t_a_bare_stem_in_the_same_script_credits_that_file_only,
         t_a_same_stem_path_component_elsewhere_does_not_credit,
         t_a_glob_over_a_directory_still_blankets_it,
         t_a_search_path_flag_still_blankets_its_directory,
         t_the_checker_does_not_scan_its_own_source]


def main():
    rc = 0
    print("check-test-wiring devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("check-test-wiring OK" if rc == 0 else "check-test-wiring BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
