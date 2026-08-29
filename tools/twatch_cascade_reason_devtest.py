#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a cascade stub prints each red job's REASON next to its name.

The stub used to carry the incriminating half of the evidence and omit the
exculpating half. Its Range section is machine-derived and authoritative in
tone; on `regression-cascade-154d1aa3fba6` it named twelve innocent Track R
commits, while the fact that settled the whole ticket --

    qemu-i386: Could not open '/lib/ld-linux.so.2': No such file or directory

-- lived only in `tstate/<host>.json` and appeared nowhere in the ticket a human
opens. Two fields of one report disagreed and the layout gave no hint that the
lower-status field was the right one. Three separate agents triaged that
cascade; a fourth who trusted the range would have spent an afternoon bisecting
Rust commits for a missing loader.

A cascade whose reasons are visible is triaged by READING. One whose reasons are
a fetch away is triaged by bisection. The reasons are already in hand at filing
time (`report["jobs"][i]["reason"]`), so this is a layout fix, not new plumbing.

Guards, and what each one is for:

  1. the reason renders under its job name -- the ticket.
  2. a job with NO reason still renders, and renders no empty bullet -- the
     absence must read as absence, not as a broken line.
  3. a long reason is truncated -- a stub is a signal, not a log; tstate keeps
     the untruncated text.
  4. a multi-line reason collapses to one line -- same reason, and a raw
     newline would break out of the list item.
  5. the section says the reasons OUTRANK the range. Printing them is only half
     the fix: a reader who sees both and does not know which wins is the reader
     who bisected.
  6. the exact 154d1aa3fba6 string survives into the body -- the regression pin.

Which of these DISCRIMINATE, measured rather than assumed -- the whole set was
re-run against `git show HEAD:tools/twatch.py` (with `CASCADE_REASON_MAX` shimmed
in so the module imports) and **7 of the 9 failed**. The two that passed against
the old code are guard 2's pair, and one half of guard 3: they are absence
checks, and absence was trivially satisfied when nothing rendered at all. That is
correct behaviour for them -- they are regression pins on the NEW rendering (that
adding reasons introduces no empty bullets and stays bounded), not evidence of
the ticket. Read "9 guards" as "7 witnesses and 2 pins", never as nine.

Run: python3 tools/twatch_cascade_reason_devtest.py
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch as tw  # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


class FakeClone:
    def __init__(self, path):
        self.path = path
        self.branch = "master"
        self.published = []

    def publish(self, message, paths=None):
        self.published.append((message, list(paths or [])))

    def commits_between(self, good, bad):
        return [bad]


# The real cascade's own shape: a loader-missing job, a diff job, a job whose
# reason the harness recovered nothing for, and one deliberately oversized.
LOADER = "qemu-i386: Could not open '/lib/ld-linux.so.2': No such file or directory"
DIFF = "@@ -1,4 +1 @@ | -12345 | -99 | -5 | -0 | +"
MULTI = "first line\nsecond line\n\tthird"
LONG = "x" * (tw.CASCADE_REASON_MAX + 80)

JOBS = {
    "lib-test#src:test/test_dynlib.pas": LOADER,
    "test-i386#src:test/test_extern_c.pas": DIFF,
    "test-arm32#src:test/test_extern_c.pas": "",      # no reason recovered
    "test-nilpy#src:test/a.npy": MULTI,
    "test-core#src:test/b.pas": LONG,
}


def report():
    return {
        "tier": "full", "wall": 879.5, "verdict": "RED",
        "compiler_sha256": "deadbeefcafe",
        "jobs": [{"name": sel.split("#")[0] + "#00", "sel": sel, "src": "",
                  "cls": "unit", "status": "fail", "advisory": False,
                  "log": None, "reason": why}
                 for sel, why in JOBS.items()],
    }


def main():
    root = tempfile.mkdtemp(prefix="cascade-reason-")
    pdir = os.path.join(root, "devdocs/progress")
    for b in tw.PROGRESS_BUCKETS:
        os.makedirs(os.path.join(pdir, b), exist_ok=True)
    clone = FakeClone(root)
    tw.CONF["autoticket"] = True
    sha = "154d1aa3fba6c0500271d12a8578158dc04975a7"

    # Stub the two neighbours that shell out to git. The subject here is the
    # job list; a devtest that also needed a real repo would be measuring
    # whether git works.
    tw.staleness_note = lambda *a, **k: ""
    tw.cascade_range_note = lambda *a, **k: "(range note)"

    st = {"host": "seven", "last": None, "jobs": {}, "history": [],
          "job_tier": {},
          "open_regressions": [{"job": "cascade@" + sha[:12],
                                "cascade": sorted(JOBS),
                                "bad": sha, "good": "e417731e9007",
                                "range": [sha], "opened": tw.utcnow()}]}

    tw.file_cascade_ticket(clone, "seven", st, sha, sorted(JOBS), report())
    path = os.path.join(pdir, "backlog", "regression-cascade-154d1aa3fba6.md")
    if not os.path.exists(path):
        print("  FAIL no cascade ticket was filed at all")
        return 1
    with open(path, encoding="utf-8") as f:
        body = f.read()
    section = body.split("## Newly red jobs", 1)[1]

    print("1. the reason renders under its job name")
    check("- `lib-test#src:test/test_dynlib.pas`\n  - " + LOADER in section,
          "loader reason sits under its own job")
    check("- `test-i386#src:test/test_extern_c.pas`\n  - " + DIFF in section,
          "diff reason sits under its own job")

    print("2. a job with no reason renders as a bare bullet")
    check("- `test-arm32#src:test/test_extern_c.pas`\n- " in section
          or section.rstrip().endswith("- `test-arm32#src:test/test_extern_c.pas`"),
          "no reason -> no continuation line")
    check("\n  - \n" not in section and not section.rstrip().endswith("  -"),
          "no empty reason bullet is emitted")

    print("3. a long reason is bounded")
    check(("x" * tw.CASCADE_REASON_MAX) not in section,
          "reason truncated below CASCADE_REASON_MAX (%d)" % tw.CASCADE_REASON_MAX)
    check("…" in section, "truncation is marked, not silent")

    print("4. a multi-line reason collapses to one line")
    check("- `test-nilpy#src:test/a.npy`\n  - first line second line third\n"
          in section, "newlines and tabs squashed to single spaces")

    print("5. the section says which field wins")
    check("the reasons win" in section.lower(),
          "reasons are stated to outrank the Range section")
    check("what CHANGED" in section and "what the job can SEE" in section,
          "and says WHY they outrank it")

    print("6. regression pin -- the string that settled the real cascade")
    check("Could not open '/lib/ld-linux.so.2'" in body,
          "the loader message reaches the ticket body")

    print("\n  %d guard(s), %d FAIL" % (6 + 3, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
