#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for testmgr's corpus reconciliation line.

WHY THIS EXISTS. The pre-run corpus banner is computed before the first job
starts, so it cannot see a job whose corpus need is discovered mid-run: its
count is a LOWER BOUND, not a total. Measured 2026-09-22, the banner said
`40 job(s)` and the report said `46 SKIP`, and two seats independently
subtracted the two and concluded six skips had another cause -- one of them
reasoning as far as a missing cross-linker. There was no second cause: the six
were the NATIVE test-c-conformance shards skipping in-run for the same absent
c-testsuite the banner had already named (its `24` is 4 cross arches x 6
shards). Both subtractions were arithmetically correct over two different
populations, which is exactly why neither seat doubted them.

The first repair proposed was to change the banner's 40 to 46. That restores
today's row and leaves the mechanism, so it goes silently wrong the next time a
corpus-dependent family skips in-run. `corpus_reconciliation` RECOMPUTES at the
end instead, where both numbers exist, and therefore cannot go stale.

THE POSITIVE CONTROL IS THE POINT OF THIS FILE. A reconciliation that always
printed "complete" would look identical in a passing run, and the 2026-09-22
case is precisely the one it must not call complete -- so case 2 asserts the
UNDERCOUNT is reported with its arithmetic, using the real 40/46 numbers.

Touches no repo state. Run:
    python3 tools/testmgr_corpus_reconciliation_devtest.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402

FAILED = []


class J:
    """The two fields corpus_reconciliation reads, and nothing else."""

    def __init__(self, status, skip_reason=None):
        self.status = status
        self.skip_reason = skip_reason


def corpus_skip(n):
    return [J("skip", testmgr.SKIP_CORPUS_ABSENT + " library_candidates/c-testsuite")
            for _ in range(n)]


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s %s" % (name, detail))
        FAILED.append(name)


def with_banner(n, jobs):
    testmgr._CORPUS_BANNER_NJOBS = n
    try:
        return testmgr.corpus_reconciliation(jobs)
    finally:
        testmgr._CORPUS_BANNER_NJOBS = None


print("case 1: no banner shown -> says nothing at all")
testmgr._CORPUS_BANNER_NJOBS = None
check("silent when no banner", testmgr.corpus_reconciliation(corpus_skip(3)) is None)

print("case 2: THE 2026-09-22 CASE -- banner 40, end 46. POSITIVE CONTROL.")
line = with_banner(40, corpus_skip(46) + [J("pass"), J("fail")])
check("reports the undercount", line is not None and "LOWER BOUND" in line, repr(line))
check("prints banner count 40", line is not None and "40" in line, repr(line))
check("prints the in-run 6", line is not None and "in-run 6" in line, repr(line))
check("prints the total 46", line is not None and "46" in line, repr(line))
check("warns against subtracting",
      line is not None and "second cause" in line, repr(line))
check("does NOT call it complete",
      line is not None and "complete" not in line, repr(line))

print("case 3: detection was complete -- banner 40, end 40")
line = with_banner(40, corpus_skip(40))
check("says complete", line is not None and "complete" in line, repr(line))
check("does not cry undercount",
      line is not None and "LOWER BOUND" not in line, repr(line))

print("case 4: the corpora are installed -- banner never shown, no skips")
testmgr._CORPUS_BANNER_NJOBS = None
check("silent on a fully-installed box",
      testmgr.corpus_reconciliation([J("pass")] * 10) is None)

print("case 5: OVERCOUNT -- banner 40, end 38. Has never happened; must not be silent.")
line = with_banner(40, corpus_skip(38))
check("reports the overcount", line is not None and "OVERCOUNT" in line, repr(line))
check("blames the detector, not the tree",
      line is not None and "not in the tree" in line, repr(line))

print("case 6: only CORPUS skips are counted -- a tool-absent skip must not inflate it")
jobs = corpus_skip(40) + [J("skip", testmgr.SKIP_HOST_TOOL_ABSENT + " gcc"),
                          J("skip", testmgr.SKIP_HOST_CAP_ABSENT + " rdrand"),
                          J("skip", "some-target: SKIP -- its own business")]
line = with_banner(40, jobs)
check("three non-corpus skips do not move it",
      line is not None and "complete" in line, repr(line))

print("case 7: the banner records its own count, so the two call sites cannot drift")
testmgr._CORPUS_BANNER_NJOBS = None
testmgr.corpus_warning({("library_candidates", "c-testsuite"): 24,
                        ("library_candidates", "lua"): 2}, 26)
check("corpus_warning recorded 26", testmgr._CORPUS_BANNER_NJOBS == 26,
      repr(testmgr._CORPUS_BANNER_NJOBS))

print("case 8: the banner text no longer invites the subtraction")
txt = testmgr.corpus_warning({("library_candidates", "c-testsuite"): 24}, 24)
check("says AT LEAST", "AT LEAST" in txt, repr(txt[:200]))
check("names the aperture", "pre-run detection only" in txt)
check("tells the reader not to subtract", "do NOT" in txt and "subtract" in txt)
testmgr._CORPUS_BANNER_NJOBS = None

print()
if FAILED:
    print("FAILED: %d (%s)" % (len(FAILED), ", ".join(FAILED)))
    sys.exit(1)
print("all corpus-reconciliation rows pass")
