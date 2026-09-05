#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a tstate report says which TOOLCHAIN measured it, absence included.

bug-t-tstate-fingerprints-the-code-and-the-hardware-but-not-the-emulator-toolchain.

`code_fp` says which harness, `hw_fp` which machine, `compiler_sha256` which
binary — and a cross-target verdict is also a statement about an EMULATOR,
which nothing recorded. Measured 2026-09-04: seven, the box that does all the
sweeping, ran qemu 8.2.2 / kernel 6.8.0-138 / gcc 13.3.0 while plexus, the box
every lane develops on, ran 10.2.1 / 7.0.0-30 / 15.2. `c_crtl_wait.c`'s riscv32
rusage row was red on one and green on the other from BYTE-IDENTICAL compiler
bytes and an empty diff outside `devdocs/`, and no field in the archive could
tell a reader that. So the honest reading — "true about a 2024 emulator" — was
unavailable, and "the compiler regressed" was the only one on offer.

WHAT THIS GUARDS, and each row is a way the field could go quietly useless:

1. **The list is complete.** `RUNNER_BINARIES` is explicit rather than parsed
   out of `run_target.sh`, because a parse that stopped matching would shrink
   the fingerprint to nothing while still printing a line. The cost of being
   explicit is drift, so this row pays it: every runner `run_target.sh` can
   `exec` must be named. A new cross target whose emulator nothing fingerprints
   is precisely the next instance of this bug.

2. **Absence is printed, not omitted.** A missing runner is the condition that
   produced six false regression tickets on 2026-09-04 — all accusing the
   compiler, all caused by wasmtime not being installed. An entry that vanishes
   when the tool is absent turns the loudest fact into the quietest.

3. **The fingerprint moves when a runner appears or disappears.** Installing
   wasmtime on seven changed what six jobs measured; a fingerprint hashing only
   the versions it found would be identical before and after.

4. **An older report is distinguishable from a toolchain that measured
   nothing.** Every report written before 2026-09-05 has no `toolchain:` line
   at all, and that must not render as a blank or a zero.

5. **The INDEX renders it too, and a host that has published nothing since the
   field existed does not read as a host that agrees.** The ticket's premise is
   that no field a reader can check exists, and a reader triaging a cross-target
   red starts at `TSTATE.md`, not at a report. A blank cell there is the same
   defect one layer up: absence rendering as agreement.

