#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: tools/expect_same.sh must make a failed assertion SAY SO.

The helper exists because a bare `test "$(a)" = "$(b)"` prints nothing when it
fails, so testmgr's job_reason() — which records the log TAIL, deliberately and
correctly — ends up recording whatever the recipe printed just before. For the
480 cross-target assertions that is two compile summaries with different code
sizes, which reads as a codegen divergence and is not one.

So the guards here are not "does diff work". They are the four properties that
decide whether the reason field is USABLE:

  * the mismatch reaches stdout at all (the original defect);
  * the label is in it, so a reader knows which assertion spoke;
  * expected and actual are not transposed;
  * the text is STABLE across runs and carries no absolute /tmp path — a
    reason that changes every run looks like a new failure to anything
    comparing this run's reds against the last, and testmgr rewrites absolute
    /tmp paths, so a leaked one varies by construction.

Run: tools/expect_same_devtest.py   (exit 0 = pass)
"""
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SH = os.path.join(HERE, "expect_same.sh")


def run(*args):
    p = subprocess.run([SH] + list(args), capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def t_equal_is_silent_and_passes():
    rc, out, err = run("lbl", "abc", "abc")
    assert rc == 0, "equal operands did not pass (exit %d)" % rc
    assert out == "" and err == "", \
        "a passing assertion printed something: %r / %r" % (out, err)
    return "equal operands pass in silence"


def t_a_mismatch_is_not_silent():
    """The whole point. A silent failure is what created this helper."""
    rc, out, _ = run("lbl", "15", "16")
    assert rc == 1, "a mismatch did not fail (exit %d)" % rc
    assert out.strip(), \
        "a MISMATCH printed nothing to stdout — the defect this replaces"
    return "a mismatch fails and prints"


def t_the_mismatch_shows_both_operands():
    rc, out, _ = run("lbl", "15", "16")
    assert "15" in out and "16" in out, \
        "the diff does not contain both operands: %r" % out
    return "both operands appear in the output"


def t_the_label_is_in_the_output():
    """job_reason() records a tail; the tail must say WHICH assertion."""
    _, out, _ = run("aarch64-fima", "a", "b")
    assert "aarch64-fima" in out, \
        "the label is absent, so the reason cannot name the assertion: %r" % out
    return "the label names the assertion that failed"


def t_expected_and_actual_are_not_transposed():
    """Transposition is its own species of wasted hour, so pin the sides."""
    _, out, _ = run("lbl", "ACTUALVAL", "EXPECTEDVAL")
    minus = [l for l in out.splitlines() if l.startswith("-") and not l.startswith("---")]
    plus = [l for l in out.splitlines() if l.startswith("+") and not l.startswith("+++")]
    assert any("EXPECTEDVAL" in l for l in minus), \
        "the `-` side is not the EXPECTED operand: %r" % out
    assert any("ACTUALVAL" in l for l in plus), \
        "the `+` side is not the ACTUAL operand: %r" % out
    return "`-` is expected and `+` is actual, not the reverse"


def t_the_output_carries_no_absolute_tmp_path():
    """testmgr rewrites absolute /tmp paths, so a leaked one is unstable."""
    _, out, _ = run("lbl", "a", "b")
    assert "/tmp/" not in out, \
        "an absolute /tmp path leaked into the reason: %r" % out
    return "no absolute /tmp path in the output"


def t_the_output_is_stable_across_runs():
    """A reason that changes every run reads as a NEW failure every run.

    `diff -u` stamps each header line with the file's mtime, which is exactly
    the kind of per-run drift that makes a still-red look new.
    """
    _, a, _ = run("lbl", "x", "y")
    time.sleep(1.05)                     # cross a whole-second boundary
    _, b, _ = run("lbl", "x", "y")
    assert a == b, \
        "the output changed between two runs of the same mismatch:\n%r\n%r" % (a, b)
    return "identical mismatches produce identical text"


def t_two_empty_operands_pass_but_warn():
    """A vacuous pass announces itself.

    Two empty strings compare equal, so this passes — which is also how a test
    whose subject silently produced nothing looks. The verdict is deliberately
    unchanged (480 call sites is the wrong place to alter pass/fail), but it
    must not be silent about it.
    """
    rc, out, err = run("vac", "", "")
    assert rc == 0, "an empty-vs-empty comparison stopped passing (exit %d)" % rc
    assert "EMPTY" in err, \
        "a vacuous pass said nothing — indistinguishable from a real one: %r" % err
    assert out == "", "the warning belongs on stderr, not stdout: %r" % out
    return "empty-vs-empty passes, and says that it did"


def t_a_normal_pass_does_not_warn():
    """The warning has to be rare enough to mean something."""
    _, _, err = run("lbl", "abc", "abc")
    assert "EMPTY" not in err, "a normal pass emitted the vacuous warning"
    return "a non-empty pass is not warned about"


def t_multiline_operands_diff_by_line():
    rc, out, _ = run("lbl", "one\ntwo\nthree", "one\nTWO\nthree")
    assert rc == 1
    assert "-TWO" in out and "+two" in out, out
    assert " one" in out, "context lines are missing — -u was not used: %r" % out
    return "multi-line operands diff line by line with context"


def t_wrong_argument_count_is_a_usage_error_not_a_pass():
    """Exit 2, distinct from both verdicts: a broken call must not read green."""
    rc, _, err = run("only-one")
    assert rc == 2, "a malformed call exited %d, not 2" % rc
    assert "usage" in err.lower(), err
    return "a malformed call is a usage error, not a pass"


TESTS = [t_equal_is_silent_and_passes,
         t_a_mismatch_is_not_silent,
         t_the_mismatch_shows_both_operands,
         t_the_label_is_in_the_output,
         t_expected_and_actual_are_not_transposed,
         t_the_output_carries_no_absolute_tmp_path,
         t_the_output_is_stable_across_runs,
         t_two_empty_operands_pass_but_warn,
         t_a_normal_pass_does_not_warn,
         t_multiline_operands_diff_by_line,
         t_wrong_argument_count_is_a_usage_error_not_a_pass]


def main():
    rc = 0
    print("expect-same devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("expect-same OK" if rc == 0 else "expect-same BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
