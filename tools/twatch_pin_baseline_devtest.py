#!/usr/bin/env python3
"""Devtest: the pin shadow judges the CANDIDATE against the INCUMBENT.

bug-t-the-pin-shadow-cannot-clear-while-its-reds-are-older-than-the-pin. The
shadow used to count reds, so a red set that was equally red under the current
pin vetoed the next one -- and six of the ten reds on 2026-08-19 were blocked on
a Track U decision only the owner can answer, which made `would_pin` unable to
become true at all. An always-false gate is skipped, and then it is not a gate.

The property under test is not "fewer reds pass". It is that the shadow answers
"does this binary have reds the one it replaces does NOT have", and that the
three ways to get that wrong stay closed:

  - a red the new pin CAUSED must not be forgiven by the same pin change
  - a baselined red that goes green must not stay forgiven forever
  - self-host is never waivable, baseline or not
  - an UNKNOWN baseline is empty, never "everything currently red"

That last one arrived by review (coordinator, 2026-08-19) and is the same hazard
as the first through a different door: the first full tier after a pin lands is
a run UNDER the new pin, so bootstrapping a fresh baseline from it waives
whatever that pin just broke. Seeding is therefore only ever from evidence
predating the pin, and "no such evidence" resolves to EMPTY -- which waives
nothing and costs one strict transition.
"""

import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402
from devtest_report import fail_detail  # noqa: E402

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-52s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


# A real temp tree, not a bogus path: the shadow appends a line to
# <tstate>/pin-shadow.log, and letting that fail prints "could not record the
# pin-shadow line" on every case. A passing run must not print what reads as an
# error -- that is the same defect this file's neighbours were fixed for.
_TMP = tempfile.mkdtemp(prefix="pinbaseline-")
os.makedirs(os.path.join(_TMP, twatch.TSTATE_REL), exist_ok=True)


class Clone:
    path = _TMP
    branch = "master"


def shadow(st, reds, pin="v366", selfhost="pass", allow=(), pinned_at=None):
    """Run pin_shadow over a synthetic red set and return the stored verdict."""
    jobs = {j: "fail" for j in reds}
    jobs["selfhost-fixedpoint#src:compiler/compiler.pas"] = selfhost
    twatch.pinned_ref = lambda clone: (pin, "0" * 40)
    twatch.load_pin_allowlist = lambda clone: ({j: "ticket" for j in allow}, [])
    twatch.orphan_keys = lambda *a, **k: set()
    twatch.pin_epoch = lambda clone, version: pinned_at
    twatch.pin_shadow(Clone(), "plexus", st, "a" * 40,
                      {"tier": twatch.PIN_TIER}, jobs, now=jobs)
    return st["pin_shadow"]


TEN = ["test-nilpy#cpyext_%d" % i for i in range(6)] + [
    "lib-test#xml_etree", "test-nilpy#callable_to_str",
    "test-riscv32#cross_float", "tools-devtest#00"]

print("the incumbent's reds are inherited, not held against the candidate")
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}          # what was red under v365
v = shadow(st, TEN, pin="v366")
check(v["inherited"] == 10, "all ten are recognised as inherited",
      "the exact set that vetoed v366")
check(v["unexpected"] == [], "none of them is unexpected")
check(v["qualifies"] is True, "so the shadow QUALIFIES the candidate",
      "the bug: it could not, ever")
check(st["pin_baseline"]["pin"] == "v366" and st["pin_baseline"]["how"].startswith("carried"),
      "the baseline is recorded against the new pin, and says where it came from")

print("\na red the candidate ADDS is still a veto")
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}
v = shadow(st, TEN + ["test-core#brand_new"], pin="v366")
check(v["unexpected"] == ["test-core#brand_new"], "the new red is the only unexpected one")
check(v["qualifies"] is False, "and it vetoes — inheritance is not blanket amnesty")

print("\na red the PIN CHANGE ITSELF introduced is not baselined away")
# The first run after a pin lands is the first evidence ABOUT that pin. Snapshot
# THIS run and a pin-caused regression forgives itself, silently, forever.
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}          # the outgoing pin's reds
v = shadow(st, TEN + ["lib-test#broken_by_the_new_pin"], pin="v366")
check("lib-test#broken_by_the_new_pin" in v["unexpected"],
      "the pin-caused red survives the snapshot", "the whole reason to carry the PREVIOUS set")

