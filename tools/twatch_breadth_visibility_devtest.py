#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: breadth staleness is VISIBLE, in --status and in the report.

The cross targets run in the `full` tier and nowhere else, and the ladder
reaches `full` only when the box is idle. When pushes arrive faster than a fast
verdict completes, idle never happens and breadth silently stops.

Measured 2026-08-19: 76 testable pushes, 30 native runs and ZERO full runs in the
four hours after the last one completed. Throughout, `--status` said UP and every
verdict said GREEN — both TRUE, and neither answering "has any cross target seen
this tree?", which is what a reader takes from them. The repo's entire push
discipline ("confirm native, offload the matrix") rests on that answer.

What stood between that and a wrong conclusion was one agent warning another by
hand. A correctness property that depends on somebody remembering is a habit, not
a property, and it does not survive a context clear — so the artifact has to say
it (bug-t-the-push-rate-starves-breadth-coverage-entirely).

What must hold:

  * a report at a non-full tier, published while breadth is stale, carries a
    BREADTH banner naming the age and saying the verdict covers x86-64 only;
  * a host that has NEVER completed a full tier says so — the case where the
    age is undefined must not read as "fine";
  * a FULL report carries no banner: it IS the breadth run;
  * a fresh full tier suppresses the banner;
  * the age helper is honest about a malformed timestamp (None, not 0, which
    would render as "0h old" and mean the opposite).

Run: python3 tools/twatch_breadth_visibility_devtest.py
"""
import importlib.util
import pathlib
import re
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tw", HERE / "twatch.py")
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

FAILURES = []


def check(cond, msg):
    print("  %-4s %s" % ("ok" if cond else "FAIL", msg))
    if not cond:
        FAILURES.append(msg)


def iso_ago(secs):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - secs))


class FakeClone:
    def __init__(self, path):
        self.path = path


REPORT = {"tier": "native", "wall": 1.0, "scale": 1.0, "verdict": "GREEN",
          "jobs": [], "compiler_sha256": "abc"}


def report_text(tmp, st, tier="native"):
    clone = FakeClone(tmp)
    rel = tw.write_report_md(clone, "plexus", "a" * 40, "b" * 40,
                             dict(REPORT, tier=tier), [], [], [], st)
    return (pathlib.Path(tmp) / rel).read_text()


def main():
    print("secs_since is honest about what it cannot parse")
    check(tw.secs_since("") is None, "empty timestamp -> None, not 0")
    check(tw.secs_since("not-a-date") is None, "garbage -> None, not 0")
    got = tw.secs_since(iso_ago(7200))
    check(got is not None and 7100 < got < 7300, "a real timestamp -> ~7200s")

    with tempfile.TemporaryDirectory() as tmp:
        print("a native report published while breadth is stale")
        st = {"last_full": {"date": iso_ago(tw.BREADTH_STALE_SECS + 3600),
                            "sha": "c" * 40, "verdict": "GREEN"}}
        text = report_text(tmp, st)
        check("BREADTH IS" in text, "carries a BREADTH banner")
        check("x86-64 only" in text,
              "and says what the verdict does NOT cover")
        check(re.search(r"BREADTH IS \d+d?\d*h STALE", text) is not None,
              "naming the age, so the reader can judge it")

        print("a host that has never completed a full tier")
        text = report_text(tmp, {})
        check("never completed" in text,
              "says so — an undefined age must not read as fine")

        print("breadth is fresh")
        text = report_text(tmp, {"last_full": {"date": iso_ago(60),
                                               "sha": "c" * 40}})
        check("BREADTH" not in text, "no banner when there is nothing to say")

        print("the report of a FULL run")
        st = {"last_full": {"date": iso_ago(tw.BREADTH_STALE_SECS + 3600),
                            "sha": "c" * 40}}
        text = report_text(tmp, st, tier="full")
        check("BREADTH" not in text, "no banner: this run IS the breadth run")

    if FAILURES:
        print("\n%d check(s) FAILED" % len(FAILURES))
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
