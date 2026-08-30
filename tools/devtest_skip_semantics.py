#!/usr/bin/env python3
"""Devtest: `skip` is published as itself, and stays non-gating.

The gate for bug-t-tstate-launders-skip-into-pass: "a devtest over diff_jobs
covering: skip is not new-red; red -> skip closes the regression; skip -> red
opens one."

Why it matters: tstate used to write a skipped job as "pass", so a GREEN host
could not be told apart from one that actually ran the jobs. On a box with no
corpus trees, 33 full-tier jobs skip — including all 24 c-testsuite
conformance jobs — and the host still published GREEN. `test-uforth` made it
worse by self-skipping wherever ~/projects/uforth is absent.

The fix must publish the third state WITHOUT making it gate: a box that
legitimately cannot run a job must not hold a regression open forever.

Run: tools/devtest_skip_semantics.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-34s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def report(**statuses):
    return {"tier": "full",
            "jobs": [{"name": k, "sel": k, "src": k, "status": v}
                     for k, v in statuses.items()]}


def main():
    print("diff_jobs — the three cases the ticket names, plus the ones that must not move")
    for name, prev, cur, pred, why in [
        ("skip is not new-red", {"a": "pass"}, {"a": "skip"},
         lambda n, nr, f, sr: "a" not in nr, "a box that cannot run it is not a regression"),
        ("red -> skip closes it", {"a": "fail"}, {"a": "skip"},
         lambda n, nr, f, sr: "a" in f, "else an unfetched corpus pins it open forever"),
        ("skip -> red opens one", {"a": "skip"}, {"a": "fail"},
         lambda n, nr, f, sr: "a" in nr, "first real run of a previously skipped job"),
        ("skip survives into tstate", {"a": "pass"}, {"a": "skip"},
         lambda n, nr, f, sr: n["a"] == "skip", "the whole point: green must mean ran"),
        ("pass -> fail still new-red", {"a": "pass"}, {"a": "fail"},
         lambda n, nr, f, sr: "a" in nr, "ordinary regression unaffected"),
        ("fail -> fail still-red", {"a": "fail"}, {"a": "fail"},
         lambda n, nr, f, sr: "a" in sr, "ordinary still-red unaffected"),
        ("skip -> skip is silent", {"a": "skip"}, {"a": "skip"},
         lambda n, nr, f, sr: not (nr or f or sr), "no churn from a permanently absent corpus"),
        ("unknown job defaults pass", {}, {"a": "skip"},
         lambda n, nr, f, sr: "a" not in nr, "a first-seen skip is not a finding"),
    ]:
        n, nr, f, sr, _fs = tw.diff_jobs(prev, report(**cur))
        check(pred(n, nr, f, sr), name, why)

    print("\nreg_open — skip is pass-like for closing, but never opens anything")
    check(tw.reg_open({"job": "a", "bad": "x"}, {"a": "skip"}) is False,
          "per-job entry closes on skip", "red -> skip must not stay open")
    check(tw.reg_open({"cascade": ["a", "b"], "bad": "x"},
                      {"a": "skip", "b": "fail"}) is True,
          "cascade held open by a real fail", "one skip must not close the sweep")

    # An entry can enter the ledger without THIS host ever seeing the red:
    # retire_host() migrates a dead host's open regressions into the survivor.
    # Closing on the red->pass transition therefore never fires, and the entry
    # is immortal — borg's fpc-bootstrap#00 sat open from 2026-07-22 to
    # 2026-08-13 while the same file recorded the job as `pass`.
    print("\nreg_open — a migrated entry closes on STATUS, not on a transition")
    check(tw.reg_open({"job": "fpc-bootstrap#src:compiler/compiler.pas",
                       "bad": "b1976742d", "migrated_from": "borg"},
                      {"fpc-bootstrap#src:compiler/compiler.pas": "pass"}) is False,
          "migrated entry closes when the job passes here",
          "no transition can ever happen for a job that was never red here")
    check(tw.reg_open({"job": "a", "bad": "x", "migrated_from": "borg"},
                      {"a": "fail"}) is True,
          "migrated entry stays open while the job is red",
          "provenance must not close a REAL regression")
    check(tw.reg_open({"job": "a", "bad": "x"}, {}) is True,
          "a job the map has never carried stays open",
          "absent != passing; gone_keys is what retires unrunnable jobs")

    print("\nPASSLIKE is the single definition both paths share")
    check(tw.PASSLIKE == ("pass", "skip"), "PASSLIKE", str(tw.PASSLIKE))

    # A coverage hole must be ANSWERABLE from the archive, not only countable.
    # The report md has always named the holes; the ndjson row carried two bare
    # integers, so "what silently did not run at sha X" needed a join onto the
    # report — and 12 of the 156 hole-carrying runs on 2026-08-30 had no report
    # file at all. Same argument `still_red` was named on.
    print("\nskip_summary names the coverage holes, not just their count")
    tmspec = importlib.util.spec_from_file_location(
        "tm", os.path.join(HERE, "testmgr.py"))
    tm = importlib.util.module_from_spec(tmspec)
    tmspec.loader.exec_module(tm)

    class J(object):
        def __init__(self, name, status, why):
            self.name, self.status, self.skip_reason = name, status, why

    s = tm.skip_summary([
        J("test-core#939", "skip", "host capability absent: rdrand — no RDRAND"),
        J("test-fgl#00", "skip", "corpus absent: fpcsrc is not on this box"),
        J("test-x#01", "skip", "the author disabled it for now"),
        J("test-y#02", "pass", None),
    ])
    check(s["coverage_holes"] == 2, "two of the three skips are holes",
          str(s["coverage_holes"]))
    check(s["hole_jobs"] == ["test-core#939", "test-fgl#00"],
          "the hole jobs are named and sorted", str(s.get("hole_jobs")))
    check("test-x#01" not in (s.get("hole_jobs") or []),
          "a non-hole skip is not listed as a hole",
          "a deliberate disable is not a coverage hole")
    check(s["count"] == 3, "every skip still counted", str(s["count"]))

    print()
    if fails:
        print("FAILED %d check(s): %s" % (len(fails), ", ".join(fails)))
        return 1
    print("skip semantics: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
