#!/usr/bin/env python3
"""Devtest: the idle escalation ladder — depth before breadth.

task-t-pin-fast-track-t-owns-verification, deliverable 2. The order is the
whole point:

    new commit -> native     seconds, so Track A+/B never wait on T
    idle       -> limited    NATIVE DEPTH: all frontends + the real corpus,
                             no qemu. Where the yield is, so it runs first
                             and therefore most often.
    still idle -> full       PLATFORM BREADTH: + the qemu cross matrix, an
                             order of magnitude slower, so it only happens
                             if nothing landed meanwhile.
    still idle -> opt        the O-level differential (caller's business)

A push preempts whatever is running and the ladder restarts at the bottom for
the new sha. That is intent, not waste: fresh commits outrank breadth on an
old one.

Run: tools/devtest_idle_ladder.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

SHA = "abc123"
fails = []


def check(cond, what, detail=""):
    print("  %-4s %-42s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def main():
    def phase(lf, mid="limited", deep="full"):
        return tw.idle_phase({"last_full": lf} if lf else {}, SHA, mid, deep)

    print("the ladder")
    check(phase(None) == "limited", "nothing backfilled -> native depth first",
          "depth must not wait behind breadth")
    check(phase({"sha": "other", "tier": "full"}) == "limited",
          "a backfill of a DIFFERENT sha does not count",
          "the ladder is per-sha")
    check(phase({"sha": SHA, "tier": "limited"}) == "full",
          "depth done -> breadth next", "only because the repo is still idle")
    check(phase({"sha": SHA, "tier": "full"}) is None,
          "breadth done -> ladder complete", "opt follows, in the caller")

    print("\nconfiguration edges")
    check(tw.idle_phase({"last_full": {"sha": SHA, "tier": "full"}},
                        SHA, "full", "full") is None,
          "mid == deep, already run -> stop", "must not loop forever")
    check(tw.idle_phase({"last_full": {"sha": "x", "tier": "full"}},
                        SHA, "full", "full") == "full",
          "mid == deep, fresh sha -> run it once")

    print("\nit terminates")
    st, seen = {}, []
    for _ in range(6):
        nxt = tw.idle_phase(st, SHA, "limited", "full")
        if nxt is None:
            break
        seen.append(nxt)
        st["last_full"] = {"sha": SHA, "tier": nxt}
    check(seen == ["limited", "full"], "exactly two rungs, in order", str(seen))

    # The checks above all pass tiers in explicitly, so they say nothing about
    # which ladder the daemon actually climbs. That is the thing that went
    # stale: `limited` was a cheap preview of `full` when it was a third of it,
    # the matrix doubled, and nobody re-measured — by 2026-08-13 limited cost
    # 84% of a full run (686s vs 821s) to cover 78% of its jobs, so the middle
    # rung was spending ~41% of the box to buy 135s of notice.
    print("\nthe SHIPPED ladder, not just the function")
    st, seen = {}, []
    mid, deep = tw.CONF_DEFAULTS["mid_tier"], tw.CONF_DEFAULTS["tier"]
    for _ in range(6):
        nxt = tw.idle_phase(st, SHA, mid, deep)
        if nxt is None:
            break
        seen.append(nxt)
        st["last_full"] = {"sha": SHA, "tier": nxt}
    check(seen == ["full"],
          "default ladder is native -> full, one idle rung",
          "re-measure the tier ratio before adding a rung back: "
          "`--tier <t> --list | wc -l` and the wall from a report")

    print("\nthe tiers behind the ladder")
    lim, full = tw.covered_tiers("limited"), tw.covered_tiers("full")
    check("full" not in lim,
          "a limited run does not cover full's jobs",
          "so it cannot evict the cross verdicts it never ran")
    check("limited" in full, "a full run does cover limited's")

    print()
    if fails:
        print("FAILED %d check(s): %s" % (len(fails), ", ".join(fails)))
        return 1
    print("idle ladder: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
