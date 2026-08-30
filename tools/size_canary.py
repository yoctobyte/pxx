#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Watch the code/data/bss floor of the images nobody measures.

WHY THIS EXISTS. An empty bare-profile ESP32 program was ~26 KB code and ~70 KB
bss when docs/targets/esp32.md was written. At pin v393 it was 50,528 B and
103,692 B -- code roughly doubled, bss grew by half, on a part with ~400 KB of
usable SRAM. It moved over MONTHS, no test failed, and it surfaced only because
a docs page happened to quote the old figure and someone re-measured
(bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss). A
four-month drift found by prose.

The finding is not the 2x. It is that nothing watched. A number nothing prints
is a number nothing checks, and here there was not even a line to make
unconditional -- there was no line.

WHAT IT ASSERTS, AND WHAT IT DOES NOT. This is a DELTA gate, not a ceiling. A
ceiling needs a number a human must maintain and defend; a delta needs only the
last measurement, and it turns "the image grew" into a red on the commit that
grew it. It says nothing about whether the current size is GOOD -- 103,692 B of
bss is the subject of the ticket above, and this file freezes it rather than
blessing it. Fixing that size is Track A's; keeping it from moving unnoticed is
this.

TWO THRESHOLDS, and the asymmetry is from the ticket rather than from taste. On
a 400 KB part the bss floor is the binding constraint -- it is a quarter of SRAM
before the program allocates anything or the stack is counted -- so bss is
watched tighter than code. Both are loose enough not to fire on ordinary RTL
growth, because a canary that cries wolf gets switched off, and a red ratchet is
a disabled ratchet.

EVERY MEASUREMENT PRINTS ON EVERY RUN, pass or fail. Silence on a no-op is
indistinguishable from silence on a never-ran, and the second is what this whole
class of defect turned out to be.

Usage:
  python3 tools/size_canary.py            # measure, compare, exit 1 on growth
  python3 tools/size_canary.py --update   # re-baseline deliberately, then commit
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMPILER = os.path.join(ROOT, "compiler/pascal26")
BASELINE = os.path.join(ROOT, "tools/size_baseline.json")

# The program is EMPTY on purpose: what is being watched is the floor every
# image pays before it does anything, which is the number the part's SRAM
# budget is spent against.
EMPTY_SRC = "program e;\nbegin\nend.\n"

# (subject, extra compiler flags). The four ESP parts are the ticket's subject;
# three of them are the same xtensa image today, and recording all three is how
# a divergence between them becomes visible instead of arriving as a surprise.
#
# x86_64 is here deliberately though the ticket does not ask for it: the sibling
# ticket bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce is the same
# disease on the hosted target, it costs one more compile, and it is the number
# most people would actually notice moving.
SUBJECTS = [
    ("esp32c3-bare", ["--target=esp32c3", "--esp-profile=bare"]),
    ("esp32s3-bare", ["--target=esp32s3", "--esp-profile=bare"]),
    ("esp32s2-bare", ["--target=esp32s2", "--esp-profile=bare"]),
    ("esp32-bare",   ["--target=esp32",   "--esp-profile=bare"]),
    ("x86_64-empty", []),
]

# Growth allowed before this is a red, per metric: the LARGER of a fraction and
# an absolute floor, so a small number is not tripped by rounding and a large
# one is not given a free multiple.
THRESHOLDS = {
    "code": (0.10, 4096),
    "data": (0.10, 4096),
    # Tighter, and the ticket says why: on a ~400 KB part the bss floor is the
    # binding constraint, not the text size.
    "bss":  (0.05, 2048),
}
METRICS = ("code", "data", "bss")

SIZE_RE = re.compile(r"code=(\d+)B\s+data=(\d+)B\s+bss=(\d+)B")


def scratch_dir():
    """A private directory, following the advice that actually survives.

    TESTMGR_TMP first: testmgr launches jobs through an environment ALLOWLIST
    whose prefixes are PXX_/TESTMGR_/LC_/QEMU_, so TESTTMP does not reach a job
    at all and a test that reads only it silently takes the shared /tmp
    fallback (bug-t-the-hardcoded-tmp-guard-recommends-a-variable-testmgr-strips).
    TESTTMP second, for the plain-`make` path where it does reach the child.
    """
    for var in ("TESTMGR_TMP", "TESTTMP"):
        d = os.environ.get(var)
        if d and os.path.isdir(d):
            return d, None
    d = tempfile.mkdtemp(prefix="size-canary-")
    return d, d


def measure(subject, flags, tmp):
    """Compile the empty program and read the size line. -> dict or an error str."""
    src = os.path.join(tmp, "size_canary_%s.pas" % subject.replace("-", "_"))
    out = os.path.join(tmp, "size_canary_%s" % subject.replace("-", "_"))
    with open(src, "w") as fh:
        fh.write(EMPTY_SRC)
    r = subprocess.run([COMPILER] + flags + [src, out], cwd=ROOT,
                       capture_output=True, text=True)
    text = (r.stdout or "") + (r.stderr or "")
    if r.returncode != 0:
        tail = text.strip().splitlines()
        return "compile failed (rc=%d): %s" % (r.returncode,
                                               tail[-1][:90] if tail else "")
    m = SIZE_RE.search(text)
    if not m:
        # A subject that built but printed nothing measurable must FAIL. The
        # alternative is a canary that reports no growth because it measured
        # nothing, which is the exact failure it exists to catch.
        return "built, but no size line to read in the output"
    return dict(zip(METRICS, (int(g) for g in m.groups())))


def limit(base, metric):
    frac, floor = THRESHOLDS[metric]
    return max(base * (1.0 + frac), base + floor)


