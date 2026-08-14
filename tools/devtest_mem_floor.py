#!/usr/bin/env python3
"""Track T devtest: the small-box admission diagnostic.

bug-t-mem-floor-is-a-fixed-1500mb-so-a-small-box-admits-nothing-ever. The floor
POLICY is a Track U question; this covers the half that is a bug regardless —
a box that cannot admit its own smallest job must SAY so, rather than crawl at
one job per STARVE_GRACE with every liveness signal healthy.
"""
import io
import os
import sys
import contextlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as T                                            # noqa: E402

fails = []


def run_with(avail_mb, total_mb):
    real = T.meminfo
    T.meminfo = lambda: {"MemAvailable": avail_mb << 20, "MemTotal": total_mb << 20}
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            T.report_mem_floor()
    finally:
        T.meminfo = real
    return buf.getvalue()


def check(name, got, want):
    if got != want:
        fails.append("%s\n     got:  %r\n     want: %r" % (name, got, want))
    else:
        print("  ok  %s" % name)


smallest = min(c["est_mem"] for c in T.CLASSES.values())
floor_mb = T.MEM_FLOOR >> 20

# The floor is only meaningful against the SMALLEST class — if that one cannot
# be admitted, none can. Pin the arithmetic so a future CLASSES edit that
# removes the cheapest class cannot silently move this threshold.
check("smallest class is the 256 MB floor set by MIN_EST_MEM",
      smallest, T.MIN_EST_MEM)

# --- a healthy box says nothing ----------------------------------------------
check("64 GB box, 54 GB free: silent",
      run_with(54_000, 64_000), "")
# exactly one byte of headroom over the floor is still healthy
just_ok = (T.MEM_FLOOR + smallest >> 20) + 1
check("just above the floor: silent", run_with(just_ok, just_ok + 100), "")

# --- the 512 MB arm32 Pi, the case the ticket was filed for -------------------
pi = run_with(400, 512)
check("512 MB Pi: warns", bool(pi), True)
check("512 MB Pi: names the starvation path, not a hang",
      "STARVATION path" in pi and "not a hang" in pi, True)
check("512 MB Pi: notes the floor exceeds the whole machine",
      "larger than the machine" in pi, True)
check("512 MB Pi: points at the policy decision",
      "decide-t-mem-floor-policy-on-a-small-box" in pi, True)

# --- the non-obvious one: a 2 GB box is ALSO below the floor -----------------
# 1600 - 256 = 1344 < 1500. Nobody would guess a 2 GB machine cannot admit a
# single job; that is exactly why this has to be printed rather than reasoned.
two_gb = run_with(1600, 2048)
check("2 GB box, 1.6 GB free: warns too", bool(two_gb), True)
check("2 GB box: does NOT claim the floor exceeds the machine",
      "larger than the machine" in two_gb, False)

# --- no /proc/meminfo: claim nothing -----------------------------------------
real = T.meminfo
T.meminfo = lambda: {}
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    T.report_mem_floor()
T.meminfo = real
check("no meminfo: silent rather than a false alarm", buf.getvalue(), "")

print()
if fails:
    print("FAIL (%d):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("devtest_mem_floor: all checks pass")
