#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a retried job reaches the published report.

testmgr retries a job whose log carries `Text file busy` / `ETXTBSY`
(RUN_RETRY_SIGNATURES) and marks it `flaky` — failed once, passed on retry. It
puts the list in its result JSON. The watcher, which turns that JSON into the
report everyone reads, **dropped the field**: 1155 published reports contained
not one mention of a retry.

That is a suppression with no counter, and it makes its own population
unmeasurable. The question it defeats is the one that was actually asked: "has
the shared-TESTTMP-name race ever fired?" Grepping the reports for `Text file
busy` returns four hits in 55 days, three of them the self-host chain that was
already fixed — a confident NO from a record that **could not have said
otherwise**, because the retry is what stops such a failure reaching a report at
all. Same shape as counting `.expected` siblings to find unwired tests: a
search whose blind spot is exactly the thing it is searching for.
bug-t-a-testtmp-binary-name-is-shared-by-two-tests-and-by-two-targets

The guards are about the CHAIN, not about the formatting: the field must be
emitted, carried, and rendered, and a report with no flakes must not grow a
line that reads as one.

Run: tools/twatch_flaky_report_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, path))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = [path]
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


tw = load("tw_probe", "twatch.py")


def job(name, flaky=False):
    return {"name": name, "sel": name, "status": "pass", "flaky": flaky,
            "attempts": 2 if flaky else 1, "cls": "unit", "advisory": False,
            "pin_built": False, "subject": "", "dur": 1.0, "src": ""}


def report(flaky):
    """A minimal result payload in testmgr's shape, one job per flaky name."""
    return {"sha": "0" * 40, "tier": "full", "host": "probe",
            "verdict": "GREEN", "date": "20260830T000000Z", "wall": 10,
            "jobs": [job(n, True) for n in flaky] + [job("test-core#00")],
            "reds": [], "git": {}, "flaky": list(flaky), "scale": 1.0,
            "compiler_sha256": "deadbeef",
            "skips": {"count": 0, "coverage_holes": 0, "by_reason": {}}}


class FakeClone:
    """write_report_md() needs only a path to write under."""
    def __init__(self, path):
        self.path = path


def render(rep):
    """The published report body, produced by the real writer.

    Not a re-implementation of the formatting: the whole defect was a field
    that existed on one side of this function and not the other, so a guard
    that formats the report itself would have passed throughout."""
    fn = getattr(tw, "write_report_md", None)
    assert callable(fn), (
        "twatch has no write_report_md — this guard cannot run, and a guard "
        "that cannot run must say so rather than pass")
    with tempfile.TemporaryDirectory() as d:
        rel = fn(FakeClone(d), "probe", "0" * 40, None, rep, [], [], [])
        with open(os.path.join(d, rel), errors="replace") as f:
            return f.read()


def t_testmgr_still_emits_it():
    """The producer half. If testmgr stops emitting, carrying it is moot."""
    src = open(os.path.join(HERE, "testmgr.py"), errors="replace").read()
    assert '"flaky": [j.name for j in jobs if j.flaky]' in src, (
        "testmgr no longer puts a `flaky` list in its result JSON, so the "
        "report below has nothing to carry")
    assert 'RUN_RETRY_SIGNATURES = ("Text file busy", "ETXTBSY")' in src, (
        "the retry signatures changed — the flake population this reports on "
        "is defined by them, so the note's claim about what it covers is stale")
    return "testmgr emits `flaky`, retry signatures unchanged"


def t_a_flaky_job_is_named_in_the_report():
    body = render(report(["test-core#42", "test-nilpy#07"]))
    assert "test-core#42" in body, (
        "a job that failed and passed on retry is not NAMED in the published "
        "report — the names are what let a reader ask whether one path keeps "
        "recurring, and a count alone cannot")
    assert "test-nilpy#07" in body, "only the first flaky job was rendered"
    assert "flaky: 2" in body, \
        "the report header does not carry the flake count beside skips"
    return "2 flaky jobs named and counted"


def t_a_clean_report_says_zero_and_nothing_else():
    """A note that appears only when it has something to say cannot report
    finding nothing — which is the failure the `skips` line was given a
    permanent header slot to avoid."""
    body = render(report([]))
    assert "flaky: 0" in body, (
        "a run with no retries does not say so; a reader then cannot tell "
        "'no flakes' from 'this publisher does not carry flakes', which is "
        "exactly the state that hid them for 1155 reports")
    assert "passed on a RETRY" not in body, \
        "the clean report grew a retry warning with no flakes behind it"
    return "clean report says `flaky: 0` and warns about nothing"


def t_the_header_slot_is_permanent():
    """Beside skips/skip_holes, for the same reason those are there."""
    body = render(report([]))
    # The report OPENS with `---` (YAML frontmatter), so the header block is
    # between the first and second one. Splitting on the first `---` yields an
    # empty string and every field then "missing" — which is what this guard
    # reported on its first run, against a correct report.
    parts = body.split("---")
    assert len(parts) >= 3, "the report has no `--- ... ---` header block"
    head = parts[1]
    for field in ("skips:", "skip_holes:", "flaky:"):
        assert field in head, (
            "`%s` is not in the report HEADER. The coverage fields sit there "
            "so a verdict is never read without them; a flake line that "
            "appears only sometimes is one a reader learns to expect to be "
            "absent" % field)
    return "flaky sits in the header beside skips and skip_holes"


TESTS = [t_testmgr_still_emits_it,
         t_a_flaky_job_is_named_in_the_report,
         t_a_clean_report_says_zero_and_nothing_else,
         t_the_header_slot_is_permanent]


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
