#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Guard: a REQUESTED verdict writes a report, and labels its reds honestly.

Run: tools/twatch_requested_report_devtest.py   (exit 0 = pass)

WHY
---
`verify_requested()` wrote no report at all. Every requested row in the archive
(every host, all time) has none, so the row was the ONLY record that the run
happened -- and somebody ASKED for each one. Adding `reds` to the row made the
verdict checkable; a row still cannot carry what only a report holds: the
per-job failure reasons, `compiler_sha256`, the toolchain, and the skip
accounting that says whether the answer covers anything.

THE LABELLING IS THE DELICATE PART, AND IT IS WHY THIS FILE EXISTS.
The report has NEW-RED / FIXED / STILL-RED sections, and all three are claims
about a PREVIOUS state. `verify_requested` deliberately does not walk the HEAD
progression -- its docstring says so, because feeding a days-old sha to the
progression would manufacture NEW-RED/FIXED pairs out of time travel. So it has
no baseline, and filing its reds under STILL-RED would assert they were red
before, while NEW-RED would assert they were not. Both are free claims.

Hence a fifth section that says exactly what is known: red HERE, unclassified.
The control below is the one that matters -- it proves the two renderings are
DISTINGUISHABLE in the artifact a human actually reads. A section that renders
identically to STILL-RED would be a distinction that exists only in my head.
"""

import glob
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

FAILED = []


def check(name, cond, detail=""):
    print("  %-62s %s" % (name, "ok" if cond else "RED"))
    if not cond:
        FAILED.append("%s%s" % (name, (": " + detail) if detail else ""))


def job(name, status):
    return {"name": name, "sel": name, "status": status, "src": "", "log": None}


RED_JOB = job("test-core#42", "fail")
K = tw.job_key


def rendered(**kw):
    """Run the REAL emitter and read the markdown back."""
    tmp = tempfile.mkdtemp(prefix="twreqreport")
    try:
        clone = type("C", (), {"path": tmp})()
        report = {"tier": "full", "wall": 1, "scale": 1.0, "verdict": "RED",
                  "jobs": [RED_JOB], "flaky": [],
                  "skips": {"count": 0, "coverage_holes": 0},
                  "compiler_sha256": "deadbeef"}
        tw.write_report_md(clone, "host", "a" * 40, kw.pop("parent", None),
                           report, kw.pop("new_red", []), kw.pop("fixed", []),
                           kw.pop("still_red", []), **kw)
        found = glob.glob(os.path.join(tmp, tw.TSTATE_REL, "reports", "*.md"))
        assert len(found) == 1, "expected one report, got %r" % (found,)
        return open(found[0]).read()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


print("requested-verify report guard")

body = rendered(unclassified_red=[K(RED_JOB)])
check("an unclassified red is NAMED in the report", K(RED_JOB) in body)
check("...under a heading that says there is no baseline",
      "no baseline at this sha" in body)
check("...and NOT under STILL-RED, which would claim it was red before",
      "STILL-RED" not in body)
check("...and NOT under NEW-RED, which would claim it was not",
      "NEW-RED" not in body)
check("parent_tested is rendered as none, the front-matter half of the claim",
      "parent_tested: none" in body)

# THE CONTROL. If both renderings looked the same, every row above would pass
# while the distinction did nothing. Same job, same emitter, still_red instead.
ctl = rendered(still_red=[K(RED_JOB)], parent="b" * 40)
check("CONTROL: the same red under still_red DOES render as STILL-RED",
      "STILL-RED" in ctl)
check("CONTROL: ...and does NOT carry the no-baseline heading",
      "no baseline at this sha" not in ctl)
check("CONTROL: so the two labellings are distinguishable to a reader",
      ("STILL-RED" in ctl) != ("STILL-RED" in body))

# --- source shape: the caller must actually use it -------------------------
src = open(os.path.join(HERE, "twatch.py")).read()
fn = src[src.index("def verify_requested("):]
fn = fn[:fn.index("\ndef ", 1)]
check("verify_requested writes a report at all", "write_report_md(" in fn)
check("...passing unclassified_red", "unclassified_red=" in fn)
check("...and NOT passing its reds as still_red",
      "still_red=sorted(reds)" not in fn and "sorted(reds))" not in
      fn.split("unclassified_red=")[0].split("write_report_md(")[-1])
check("...non-fatally, since a report is diagnostic and the verdict is not",
      "report not written" in fn)

if FAILED:
    print("\n%d RED:" % len(FAILED))
    for f in FAILED:
        print("  - %s" % f)
    sys.exit(1)
print("requested-verify report: all guards green")