Run: python3 tools/twatch_toolchain_devtest.py
"""

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import twatch                                                   # noqa: E402

fails = []


def check(cond, what, detail=""):
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                  # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-56s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def main():
    print("1. the runner list is complete — every emulator run_target.sh can exec")
    rt = (ROOT / "tools" / "run_target.sh").read_text(errors="replace")
    # `exec <tool>` and `exec "$HOME/.local/bin/<tool>"` are the two spellings
    # a runner is invoked through; `exec "$bin"` is the NATIVE arm and is not a
    # runner. Derived from the script rather than restated, so this row cannot
    # agree with a stale copy of the same list.
    execs = set()
    for m in re.finditer(r'^\s*exec\s+("?\$?\S+?"?)\s+"\$bin"', rt, re.M):
        tok = m.group(1).strip('"')
        execs.add(os.path.basename(tok))
    execs.discard("$bin")
    check(execs, "run_target.sh's exec arms are readable at all",
          "found: %s" % ", ".join(sorted(execs)) if execs else
          "NONE — the scan stopped matching, and a scan that finds nothing "
          "would pass every row below")
    missing = sorted(execs - set(twatch.RUNNER_BINARIES))
    check(not missing,
          "and every one is named in twatch.RUNNER_BINARIES",
          "unfingerprinted: %s" % ", ".join(missing) if missing else
          "%d runner(s)" % len(twatch.RUNNER_BINARIES))

    print("2. absence is PRINTED, never omitted")
    absent = {"kernel": "x", "gcc": None, "qemu-i386": "9.9.9",
              "qemu-arm": None, "wasmtime": None}
    line = twatch.toolchain_line(absent)
    check(line.count("ABSENT") == 3,
          "a missing tool renders as ABSENT",
          "%d of 3 in: %s" % (line.count("ABSENT"), line))
    check("gcc=ABSENT" in line and "wasmtime=ABSENT" in line,
          "and it is named, so a reader knows WHICH is missing", line)

    print("3. a mixed toolchain cannot collapse into a single version")
    mixed = {"kernel": "k", "gcc": "1", "qemu-i386": "8.2.2",
             "qemu-arm": "10.2.1"}
    ml = twatch.toolchain_line(mixed)
    check("8.2.2" in ml and "10.2.1" in ml,
          "disagreeing emulators are both spelled out", ml)
    same = {"kernel": "k", "gcc": "1", "qemu-i386": "8.2.2",
            "qemu-arm": "8.2.2"}
    sl = twatch.toolchain_line(same)
    check("(2 of 2)" in sl,
          "and a collapsed group still says how many agreed",
          "%s — so three-of-six cannot read as six" % sl)

    print("4. the fingerprint moves on the changes that matter")
    base = {"kernel": "k", "gcc": "1", "qemu-i386": "8.2.2", "wasmtime": None}
    got = {"kernel": "k", "gcc": "1", "qemu-i386": "8.2.2", "wasmtime": "48.0.1"}
    up = {"kernel": "k", "gcc": "1", "qemu-i386": "10.2.1", "wasmtime": None}
    check(twatch.fp_of_toolchain(base) != twatch.fp_of_toolchain(got),
          "installing an absent runner moves it",
          "%s -> %s" % (twatch.fp_of_toolchain(base),
                        twatch.fp_of_toolchain(got)))
    check(twatch.fp_of_toolchain(base) != twatch.fp_of_toolchain(up),
          "and so does upgrading a present one",
          "%s -> %s" % (twatch.fp_of_toolchain(base),
                        twatch.fp_of_toolchain(up)))
    check(twatch.fp_of_toolchain(base) == twatch.fp_of_toolchain(dict(base)),
          "while an unchanged toolchain does not — it is not a nonce")

    print("5. an OLDER report is not a toolchain that measured nothing")
    check(twatch.toolchain_line({}) == "unrecorded (older harness)",
          "the empty case says WHY it is empty",
          twatch.toolchain_line({}))
    check(twatch.fp_of_toolchain({}) == "",
          "and its fingerprint is empty rather than a hash of nothing",
          "a hash of {} would be a stable 12 hex that reads as a real "
          "toolchain every reader could then 'match' against")

    print("6. it works on THIS box — the population is real, not synthetic")
    live = twatch.host_toolchain()
    check(live.get("kernel"),
          "the live reading names a kernel", live.get("kernel"))
    check(sum(1 for k, v in live.items() if v is not None) >= 2,
          "and at least two tools resolved",
          twatch.toolchain_line(live))

    print("7. TSTATE.md renders it, and a silent host is not a matching host")
    # The ticket's premise is "there is no field a READER can check", and a
    # reader triaging a cross-target red starts at the index, not at a report.
    # Rendered as its own block rather than as extra rows inside
    # cross_currency_block, because that block's devtest counts the `| ` rows it
    # emits -- a table appended there turned two rows into four and its guard
    # would have had to be loosened to fit its own subject.
    tb = "\n".join(twatch.toolchain_block(
        ["seven", "plexus", "borg"],
        {"seven": dict(mixed, fp="aaaabbbbcccc"),
         "plexus": dict(same, fp="ddddeeeeffff")}))
    check("aaaabbbbcccc" in tb and "ddddeeeeffff" in tb,
          "each host's fingerprint is printed, not just its versions",
          "a reader compares fp before comparing versions")
    check("_not published since this field existed_" in tb,
          "a host with NO stored toolchain says so in words",
          "borg has published no report since 2026-09-05; rendering it blank "
          "would read as agreement with the hosts above it, which is the "
          "reading this whole ticket exists to remove")
    check(tb.count("| borg") == 1 and "borg" not in tb.split("| borg")[1],
          "and it is one row, not an entry that duplicates or vanishes")
    check(twatch.toolchain_block([], {}) == [],
          "no hosts renders NOTHING, not an empty table with a promise in it")
    print("8. the two SILENCES are told apart — no baseline is not no change")
    # Measured 2026-09-05: seven.json and plexus.json both had NO `toolchain`
    # key, because the field landed the same day and neither host published
    # through it. So seven's first post-upgrade report -- the one the whole
    # ticket was written for -- had nothing to diff against and could not
    # announce the transition. "No callout" already had two candidate causes
    # (the render is broken; the watcher died); this was a silent third that
    # looks exactly like both, and it was the one that was true.
    import tempfile
    import types

    def _render(st):
        """A real write_report_md call, not a re-implementation of the branch.

        Asserting the CONDITION would restate the `if`; this renders the
        document a reader actually receives, which is the artefact the two
        silences are indistinguishable in."""
        clone = types.SimpleNamespace(path=tempfile.mkdtemp())
        rep = {"tier": "full", "verdict": "GREEN", "wall": 1, "jobs": {},
               "scale": 1.0,
               "toolchain": {"kernel": "k", "gcc": "1", "qemu-i386": "8.2.2"}}
        twatch.write_report_md(clone, "h", "0" * 40, "1" * 40, rep,
                               [], [], [], st)
        return sorted(pathlib.Path(clone.path).rglob("*.md"))[0].read_text()
    try:
        first = _render({})
        again = _render({"toolchain": {"kernel": "k", "gcc": "1",
                                       "qemu-i386": "8.2.2",
                                       "fp": twatch.fp_of_toolchain(
                                           {"kernel": "k", "gcc": "1",
                                            "qemu-i386": "8.2.2"})}})
        moved = _render({"toolchain": {"fp": "0123456789ab"}})
    except Exception as e:                                          # noqa: BLE001
        first = again = moved = "RAISED %s: %s" % (type(e).__name__, e)
    check("FIRST RECORDED" in first,
          "a host with no stored fingerprint says the baseline is NEW",
          "otherwise it is indistinguishable from a quiet unchanged run")
    check("CHANGED on this host" not in first,
          "and does not claim a change it cannot have observed")
    check("FIRST RECORDED" not in again and "CHANGED on this host" not in again,
          "an unchanged toolchain says nothing — silence means unchanged only "
          "once a baseline exists")
    check("CHANGED on this host" in moved and "FIRST RECORDED" not in moved,
          "and a real move still announces itself, exactly once")

    check(tb.startswith("## "),
          "the heading is top-level, so it cannot orphan",
          "cross_currency_block returns [] when no host has a DATED full tier; "
          "a `###` under a parent that did not render reads as part of "
          "whatever section came before it")

    print("\n  %d guard(s), %d FAIL" % (22, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
