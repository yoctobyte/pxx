#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the scratch root the MATCHERS hunt is the one the PRODUCER writes.

`$(TESTTMP)` is read by two programs that must never disagree about it:

  * the Makefile EXPANDS it into every test recipe -- it is where the binaries
    and their outputs are actually written;
  * tools/testmgr.py MATCHES it, and derives TMP_RE, the three make_dry_run
    expressions, _REASON_TMP_RE, the pinned-path root and RUN_TMP from it.

When they disagree, nothing errors. The matchers hunt a prefix no recipe emits,
so privatization silently stops happening (concurrent runs collide again) and
the producer/consumer job merge silently stops happening (which is how
test-core#555/#556 went red on 2026-07-12). testmgr's own comment on those
expressions says it: "all four go blind AT ONCE and fail silently".

That disagreement was REAL and shipped between two commits: testmgr learned to
read TESTTMP, but job_env() is an ALLOWLIST and TESTTMP was not on it, so
`TESTTMP=/foo tools/testmgr.py ...` rebuilt every matcher around /foo while the
make it spawned -- stripped of the variable -- kept emitting /tmp. Measured
2026-08-30. The repair pins the value into BASE_ENV_KEEP rather than
allowlisting it, so agreement holds even when the parent environment is silent
and even after the Makefile's own DEFAULT moves.

The guards are therefore about AGREEMENT and about the two properties the
default must keep, not about any particular path:

  * the value testmgr matches on == the value the make it spawns expands,
    with the parent environment silent AND with it set;
  * the pin is a SET, not a pass-through (present when the parent has none);
  * the Makefile default is per-checkout (two trees cannot collide) and
    STABLE within one (separate invocations hand artefacts to each other);
  * an explicit TESTTMP still wins, because `?=` is what makes the pin work.

Run: tools/testtmp_agreement_devtest.py   (exit 0 = pass)
"""
import hashlib
import importlib.util
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def load_testmgr(testtmp):
    """Import testmgr with TESTTMP set (or deliberately absent) in the parent.

    The environment is deliberately NOT restored afterwards. testmgr writes
    TESTTMP back into its own os.environ on import -- that write is the pin
    every un-env'd `make` it starts depends on -- and a tidy-up here would
    delete the very thing two of the guards below exist to observe. (It did:
    both went red on their first run, on the instrument rather than on the
    code.) Nothing leaks, because every caller states the parent it wants
    before importing, and the guards that need the Makefile's own default pop
    the variable from their own copy of the environment.
    """
    if testtmp is None:
        os.environ.pop("TESTTMP", None)
    else:
        os.environ["TESTTMP"] = testtmp
    spec = importlib.util.spec_from_file_location(
        "tm_probe", os.path.join(HERE, "testmgr.py"))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["testmgr.py"]
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


def make_says(env):
    p = subprocess.run(["make", "-s", "print-TESTTMP"], cwd=REPO, env=env,
                       capture_output=True, text=True)
    assert p.returncode == 0, "make -s print-TESTTMP failed: %s" % p.stderr.strip()
    return p.stdout.strip()


def t_agree_with_a_silent_parent():
    """The common case: nobody sets TESTTMP, and the two halves still agree."""
    tm = load_testmgr(None)
    env = tm.job_env()
    said = make_says(env)
    assert said == tm.TESTTMP, (
        "the make testmgr spawns writes to %r while every matcher hunts %r -- "
        "privatization and the job merge are both blind" % (said, tm.TESTTMP))
    return "silent parent: matchers and producer both on %s" % said


def t_agree_when_the_parent_sets_it():
    """The case that was broken: an explicit TESTTMP moved only the matchers."""
    scratch = os.path.join(os.environ.get("TMPDIR", "/tmp"),
                           "testtmp-agree-probe-%d" % os.getpid())
    tm = load_testmgr(scratch)
    assert tm.TESTTMP == scratch, \
        "testmgr ignored TESTTMP=%r (read %r)" % (scratch, tm.TESTTMP)
    env = tm.job_env()
    said = make_says(env)
    assert said == scratch, (
        "TESTTMP=%r moved the matchers but NOT the recipes -- make wrote to %r. "
        "This is the allowlist gap: the value must be SET into the job "
        "environment, not merely passed through." % (scratch, said))
    return "explicit TESTTMP: both halves moved to %s" % scratch


def t_the_pin_is_a_set_not_a_pass_through():
    """job_env() must supply TESTTMP even when the parent has none.

    A pass-through (adding it to ENV_ALLOW) looks identical in the guard above,
    because there the parent DOES have it. It differs exactly here -- and here
    is the common case."""
    tm = load_testmgr(None)
    env = tm.job_env()
    assert "TESTTMP" in env, (
        "job_env() supplied no TESTTMP with a silent parent, so the spawned "
        "make falls back to the Makefile's own default -- which is the whole "
        "hazard once that default is no longer /tmp")
    assert env["TESTTMP"] == tm.TESTTMP, \
        "job_env() disagrees with the matchers: %r vs %r" % (env["TESTTMP"], tm.TESTTMP)
    return "pinned with a silent parent: %s" % env["TESTTMP"]


def t_pin_survives_the_inherit_escape_hatch():
    """TESTMGR_INHERIT_ENV=1 restores the old environment; it must not unpin."""
    saved = os.environ.get("TESTMGR_INHERIT_ENV")
    os.environ["TESTMGR_INHERIT_ENV"] = "1"
    try:
        tm = load_testmgr(None)
        env = tm.job_env()
        assert env.get("TESTTMP") == tm.TESTTMP, (
            "TESTMGR_INHERIT_ENV=1 dropped the pin (%r vs %r) -- the escape "
            "hatch is for debugging this, so it is the worst place to lose it"
            % (env.get("TESTTMP"), tm.TESTTMP))
    finally:
        if saved is None:
            os.environ.pop("TESTMGR_INHERIT_ENV", None)
        else:
            os.environ["TESTMGR_INHERIT_ENV"] = saved
    return "pin survives TESTMGR_INHERIT_ENV=1"


def t_dry_run_speaks_the_matchers_root():
    """make_dry_run() is a SECOND make, and it passes no env= at all.

    It inherits testmgr's own process environment, so reading TESTTMP into a
    module constant does not reach it. While the Makefile default was also
    /tmp the two agreed by coincidence; the moment the default moved, `make -n`
    named the per-checkout root, TMP_RE still matched it, and the privatizing
    rewrite prefixed RUN_TMP onto an already-per-checkout path -- compiled to
    /tmp/testmgr-scratch-<pid>/pxx-testtmp-<...>/qc_nilpy26 and `not found` at
    exec. Caught by tools/gate.sh quick, not by the agreement guards above,
    because those only exercised job_env()."""
    tm = load_testmgr(None)
    bare = dict(os.environ)
    bare.pop("TESTTMP", None)
    makefile_default = make_says(bare)
    lines = tm.make_dry_run("test-quick")
    assert lines, "make -n test-quick produced no recipe lines"
    if makefile_default != tm.TESTTMP:
        leaked = [l for l in lines if makefile_default in l]
        assert not leaked, (
            "make -n named the Makefile's own default root %r while every "
            "matcher is built on %r -- the rewrite will prefix RUN_TMP onto an "
            "already-rooted path. %d line(s), first: %s"
            % (makefile_default, tm.TESTTMP, len(leaked), leaked[0][:120]))
    assert any(tm.TESTTMP + "/" in l for l in lines), (
        "no dry-run line names %r at all, so this guard proved nothing -- the "
        "target may have stopped using $(TESTTMP)" % tm.TESTTMP)
    return "make -n speaks %s, the root the matchers match" % tm.TESTTMP


def t_the_process_environment_carries_it():
    """The pin that reaches every make, including ones not written yet."""
    tm = load_testmgr(None)
    assert os.environ.get("TESTTMP") == tm.TESTTMP, (
        "testmgr did not write TESTTMP back into its own environment (%r vs "
        "%r), so any `make` it starts without an explicit env= falls back to "
        "the Makefile default" % (os.environ.get("TESTTMP"), tm.TESTTMP))
    return "process environment pinned to %s" % tm.TESTTMP


def t_default_is_per_checkout():
    """Two trees must not derive the same root -- that is the bug being fixed."""
    env = dict(os.environ)
    env.pop("TESTTMP", None)
    here = make_says(env)
    # Derive what a DIFFERENT checkout path yields, using the same expression
    # the Makefile uses. Reproducing the derivation rather than checking out a
    # second tree keeps this a devtest and not a fixture.
    src = open(os.path.join(REPO, "Makefile"), errors="replace").read()
    line = [l for l in src.splitlines() if l.startswith("TESTTMP ?=")]
    assert len(line) == 1, "expected exactly one `TESTTMP ?=` line, found %d" % len(line)
    assert "CURDIR" in line[0], (
        "the TESTTMP default no longer mentions $(CURDIR), so it is not "
        "per-checkout: %r" % line[0])
    other = "/home/somebody/a-second-checkout"
    h_here = hashlib.sha1(REPO.encode()).hexdigest()[:10]
    h_other = hashlib.sha1(other.encode()).hexdigest()[:10]
    assert h_here != h_other, "sha1 collision in a devtest fixture (astonishing)"
    assert h_here in here, (
        "the root make reports (%r) does not contain the hash of $(CURDIR) "
        "(%s) -- the derivation is not what this guard thinks it is" % (here, h_here))
    return "per-checkout: %s carries the $(CURDIR) hash" % here


def t_default_is_stable_within_a_checkout():
    """Separate `make` runs in one tree hand artefacts to each other by path."""
    env = dict(os.environ)
    env.pop("TESTTMP", None)
    a, b = make_says(env), make_says(env)
    assert a == b, (
        "two invocations in one tree produced different roots (%r, %r) -- a "
        "per-invocation mktemp breaks the producer/consumer pairing rather "
        "than isolating it" % (a, b))
    return "stable within a checkout: %s" % a


def t_an_explicit_value_still_wins():
    """`?=` is what lets testmgr's pin override the default. Guard it."""
    env = dict(os.environ)
    env["TESTTMP"] = "/tmp"
    said = make_says(env)
    assert said == "/tmp", (
        "an explicit TESTTMP=/tmp did not win (make said %r) -- the default is "
        "not `?=` any more, and testmgr's pin is now inert" % said)
    return "explicit value overrides the default"


TESTS = [t_agree_with_a_silent_parent,
         t_agree_when_the_parent_sets_it,
         t_dry_run_speaks_the_matchers_root,
         t_the_process_environment_carries_it,
         t_the_pin_is_a_set_not_a_pass_through,
         t_pin_survives_the_inherit_escape_hatch,
         t_default_is_per_checkout,
         t_default_is_stable_within_a_checkout,
         t_an_explicit_value_still_wins]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-44s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-44s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