print("\na baselined red that goes green leaves the baseline for good")
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}
shadow(st, TEN, pin="v366")                     # baseline of 10 established
v = shadow(st, [j for j in TEN if j != "tools-devtest#00"], pin="v366")
check("tools-devtest#00" not in set(st["pin_baseline"]["reds"]),
      "the healed job drops out of the baseline")
v = shadow(st, TEN, pin="v366")                 # ...and now it breaks again
check("tools-devtest#00" in v["unexpected"],
      "so a RE-break counts as new", "amnesty covers a red, never a job name")

print("\nself-host is never waivable, baseline or not")
st = {"pin_shadow": {"pin": "v365",
                "red_set": TEN + ["selfhost-fixedpoint#src:compiler/compiler.pas"]}}
v = shadow(st, TEN, pin="v366", selfhost="fail")
check(v["qualifies"] is False, "a dirty self-host cannot be inherited into a pass")

print("\nan UNKNOWN baseline is EMPTY — never this run's own reds")
st = {}                                          # no prior full tier recorded
v = shadow(st, TEN, pin="v366")
check(st["pin_baseline"]["reds"] == [],
      "nothing observed before the pin waives nothing",
      "the cost of not knowing is a strict transition, not a silent pass")
check(set(v["unexpected"]) == set(TEN) and v["qualifies"] is False,
      "so all ten stay unexpected and the candidate does NOT qualify")
check("EMPTY" in st["pin_baseline"]["how"],
      "and the log says the baseline is empty and why")

print("\na run that already ran UNDER the incoming pin is not a seed")
# The door the previous four checks left open: not re-reading at pin time, but
# seeding a NEW baseline from the first run after the pin landed. Same result --
# a regression the pin caused, waived by the pin.
st = {"pin_shadow": {"pin": "v366", "red_set": TEN + ["lib-test#broken_by_v366"]}}
v = shadow(st, TEN + ["lib-test#broken_by_v366"], pin="v366")
check(st["pin_baseline"]["reds"] == [],
      "a post-pin observation cannot seed that pin's own baseline")
check("lib-test#broken_by_v366" in v["unexpected"],
      "so the pin-caused red is still visible", "it cannot forgive itself")

print("\na legacy record is dated against pin.log, not assumed")
# Records written before the shadow stamped its pin carry no `pin` key. pin.log
# says when the pin moved, so "was this observed first" stays a measurement.
st = {"pin_shadow": {"at": "2026-08-19T19:34:58Z", "sha": "a" * 40,
                     "unexpected": TEN}}
v = shadow(st, TEN, pin="v366", pinned_at="2026-08-19T19:44:00Z")
check(st["pin_baseline"]["reds"] == sorted(TEN),
      "an observation predating the pin IS the baseline",
      "measured, not assumed")
check("observed" in st["pin_baseline"]["how"] and v["qualifies"] is True,
      "...and it qualifies the candidate on evidence")
st = {"pin_shadow": {"at": "2026-08-19T19:51:12Z", "sha": "a" * 40,
                     "unexpected": TEN}}
v = shadow(st, TEN, pin="v366", pinned_at="2026-08-19T19:44:00Z")
check(st["pin_baseline"]["reds"] == [],
      "an undated-or-later observation does NOT",
      "after the pin moved, it is evidence about the new pin")

print("\nthe verdict stamps the pin it ran under")
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}
v = shadow(st, TEN, pin="v366")
check(v["pin"] == "v366", "so the next transition needs no date arithmetic",
      "the legacy arm retires itself")

print("\nthe baseline is not re-snapshotted while the pin stands still")
st = {"pin_shadow": {"pin": "v365", "red_set": TEN}}
shadow(st, TEN, pin="v366")
shadow(st, TEN + ["test-core#regressed_under_v366"], pin="v366")
v = st["pin_shadow"]
check("test-core#regressed_under_v366" in v["unexpected"],
      "a regression during a pin's life stays visible for that pin's whole life")

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("pin-shadow baseline guards green")
