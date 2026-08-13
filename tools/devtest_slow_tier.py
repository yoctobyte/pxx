#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the demoted shards run SOMEWHERE, exactly once, and evict nothing.

`test-uforth#blocktest` was 594.8s of an 821s full sweep on plexus (2026-08-13)
— 72% of the run, in one job, on every sha, in two tiers at once. It is slow for
a reason rather than for being big:
bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython measures
pxx-compiled uforth at 413s on blocktest.fth against CPython's 196s
INTERPRETING the same source. So it was demoted to the `slow` tier, which the
watcher runs as an idle rung after the full matrix.

Demotion is the dangerous kind of change, because its failure mode is SILENT.
uforth_shards' own docstring names it: "a slow tier is a cost, a wrong list is a
coverage lie". The three ways to get it wrong:

  * demoted from every tier and added to none — the corpus stops being tested
    and every sweep goes green faster, which reads as success;
  * left in the per-sha tiers AND added to `slow` — paid for twice;
  * `slow` folded into the nesting chain — a full run would then "cover" it,
    evict its verdicts, and re-report it as NEW-RED once per cycle forever
    (the exact bug covered_tiers exists to prevent, observed with optdiff).

Run: tools/devtest_slow_tier.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


tm = load("tm", os.path.join(HERE, "testmgr.py"))
tw = load("tw", os.path.join(HERE, "twatch.py"))

fails = []


def check(ok, name, why=""):
    print("  %s %-46s %s" % ("PASS" if ok else "FAIL", name, why))
    if not ok:
        fails.append(name)


def labels(tier):
    """Shard labels of the demoted TARGET that `tier` would actually run.

    Reads the tier the way generate() does — from uforth_shards() plus the
    SLOW_SHARDS split — rather than by running make, so this stays a unit test.
    """
    out = set()
    for tgt, demoted in tm.SLOW_SHARDS.items():
        if tgt not in tm.TIERS[tier]:
            continue
        for label, _ov in SHARDS:
            if (label in demoted) != (tier == tm.SLOW_TIER):
                continue
            out.add(label)
    return out


def main():
    global SHARDS
    SHARDS = tm.uforth_shards()
    if not SHARDS:
        print("skip: `make print-UFORTH_WORDSETS` gave nothing — cannot judge "
              "the split without the authoritative word-set list")
        return 0

    all_labels = {lab for lab, _ in SHARDS}
    demoted = set(tm.SLOW_SHARDS.get("test-uforth", ()))
    print("shards: %d, demoted: %s" % (len(all_labels), sorted(demoted) or "-"))

    print("\nthe demoted shard is somewhere, and only somewhere")
    check(demoted <= all_labels,
          "every demoted label is a real shard",
          "a typo here silently demotes nothing: %s" % sorted(demoted - all_labels))
    check(labels("slow") == demoted, "slow runs exactly the demoted shards")
    for t in ("limited", "full"):
        check(not (labels(t) & demoted),
              "%s no longer carries them" % t, "that was the point")
        check(labels(t) == all_labels - demoted,
              "%s carries every OTHER shard" % t,
              "demotion must not take neighbours with it")

    print("\nno coverage hole: union of the tiers is still the whole corpus")
    check(labels("full") | labels("slow") == all_labels,
          "full + slow == all shards",
          "the failure mode that looks like a speedup")

    print("\nslow is DISJOINT, so a full run cannot evict it")
    check(tw.covered_tiers("slow") == {"slow"}, "covered_tiers(slow)")
    check("slow" not in tw.covered_tiers("full"),
          "a full run does not claim to cover slow",
          "else: evicted verdicts, NEW-RED once per cycle forever")
    check("full" not in tw.covered_tiers("slow"),
          "and a slow run does not claim to cover full")

    print("\nthe watcher actually has a rung for it")
    check(tw.CONF_DEFAULTS.get("idle_slow") is True,
          "idle_slow is on by default",
          "demoted with no rung = never run again")
    check("slow" in tm.TIERS, "testmgr defines the tier")

    print()
    if fails:
        print("FAILED %d check(s): %s" % (len(fails), ", ".join(fails)))
        return 1
    print("slow tier: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
