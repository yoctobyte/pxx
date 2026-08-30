#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the tstate index says WHICH host's map is current for cross targets.

A host's `jobs` map is only as current as THAT HOST's own last full tier --
quick, native and limited run no cross target at all, so every i386 / arm32 /
aarch64 / riscv32 / xtensa entry in a host's state dates from its last FULL run,
however recently the host published something else. The index has always printed
each host's full-through sha; what it never printed is that those shas are of
different AGES, which is the fact a reader actually needs.

Measured 2026-08-30, and it is not hypothetical: `plexus.json` said `fail` for
`test-emit-obj#cxtensa_obj.c` and `test-nilpy#parent_call_after_instantiation`
while `seven`'s newer full tier showed both green -- and both tickets were
already in `done/`. Anyone reading the staler map would have re-triaged fixed
work, which is the same afternoon regression-cascade-154d1aa3fba6 nearly cost
three agents from the other direction.

Guards:

  1. the newest full tier is named, and marked as newest in the table.
  2. every live host appears, ordered newest first.
  3. "behind by" is the DIFFERENCE, not the absolute age -- the newest host is
     not "behind" by its own age.
  4. a retired host is the caller's business, but an undated one is dropped
     here: unknown must never render as recent.
  5. no hosts -> no section at all. A heading over an empty table is a claim
     that there is nothing to say, which is not the same as saying nothing.
  6. one host still renders, and is not reported as behind itself.

Run: python3 tools/twatch_cross_currency_devtest.py
"""

import os
import sys

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


# 2026-08-29T22:36:46Z, and one exactly 31 minutes older.
NOW = 1788043006.0 + 800   # 2026-08-29T22:36:46Z + 13m; a fixed clock, nothing here reads the wall
NEW = {"sha": "e46dbffaa80d8049", "date": "2026-08-29T22:36:46Z", "verdict": "RED"}
OLD = {"sha": "f2706f45eabe3c14", "date": "2026-08-29T22:05:13Z", "verdict": "RED"}
ANCIENT = {"sha": "aaaabbbbcccc1111", "date": "2026-07-31T17:46:27Z", "verdict": "GREEN"}


def main():
    print("0. iso_secs_ago: unknown is None, never recent")
    check(tw.iso_secs_ago("") is None, "empty string -> None")
    check(tw.iso_secs_ago(None) is None, "missing date -> None")
    check(tw.iso_secs_ago("yesterday") is None, "unparseable -> None")
    a = tw.iso_secs_ago("2026-08-29T22:36:46Z", NOW)
    check(a is not None and abs(a - 800) < 2, "a real date -> its age", str(a))

    print("1. the newest full tier is named and marked")
    body = "\n".join(tw.cross_currency_block(
        [("seven", OLD), ("plexus", NEW)], NOW))
    check("Newest full tier in the fleet: `e46dbffaa80d` on plexus" in body,
          "the headline names sha and host")
    check("| plexus | `e46dbffaa80d` | RED | 13m | — (newest) |" in body,
          "and the row says newest, not an age-behind")

    print("2. every live host appears, newest first")
    rows = [l for l in body.splitlines() if l.startswith("| ") and "host |" not in l
            and not l.startswith("|--")]
    check(len(rows) == 2, "both hosts have a row", str(len(rows)))
    check(rows[0].startswith("| plexus") and rows[1].startswith("| seven"),
          "ordered newest first")

    print("3. behind-by is the difference, not the age")
    check("| seven | `f2706f45eabe` | RED | 44m | 31m |" in body,
          "seven is 44m old and 31m behind", [r for r in rows if "seven" in r])

    print("4. an undated host is dropped -- unknown is not recent")
    body2 = "\n".join(tw.cross_currency_block(
        [("plexus", NEW), ("ghost", {"sha": "0" * 16, "verdict": "RED"})], NOW))
    check("ghost" not in body2, "no row for a host with no full-tier date")
    check("plexus" in body2, "and the dated host still renders")

    print("5. nothing to say -> no section")
    check(tw.cross_currency_block([], NOW) == [], "no hosts -> empty list")
    check(tw.cross_currency_block([("ghost", {})], NOW) == [],
          "only undated hosts -> empty list, not an empty table")

    print("6. one host renders and is not behind itself")
    solo = "\n".join(tw.cross_currency_block([("plexus", NEW)], NOW))
    check("— (newest)" in solo and solo.count("| plexus") == 1,
          "single row, marked newest")
    check("behind the newest by" in solo,
          "the column stays, so the table shape does not depend on fleet size")

    print("7. a very stale host reads in days, not thousands of minutes")
    body3 = "\n".join(tw.cross_currency_block(
        [("plexus", NEW), ("borg", ANCIENT)], NOW))
    check("| borg |" in body3 and "d" in body3.split("| borg |")[1].split("|")[3],
          "fmt_age gives it a days-scale age",
          body3.split("| borg |")[1].strip()[:60] if "| borg |" in body3 else "")

    print("\n  %d guard(s), %d FAIL" % (17, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
