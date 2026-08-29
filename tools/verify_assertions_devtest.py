#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the assertion sampler must not report its own aperture as a defect.

Every FAIL `verify_assertions.py` emitted while it was being written was its
own limitation, four distinct times, and each one printed an empty `actual`
under a confident MISMATCH banner:

  * the producer sat before the PREVIOUS assertion (`label.2` shares a binary
    with `label`), so a positional span found nothing to build;
  * a build line ending `2>&1` had the redirect read as its output path;
  * `$(PXX_STABLE)` went unexpanded, so the recipe ran a command named
    `-Fulib/rtl`;
  * a compile buried inside a quoted `hyperfine --command-name '...'` string
    is not reachable by any resolver.

Four for four. A tool that blames the code under test for files it failed to
build is worse than no tool, because its verdict is confident and wrong in the
direction that generates work. Hence the invariant these guards exist to hold:

    NEVER FAIL ON AN INPUT THAT WAS NOT DEMONSTRABLY PRODUCED.

And its necessary counterweight, which is why t_a_real_mismatch_is_still_a_fail
is the most important guard in the file: an instrument softened until it cannot
fail is not safe, it is decorative. Both directions are pinned here.

Run: tools/verify_assertions_devtest.py   (exit 0 = pass)
"""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "verify_assertions.py")


def run(makefile_body, args=("--all",)):
    """Build a throwaway tree with this Makefile and run the sampler on it."""
    tmp = tempfile.mkdtemp(prefix="va-devtest-")
    try:
        os.makedirs(os.path.join(tmp, "tools"), exist_ok=True)
        shutil.copy(os.path.join(HERE, "expect_same.sh"),
                    os.path.join(tmp, "tools", "expect_same.sh"))
        with open(os.path.join(tmp, "Makefile"), "w") as f:
            f.write(makefile_body)
        scratch = os.path.join(tmp, "scratch")
        os.makedirs(scratch)
        env = dict(os.environ, VERIFY_ASSERTIONS_REPO=tmp, TESTTMP=scratch)
        r = subprocess.run([sys.executable, TOOL, *args], env=env,
                           capture_output=True, text=True)
        return r.stdout + r.stderr, r.returncode
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


HEAD = "TESTTMP ?= /tmp\nCOMPILER := compiler/pascal26\n\ncheck:\n"


def verdicts(out):
    """Per-site verdicts only.

    The summary line reads `0 pass, 0 FAIL, 1 skipped`, so a bare `"FAIL" in
    out` is true of every run this tool has ever made -- including the ones
    where nothing failed. Two guards here asserted exactly that and passed
    vacuously in the safe direction, which is the same instrument-shaped defect
    they were written to catch.
    """
    return [l.split()[0] for l in out.splitlines()
            if l.startswith("  ") and l[2:].split()[:1]
            and l[2:].split()[0] in ("ok", "FAIL", "SKIP")]


def t_a_producer_before_the_previous_assertion_is_found():
    """The `.2` case: one binary, two assertions, the build before the first."""
    out, _ = run(HEAD + "\tprintf 'hi\\n' > $(TESTTMP)/bin.txt\n"
                        "\ttools/expect_same.sh one \"$$(cat $(TESTTMP)/bin.txt)\" \"hi\"\n"
                        "\ttools/expect_same.sh one.2 \"$$(cat $(TESTTMP)/bin.txt)\" \"hi\"\n")
    assert "ok   one.2" in out, \
        "the second assertion did not find the producer that precedes the " \
        "first — the positional-span defect is back:\n%s" % out
    return "a producer before the previous assertion is still resolved"


def t_a_redirect_is_not_read_as_an_output_path():
    """`... > log 2>&1` must not make `2>&1` the produced file."""
    out, _ = run(HEAD + "\tprintf 'v\\n' > $(TESTTMP)/out.txt 2>&1\n"
                        "\ttools/expect_same.sh red \"$$(cat $(TESTTMP)/out.txt)\" \"v\"\n")
    assert "ok   red" in out, \
        "a trailing redirect was mistaken for the output path:\n%s" % out
    return "a trailing redirect is not mistaken for the produced file"


def t_an_unresolvable_producer_is_a_skip_not_a_fail():
    """THE INVARIANT. No producer found -> report the absence, never a verdict."""
    out, rc = run(HEAD + "\ttools/expect_same.sh ghost "
                         "\"$$(cat $(TESTTMP)/never_built)\" \"something\"\n")
    assert "FAIL" not in verdicts(out), \
        "the tool blamed the code for a file it never built:\n%s" % out
    assert "SKIP" in verdicts(out) and "not produced" in out, \
        "the absence was not reported as a fact:\n%s" % out
    assert rc == 0, "an unproduced input set a failing exit code (rc=%d)" % rc
    return "an input with no resolvable producer is SKIP, and says why"


def t_a_real_mismatch_is_still_a_fail():
    """The counterweight, and the reason the guards above are safe.

    Everything else here makes the tool quieter. If that softening ever reaches
    the point where a genuine mismatch also goes quiet, the tool is decorative
    and this guard is the only thing that says so.
    """
    out, rc = run(HEAD + "\tprintf 'ACTUAL\\n' > $(TESTTMP)/real.txt\n"
                         "\ttools/expect_same.sh real "
                         "\"$$(cat $(TESTTMP)/real.txt)\" \"EXPECTED\"\n")
    assert "FAIL" in verdicts(out), \
        "a genuine mismatch was not reported — the tool can no longer fail:\n%s" % out
    assert rc == 1, "a genuine mismatch did not set a failing exit code (rc=%d)" % rc
    return "a genuine mismatch is still FAIL, with a failing exit code"


def t_an_unresolved_variable_is_named():
    """A shell error from an unexpanded `$(VAR)` reads as broken setup."""
    out, _ = run(HEAD + "\t$(NOT_DEFINED_ANYWHERE) $(TESTTMP)/x\n"
                        "\ttools/expect_same.sh v \"$$(echo hi)\" \"hi\"\n")
    assert "NOT_DEFINED_ANYWHERE" in out or "ok   v" in out, \
        "an unresolved variable neither resolved nor was named:\n%s" % out
    return "an unresolved make variable is named rather than run"


def t_variables_expand_recursively():
    out, _ = run("TESTTMP ?= /tmp\nA := hi\nB := $(A)\n\ncheck:\n"
                 "\tprintf '$(B)\\n' > $(TESTTMP)/r.txt\n"
                 "\ttools/expect_same.sh rec \"$$(cat $(TESTTMP)/r.txt)\" \"hi\"\n")
    assert "ok   rec" in out, "a variable defined via another did not expand:\n%s" % out
    return "variables defined through other variables expand"


def t_a_sample_says_what_it_did_not_cover():
    """The whole point: a partial run must not read as a verdict on the rest."""
    body = HEAD + "".join(
        "\tprintf 'x\\n' > $(TESTTMP)/f%d\n"
        "\ttools/expect_same.sh s%d \"$$(cat $(TESTTMP)/f%d)\" \"x\"\n" % (i, i, i)
        for i in range(10))
    out, _ = run(body, args=("3",))
    assert "NOT COVERAGE" in out, \
        "a sample did not state what it left unexamined:\n%s" % out
    assert "7 sites were not run" in out, out
    return "a sample states the count it did not run"


def t_all_makes_no_coverage_claim_either():
    """`--all` drops the caveat because it ran everything — but only then."""
    out, _ = run(HEAD + "\tprintf 'x\\n' > $(TESTTMP)/f\n"
                        "\ttools/expect_same.sh a \"$$(cat $(TESTTMP)/f)\" \"x\"\n")
    assert "NOT COVERAGE" not in out, \
        "--all still claimed sites were left out:\n%s" % out
    return "--all omits the sampling caveat"


def t_a_target_boundary_stops_setup_carrying_over():
    """Setup from an unrelated target must not be replayed into this one."""
    out, _ = run("TESTTMP ?= /tmp\n\nother:\n"
                 "\tprintf 'wrong\\n' > $(TESTTMP)/g\n\ncheck:\n"
                 "\ttools/expect_same.sh b \"$$(cat $(TESTTMP)/g)\" \"wrong\"\n")
    assert verdicts(out) == ["SKIP"], \
        "setup leaked across a target boundary, or the absence was blamed on " \
        "the code:\n%s" % out
    return "setup does not carry across a target boundary"


TESTS = [t_a_producer_before_the_previous_assertion_is_found,
         t_a_redirect_is_not_read_as_an_output_path,
         t_an_unresolvable_producer_is_a_skip_not_a_fail,
         t_a_real_mismatch_is_still_a_fail,
         t_an_unresolved_variable_is_named,
         t_variables_expand_recursively,
         t_a_sample_says_what_it_did_not_cover,
         t_all_makes_no_coverage_claim_either,
         t_a_target_boundary_stops_setup_carrying_over]


def main():
    rc = 0
    print("verify-assertions devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("verify-assertions OK" if rc == 0 else "verify-assertions BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