def load_baseline():
    try:
        with open(BASELINE) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def head_id():
    """(sha12, commit date) of HEAD — the provenance a baseline needs.

    The COMMIT date, not the wall clock: a baseline file must say which tree it
    was measured against, and a timestamp that moves when you re-run the same
    measurement says nothing.
    """
    try:
        r = subprocess.run(["git", "log", "-1", "--format=%H %cI"], cwd=ROOT,
                           capture_output=True, text=True)
        if r.returncode != 0:
            return "", ""
        parts = r.stdout.split()
        return parts[0][:12], (parts[1] if len(parts) > 1 else "")
    except OSError:
        return "", ""


def compare(measured, baseline):
    """-> (rows, failures, shrunk). Pure, so the guards can drive it."""
    base = (baseline or {}).get("subjects") or {}
    rows, failures, shrunk = [], [], []
    for subject, _ in SUBJECTS:
        got = measured.get(subject)
        if isinstance(got, str):
            failures.append("%s: %s" % (subject, got))
            rows.append((subject, None, None, got))
            continue
        want = base.get(subject)
        if want is None:
            # A subject with no baseline asserts NOTHING while looking like
            # coverage. That is the unenrolled-check failure this repo keeps
            # paying for, so it is a red with the command that fixes it.
            failures.append("%s: no baseline — it is measured but unwatched "
                            "(run --update to adopt it)" % subject)
            rows.append((subject, got, None, "UNBASELINED"))
            continue
        for metric in METRICS:
            now, was = got[metric], want.get(metric)
            if was is None:
                failures.append("%s.%s: no baseline for this metric" % (subject, metric))
            elif now > limit(was, metric):
                failures.append("%s.%s: %d -> %d (+%d, +%.1f%%), over the "
                                "allowed %d" % (subject, metric, was, now,
                                                now - was,
                                                100.0 * (now - was) / max(1, was),
                                                int(limit(was, metric))))
            elif now < was:
                shrunk.append("%s.%s: %d -> %d (%d smaller)"
                              % (subject, metric, was, now, was - now))
        rows.append((subject, got, want, None))
    return rows, failures, shrunk


def render(rows, baseline):
    out = []
    at = (baseline or {}).get("measured_at") or {}
    out.append("size-canary: baseline %s (%s)"
               % (at.get("sha", "unknown"), at.get("date", "undated")))
    out.append("  %-14s %10s %10s   %10s %10s   %10s %10s"
               % ("subject", "code", "d(code)", "data", "d(data)", "bss", "d(bss)"))
    for subject, got, want, err in rows:
        if err and not isinstance(got, dict):
            out.append("  %-14s %s" % (subject, err))
            continue
        cells = []
        for metric in METRICS:
            now = got[metric]
            was = (want or {}).get(metric)
            cells.append("%10d" % now)
            cells.append("%10s" % ("—" if was is None
                                   else ("%+d" % (now - was) if now != was else "0")))
        out.append("  %-14s %s%s" % (subject, " ".join(
            "%s %s" % (cells[i], cells[i + 1]) for i in range(0, len(cells), 2)),
            "   " + err if err else ""))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--update", action="store_true",
                    help="rewrite the baseline from this measurement")
    args = ap.parse_args()

    if not os.path.exists(COMPILER):
        print("size-canary: %s is not built — nothing to measure" % COMPILER)
        return 1
    tmp, owned = scratch_dir()
    measured = {}
    try:
        for subject, flags in SUBJECTS:
            measured[subject] = measure(subject, flags, tmp)
    finally:
        if owned:
            for f in os.listdir(owned):
                try:
                    os.unlink(os.path.join(owned, f))
                except OSError:
                    pass
            try:
                os.rmdir(owned)
            except OSError:
                pass

    baseline = load_baseline()
    rows, failures, shrunk = compare(measured, baseline)
    # UNCONDITIONAL. The table prints whether or not anything moved -- a line
    # that appears only when something is wrong cannot report that nothing is.
    print("\n".join(render(rows, baseline)))

    if args.update:
        errs = [s for s, v in measured.items() if isinstance(v, str)]
        if errs:
            print("\nsize-canary: REFUSING to update — %d subject(s) did not "
                  "measure (%s). A baseline written around a broken subject "
                  "silently drops it from the watch."
                  % (len(errs), ", ".join(sorted(errs))))
            return 1
        doc = {"_comment": "Written by tools/size_canary.py --update. "
                           "A DELTA baseline, not a target: it freezes today's "
                           "sizes so growth becomes a red, and blesses none of "
                           "them. See "
                           "bug-a-the-esp32-bare-image-doubled-in-code-and-grew-"
                           "half-again-in-bss.",
               "measured_at": dict(zip(("sha", "date"), head_id())),
               "subjects": {s: measured[s] for s, _ in SUBJECTS}}
        with open(BASELINE, "w") as fh:
            json.dump(doc, fh, indent=2, sort_keys=True)
            fh.write("\n")
        print("\nsize-canary: baseline updated at %s — commit it, and say in "
              "the message WHY the image grew." % (doc["measured_at"]["sha"] or "?"))
        return 0

    if shrunk:
        # Not a failure, and loud anyway: a baseline left above a real shrink is
        # slack in the ratchet, and slack is how the next 2x fits underneath.
        print("\nsize-canary: SMALLER than baseline — good news, and the "
              "baseline is now loose by that much. Re-baseline with --update:")
        for s in shrunk:
            print("  %s" % s)
    if failures:
        print("\nsize-canary: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  %s" % f)
        print("\nA size that moved is not automatically a defect — but it is "
              "always a decision. Either fix what grew, or re-baseline with "
              "tools/size_canary.py --update and say why in the commit.")
        return 1
    print("\nsize-canary: %d subject(s) within their allowances"
          % len(SUBJECTS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
