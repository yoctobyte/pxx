#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the size canary fails on growth, and fails on not measuring.

The number it watches drifted 2x over four MONTHS with no test failing -- an
empty ESP32 bare image went from ~26 KB code / ~70 KB bss to 50,528 / 103,692 --
and surfaced only because a docs page quoted the old figure and someone
re-measured (bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss).
A four-month drift found by prose.

So the guards here are aimed at the two ways a canary of this shape dies:

  A. it does not fire when the thing it watches moves; or
  B. it fires green when it measured NOTHING -- a compile that failed, a subject
     with no baseline, a size line it could not read. That one is worse, because
     it looks exactly like the good news it is not, and it is the failure the
     original defect actually was.

The asymmetry between code and bss is deliberate and is pinned here: on a
~400 KB part the bss floor is the binding constraint, not the text size, so bss
is watched tighter. A future simplification that collapses the two thresholds
into one loses the ticket's own argument, and guard 4 is what says so.

Run: python3 tools/size_canary_devtest.py
"""

import io
import os
import sys
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import size_canary as sc  # noqa: E402

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


BASE = {"code": 50528, "data": 344, "bss": 103692}


def baseline(**over):
    subs = {}
    for name, _ in sc.SUBJECTS:
        v = dict(BASE)
        v.update(over.get(name) or {})
        subs[name] = v
    return {"measured_at": {"sha": "abc123abc123", "date": "2026-08-30"},
            "subjects": subs}


def measured(**over):
    out = {}
    for name, _ in sc.SUBJECTS:
        v = over.get(name, dict(BASE))
        out[name] = v
    return out


def main():
    print("1. the subjects the ticket names are all watched")
    names = {n for n, _ in sc.SUBJECTS}
    for want in ("esp32c3-bare", "esp32s3-bare", "esp32s2-bare", "esp32-bare"):
        check(want in names, "%s is a subject" % want)
    check(all("--esp-profile=bare" in f for n, f in sc.SUBJECTS
              if n.endswith("-bare")),
          "every *-bare subject really uses the bare profile")

    print("2. no movement is not a failure, and the delta still renders")
    rows, f, shrunk = sc.compare(measured(), baseline())
    check(f == [], "identical sizes -> no failure", str(f[:1]))
    body = "\n".join(sc.render(rows, baseline()))
    check("esp32c3-bare" in body and " 50528 " in body.replace("  ", " "),
          "the measurement prints even when nothing moved")

    print("3. growth past the allowance fails, and says by how much")
    rows, f, _ = sc.compare(measured(**{"esp32c3-bare": dict(BASE, code=100000)}),
                            baseline())
    check(len(f) == 1 and "esp32c3-bare.code" in f[0], "one failure, named", str(f))
    check("50528 -> 100000" in f[0] and "+49472" in f[0],
          "with the before, the after and the delta", f[0][:80])

    print("4. bss is watched TIGHTER than code -- the ticket's asymmetry")
    check(sc.THRESHOLDS["bss"][0] < sc.THRESHOLDS["code"][0],
          "bss fraction is stricter", str(sc.THRESHOLDS))
    check(sc.THRESHOLDS["bss"][1] < sc.THRESHOLDS["code"][1],
          "bss absolute floor is stricter too")
    # Held at the SAME baseline for both metrics, because the real code and bss
    # baselines differ and "the same absolute jump" would then be a different
    # PERCENTAGE on each -- which measures the baselines, not the thresholds.
    flat = {"code": 100000, "data": 344, "bss": 100000}
    b = baseline(**{"esp32c3-bare": flat})
    bump = int(100000 * 1.07)
    _, f, _ = sc.compare(measured(**{"esp32c3-bare": dict(flat, bss=bump)}), b)
    check(len(f) == 1 and ".bss" in f[0], "+7% on bss is a failure", str(f))
    _, f2, _ = sc.compare(measured(**{"esp32c3-bare": dict(flat, code=bump)}), b)
    check(f2 == [], "...and +7% on code, off the SAME baseline, is not", str(f2[:1]))

    print("5. both arms of the allowance are live")
    # small baseline: the ABSOLUTE floor is what protects it
    check(sc.limit(344, "data") == 344 + 4096,
          "a small number gets the floor, not the fraction", sc.limit(344, "data"))
    # large baseline: the FRACTION is what bounds it
    check(abs(sc.limit(50528, "code") - 50528 * 1.10) < 1e-6,
          "a large number gets the fraction, not a free 4 KiB",
          sc.limit(50528, "code"))
    rows, f, _ = sc.compare(measured(**{"esp32c3-bare": dict(BASE, data=444)}),
                            baseline())
    check(f == [], "+100 B on a 344 B metric (+29%) is inside the floor", str(f[:1]))

    print("6. failing to MEASURE is a failure, never silence")
    rows, f, _ = sc.compare({**measured(),
                             "esp32c3-bare": "compile failed (rc=1): boom"},
                            baseline())
    check(len(f) == 1 and "compile failed" in f[0],
          "a subject that did not compile fails the run", str(f))
    rows, f, _ = sc.compare({**measured(),
                             "esp32s3-bare": "built, but no size line to read"},
                            baseline())
    check(len(f) == 1 and "no size line" in f[0],
          "a subject with no readable size fails the run")

    print("7. an unbaselined subject is a failure, with the fix in the message")
    b = baseline()
    del b["subjects"]["esp32-bare"]
    rows, f, _ = sc.compare(measured(), b)
    check(len(f) == 1 and "no baseline" in f[0], "measured but unwatched -> red")
    check("--update" in f[0], "and the message names the command that adopts it",
          f[0][-40:])

    print("8. a SHRINK is reported and is not a failure")
    rows, f, shrunk = sc.compare(
        measured(**{"esp32c3-bare": dict(BASE, code=40000)}), baseline())
    check(f == [], "smaller than baseline does not fail")
    check(len(shrunk) == 1 and "10528 smaller" in shrunk[0],
          "but it IS reported, so the slack does not go unnoticed", str(shrunk))

    print("9. --update refuses to bake in a subject that did not measure")
    real_measure, real_argv = sc.measure, sys.argv
    try:
        sc.measure = lambda subject, flags, tmp: (
            "compile failed (rc=2): nope" if subject == "esp32-bare"
            else dict(BASE))
        sys.argv = ["size_canary.py", "--update"]
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = sc.main()
        out = buf.getvalue()
        check(rc == 1, "--update exits nonzero", "rc=%s" % rc)
        check("REFUSING to update" in out and "esp32-bare" in out,
              "and says which subject stopped it", out.strip().splitlines()[-1][:70])
    finally:
        sc.measure, sys.argv = real_measure, real_argv

    print("\n  %d guard(s), %d FAIL" % (22, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
