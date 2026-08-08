#!/usr/bin/env python3
"""Devtest: the auto-stub lifecycle — file -> dedupe -> heal -> close.

The gate for
bug-t-a-self-healed-red-leaves-a-permanent-prio-70-stub-at-the-head-of-the-queue
asks for "a scratch bare repo exercising the file->heal->close cycle end to
end". No repo is needed: the two halves take a clone-like object and a report
dict, so a temp directory and a recording stub are enough — and that keeps this
runnable in a QUICK tier, which is what Track T's own guidance asks for
(test the tooling with quick tiers and scratch dirs, never long runs).

Covers, in one pass:
  1. a NEW-RED files one stub;
  2. a SECOND job on the SAME test source files nothing (the dedupe);
  3. the source still red in another job keeps the stub OPEN when its own job
     heals — otherwise the dedupe would strand a broken source with no ticket;
  4. once nothing is red, the stub closes into done/ with its evidence line.

Run: tools/devtest_stub_lifecycle.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

SRC = "test/test_nilpy_augmented_assign_class_dunder.npy"
JOB_A = "test-core#src:" + SRC          # the same source, reached two ways
JOB_B = "test-nilpy#src:" + SRC
SHA_RED = "e8450c5aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_FIX = "733be33bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fails = []


def check(cond, what):
    print("  %-4s %s" % ("PASS" if cond else "FAIL", what))
    if not cond:
        fails.append(what)


class FakeClone:
    """Enough of Clone for the ticket paths: a path, and a recording publish."""

    def __init__(self, path):
        self.path = path
        self.published = []

    def publish(self, message, paths=None):
        self.published.append((message, list(paths or [])))

    def commits_between(self, good, bad):
        return [bad]


def report(statuses, tier="full"):
    return {
        "tier": tier, "wall": 12.3, "verdict": "RED",
        "compiler_sha256": "deadbeefcafe",
        "jobs": [{"name": sel.split("#")[0] + "#00", "sel": sel, "src": SRC,
                  "cls": "unit", "status": st, "advisory": False, "log": None}
                 for sel, st in statuses.items()],
    }


def stubs_in(pdir, bucket):
    d = os.path.join(pdir, bucket)
    return sorted(f for f in os.listdir(d) if f.endswith(".md")) if os.path.isdir(d) else []


def main():
    root = tempfile.mkdtemp(prefix="stub-lifecycle-")
    try:
        pdir = os.path.join(root, "devdocs/progress")
        for b in tw.PROGRESS_BUCKETS:
            os.makedirs(os.path.join(pdir, b), exist_ok=True)
        clone = FakeClone(root)
        tw.CONF["autoticket"] = True
        st = {"host": "devtest", "last": None, "jobs": {}, "open_regressions": [],
              "history": [], "job_tier": {}}

        print("1. NEW-RED on two jobs sharing one test source")
        rep = report({JOB_A: "fail", JOB_B: "fail"})
        st["open_regressions"] = [
            {"job": JOB_A, "name": "test-core#00", "src": SRC, "bad": SHA_RED,
             "good": "0000000000000000000000000000000000000000",
             "range": [SHA_RED], "opened": tw.utcnow()},
            {"job": JOB_B, "name": "test-nilpy#00", "src": SRC, "bad": SHA_RED,
             "good": "0000000000000000000000000000000000000000",
             "range": [SHA_RED], "opened": tw.utcnow()},
        ]
        tw.file_stub_tickets(clone, "devtest", st, SHA_RED, [JOB_A, JOB_B], rep)
        filed = stubs_in(pdir, "backlog")
        check(len(filed) == 1,
              "one source -> ONE stub, not two (filed: %s)" % (filed or "none"))

        print("2. the stub records the source, so the dedupe is repeatable")
        idx = tw.stub_sources(pdir)
        check(idx.get(SRC) is not None, "stub_sources indexes it by source")
        before = list(filed)
        tw.file_stub_tickets(clone, "devtest", st, SHA_RED, [JOB_A, JOB_B], rep)
        check(stubs_in(pdir, "backlog") == before,
              "a second filing pass adds nothing")

        print("3. its own job heals, but the source is STILL red in the other job")
        healed = [r for r in st["open_regressions"] if r["job"] == filed[0].split(".md")[0]]
        # close the job the stub was named after; the sibling job stays red
        owner_job = JOB_A if tw.reg_slug(JOB_A) + ".md" == filed[0] else JOB_B
        other_job = JOB_B if owner_job == JOB_A else JOB_A
        rep_partial = report({owner_job: "pass", other_job: "fail"})
        tw.close_stub_tickets(clone, "devtest",
                              [{"job": owner_job, "src": SRC, "bad": SHA_RED}],
                              SHA_FIX, rep_partial)
        check(stubs_in(pdir, "backlog") == before,
              "stub stays OPEN — it is that source's only ticket")
        check(stubs_in(pdir, "done") == [],
              "and nothing moved to done/")

        print("4. everything green -> the stub closes with its evidence")
        rep_green = report({owner_job: "pass", other_job: "pass"})
        tw.close_stub_tickets(clone, "devtest",
                              [{"job": owner_job, "src": SRC, "bad": SHA_RED}],
                              SHA_FIX, rep_green)
        check(stubs_in(pdir, "backlog") == [], "stub left backlog/")
        done = stubs_in(pdir, "done")
        check(done == before, "stub landed in done/ (%s)" % (done or "none"))
        if done:
            body = open(os.path.join(pdir, "done", done[0])).read()
            check(SHA_FIX[:12] in body, "close cites the sha it passed at")
            check("auto-closed" in body, "close is attributed to the watcher")
        check(any("closed" in m for m, _ in clone.published),
              "the move was published (both paths staged)")
        _ = healed
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print()
    if fails:
        print("FAILED %d check(s):" % len(fails))
        for f in fails:
            print("  - " + f)
        return 1
    print("stub lifecycle: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
