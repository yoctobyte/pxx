#!/usr/bin/env python3
"""Devtest: Track T auto-pin, shadow mode — decides, never pins.

decide-track-t-autopin-criteria, option A, reopened and chosen by the user
2026-08-08 after the baseline cleared (18 permanent reds -> 2 of 2182).

`make pin` moves the ground every other track builds on, so the cost of
pinning too eagerly is asymmetric. These are the invariants that make the
automation safe enough to eventually trust:

  * a red NOT in the allowlist blocks a pin, and resets the streak;
  * only allowlisted reds qualify — and every allowlist entry must name a
    ticket, or it is refused at load;
  * self-host byte-identical is NEVER waivable, allowlist or streak be damned;
  * K >= 2 consecutive qualifying shas, because one clean matrix can be luck;
  * only the broadest tier may qualify a pin;
  * and in shadow mode, nothing moves `pinned` at all.

Run: tools/devtest_pin_shadow.py   (exit 0 = pass)
"""
import importlib.util
import os
import shutil
import sys
import tempfile
import types

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

SH = "selfhost-fixedpoint#src:compiler/compiler.pas"
fails = []


def check(cond, what, detail=""):
    print("  %-4s %-46s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def main():
    root = tempfile.mkdtemp(prefix="pin-shadow-")
    try:
        os.makedirs(os.path.join(root, tw.TSTATE_REL))
        clone = types.SimpleNamespace(path=root)
        with open(os.path.join(root, tw.PIN_ALLOWLIST_REL), "w") as f:
            f.write("# leading-hash comment\n\n"
                    "test-zlib#00\tbug-t-zlib-oracle\n"
                    "bad-entry-no-ticket\n"
                    "test-asm#3\tbug-elf-pt-gnu-stack\n")

        print("allowlist parsing")
        allow, bad = tw.load_pin_allowlist(clone)
        check(set(allow) == {"test-zlib#00", "test-asm#3"},
              "selectors containing '#' survive", str(sorted(allow)))
        check(bad == ["bad-entry-no-ticket"],
              "an entry with no ticket is refused", "the anti-dumping-ground rule")

        def shadow(auth, st, tier="full"):
            tw.pin_shadow(clone, "devtest", st, "a" * 40, {"tier": tier}, auth)
            return st.get("pin_shadow", {})

        print("\nthe streak, and what breaks it")
        st = {}
        r = shadow({SH: "pass", "test-core#1": "pass"}, st)
        check(r["streak"] == 1 and not r["would_pin"],
              "clean matrix, 1st sha -> pending", "one clean matrix can be luck")
        r = shadow({SH: "pass", "test-core#1": "pass"}, st)
        check(r["streak"] == 2 and r["would_pin"], "2nd consecutive -> WOULD PIN")
        r = shadow({SH: "pass", "test-core#9": "fail"}, st)
        check(r["streak"] == 0 and not r["would_pin"],
              "an unlisted red blocks AND resets", "test-core#9")
        r = shadow({SH: "pass", "test-zlib#00": "fail"}, st)
        check(r["qualifies"] and not r["would_pin"],
              "an ALLOWLISTED red still qualifies", "streak restarts at 1")

        print("\nthe things that can never be waived")
        r = shadow({SH: "fail"}, {"pin_shadow": {"streak": 9}})
        check(not r["would_pin"],
              "self-host red refuses even at streak 9",
              "a compiler that cannot reproduce itself is never anyone's ground")
        st_n = {}
        tw.pin_shadow(clone, "devtest", st_n, "b" * 40, {"tier": "native"},
                      {SH: "pass"})
        check("pin_shadow" not in st_n,
              "a narrower tier is not evaluated at all", "only %s qualifies" % tw.PIN_TIER)

        print("\nan orphaned key must not block a pin forever")
        OLD = "selfhost-fixedpoint#src:compiler/compiler.pas"
        NEW = "selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh"
        OPT = "optdiff#shard1/8"
        # The real plexus shape: the job's `src` changed, so the old key sits at
        # `fail` in a map that is never pruned while the live key passes. A red
        # no run can produce again would block every future pin.
        st_o = {"jobs": {OLD: "fail", NEW: "pass", OPT: "pass"},
                "job_tier": {OLD: "full", NEW: "full", OPT: "opt"}}
        check(tw.orphan_keys(st_o, {NEW: "pass"}, "full") == {OLD},
              "the dead key is an orphan, the opt job is not",
              "a full run never contains opt jobs")
        tw.pin_shadow(clone, "devtest", st_o, "c" * 40, {"tier": "full"},
                      {OLD: "fail", NEW: "pass", OPT: "pass"}, {NEW: "pass"})
        check(st_o["pin_shadow"]["qualifies"],
              "an orphaned red does not block", "it is unclearable by construction")
        st_n = {"jobs": {OLD: "pass"}, "job_tier": {OLD: "full"}}
        tw.pin_shadow(clone, "devtest", st_n, "d" * 40, {"tier": "full"},
                      {OLD: "pass"}, {})
        check(not st_n["pin_shadow"]["qualifies"],
              "NO live self-host evidence refuses",
              "all() over an empty set is True — that must not read as clean")

        print("\nshadow mode moves nothing")
        touched = [p for p in ("stable_linux_amd64", "compiler")
                   if os.path.exists(os.path.join(root, p))]
        check(not touched, "no stable_linux_amd64/ or compiler/ written", str(touched))
        check(os.path.exists(os.path.join(root, tw.PIN_SHADOW_REL)),
              "the decision IS recorded for review", tw.PIN_SHADOW_REL)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    print()
    if fails:
        print("FAILED %d check(s): %s" % (len(fails), ", ".join(fails)))
        return 1
    print("pin shadow: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
