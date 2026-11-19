#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Run a one-target test recipe to its END and say what failed.

    tools/test_tally.py TARGET [LOG]        e.g. tools/test_tally.py test-core

A test target such as test-core is ONE make target whose recipe is thousands
of test lines. Plain `make` stops that recipe at the first failing line and
reports nothing about the lines it never ran; `make -k` does not help (it
continues past failed TARGETS, and this is one target). So one standing red
silently turns the rest of the recipe into non-coverage.
bug-t-a-one-target-test-recipe-truncates-silently-on-its-first-failure

This runs `make -i TARGET` (every recipe line runs, each failure is printed
as "Error N (ignored)"), then names every failure: the nearest preceding
`expect_same: MISMATCH [label]` or `...: FAIL ...` line since the previous
failure, else the last command before it. Exit 0 only when the recipe ran
to its end with no failure; 1 when any line failed; 2 when make itself
stopped (a `***` error -- a missing prerequisite, a build that broke), with
the tally of what did run, so a truncated run never reads as complete.

It is a REPORT, not a gate change: nothing is narrowed or skipped, and the
same lines run as under plain make. The full-suite hook still applies to the
caller (set PXX_ALLOW_FULL_SUITE=1 when you mean it).
"""
import os
import re
import subprocess
import sys
import tempfile

ERR = re.compile(r"^make(?:\[\d+\])?: \[([^:\]]+):(\d+): ([^\]]+)\] Error (\d+) \(ignored\)")
FATAL = re.compile(r"^make(?:\[\d+\])?: \*\*\* ")
MISMATCH = re.compile(r"^expect_same: MISMATCH \[([^\]]*)\]")
FAILLINE = re.compile(r"\bFAIL\b")


def tally(lines):
    """[(label, context)] for each ignored error, and the fatal line or None."""
    failures, fatal = [], None
    last_label, last_fail, last_cmd, last_any = None, None, None, None
    for line in lines:
        line = line.rstrip("\n")
        m = ERR.match(line)
        if m:
            label = last_label or last_fail or last_cmd or last_any or "(no context)"
            # make's own line number: near the row, not always on it (it can
            # count from where a multi-line command began)
            failures.append((label, "make: Makefile:%s" % m.group(2)))
            last_label, last_fail, last_cmd, last_any = None, None, None, None
            continue
        if FATAL.match(line):
            fatal = line
            continue
        m = MISMATCH.match(line)
        if m:
            last_label = "MISMATCH [%s]" % m.group(1)
            continue
        if FAILLINE.search(line) and not line.lstrip().startswith("#") \
                and "echo " not in line and "grep" not in line:
            last_fail = line.strip()
            continue
        if line.startswith(("./", "/", "tools/", "gcc ", "python3 ", "! ")):
            last_cmd = line.strip()
        elif line.strip() and not line.lstrip().startswith("#"):
            last_any = line.strip()
    return failures, fatal


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        return 2
    target = sys.argv[1]
    if len(sys.argv) > 2:
        log = sys.argv[2]
    else:
        fd, log = tempfile.mkstemp(prefix="test-tally-%s-" % target, suffix=".log")
        os.close(fd)
    with open(log, "w") as out:
        rc = subprocess.call(["make", "-i", target], stdout=out, stderr=subprocess.STDOUT)
    with open(log, errors="replace") as f:
        failures, fatal = tally(f)
    for label, where in failures:
        print("  FAIL  %-60s (%s)" % (label[:160], where))
    if fatal:
        print("test-tally %s: make STOPPED before the end: %s" % (target, fatal))
        print("test-tally %s: %d failure(s) in what ran; the rest did NOT run. log: %s"
              % (target, len(failures), log))
        return 2
    if rc != 0 and not failures:
        print("test-tally %s: make exited %d with no failure line; log: %s" % (target, rc, log))
        return 2
    print("test-tally %s: recipe ran to its end, %d failure(s). log: %s"
          % (target, len(failures), log))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
