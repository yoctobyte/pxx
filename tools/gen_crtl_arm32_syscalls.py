#!/usr/bin/env python3
"""Emit crtl's arm32 arm of <sys/syscall.h> from the measured syscall map.

GENERATED, NOT TRANSCRIBED, and the distinction is the whole point. The other
four arms of that header come from this box's kernel headers by script; arm32
has no header on this box, and for a long time the honest answer was to ship
nothing, because a guessed number does not fail -- it runs a DIFFERENT syscall.
devdocs/dev/syscall-maps/arm32.txt changed that: it is measured under
qemu-arm -strace by tools/qemu_syscall_map.sh, which is the same method
platform_backend.pas's xtensa block documents for its own numbers.

WHAT THIS IS AN ORACLE ABOUT. QEMU, not a kernel on real hardware. Every arm32
test in this tree runs under qemu-arm, so the numbers are right for the entire
population that exercises them; a first run on hardware is where they would be
falsified. That sentence is stamped into the generated block, because a number
copied out from under it stops carrying it.

CONTROLS, asserted here and not only in the map's generator -- a consumer that
trusts its input has no guard at all:

  * three CONSECUTIVE, DISTINCT names (3 read, 4 write, 5 open). read+write
    alone cannot catch a constant shift within a family: adjacent numbers in
    one family answer alike, which is how a behavioural control failed to fail
    during this ticket (readv 145 / writev 146 both EBADF).
  * the three rows this ticket audited BEHAVIOURALLY and found wrong in the
    first map: 2 fork, 29 pause, 248 exit_group. They are the regression test
    for the extractor bugs that produced them.
  * NO DUPLICATE NAMES. A property of the OUTPUT, which is what caught those
    two misnamings when five input-side controls had all passed.
  * a floor on the row count, so a truncated map cannot quietly emit a short
    header.

Refuses to write anything if any control fails. A generator whose guard cannot
fail produces a header nobody can check.

THE TABLE IS PARTIAL AND THE HEADER MUST NOT IMPLY OTHERWISE. The map holds
what the sweep established, not the kernel's full table -- ?unnamed rows are
skipped (90/old_mmap: assigned, returns, and qemu prints no name), and a number
the sweep never saw is simply absent. An absent SYS_* stays a COMPILE ERROR,
which is the header's existing contract and the correct outcome: a program that
names one gets told, rather than getting a number somebody inferred.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAP = ROOT / "devdocs/dev/syscall-maps/arm32.txt"
HDR = ROOT / "lib/crtl/include/sys/syscall.h"

BEGIN = "#elif defined(__arm__)"
END_MARKER = "#else\n/* xtensa: see the note at the top of this file."

TRIPLE = [(3, "read"), (4, "write"), (5, "open")]
AUDITED = [(2, "fork"), (29, "pause"), (248, "exit_group")]
MIN_ROWS = 300


def read_map():
    rows = []
    for line in MAP.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        f = line.split()
        if not re.fullmatch(r"[0-9]+", f[0]):
            continue
        num, name = int(f[0]), f[1]
        if name.startswith("?"):
            continue          # ?unnamed / any future marker: no name to emit
        rows.append((num, name))
    return rows


def check(rows):
    by_num = dict(rows)
    names = [n for _, n in rows]
    problems = []
    if len(rows) < MIN_ROWS:
        problems.append(f"only {len(rows)} rows, floor is {MIN_ROWS}")
    for num, want in TRIPLE + AUDITED:
        got = by_num.get(num)
        if got != want:
            problems.append(f"control row {num}: expected {want}, map says {got!r}")
    if len({n for _, n in TRIPLE}) != 3:
        problems.append("the consecutive triple is not distinct")
    dups = {n for n in names if names.count(n) > 1}
    if dups:
        problems.append("duplicate name(s): " + ", ".join(sorted(dups)))
    return problems


def block(rows):
    stamp = []
    for line in MAP.read_text().splitlines():
        if line.startswith("# range:") or line.startswith("# compiler:"):
            stamp.append("   " + line[2:])
    out = [BEGIN,
           "/* arm32 EABI. NOT from a kernel header -- there is none on this box for this",
           "   target -- but MEASURED, by tools/qemu_syscall_map.sh, and emitted here by",
           "   tools/gen_crtl_arm32_syscalls.py from devdocs/dev/syscall-maps/arm32.txt.",
           "   Do not hand-edit: regenerate.",
           "",
           "   IT IS AN ORACLE ABOUT QEMU, not about a kernel on real hardware. Every",
           "   arm32 test in this tree runs under qemu-arm, so these are right for the",
           "   whole population that exercises them; a first run on hardware is where",
           "   they would be falsified. Carry that sentence with any number taken out",
           "   of here -- 'measured' on its own overstates it.",
           "",
           "   THE TABLE IS PARTIAL, DELIBERATELY. It holds what the sweep established.",
           "   A number it never saw is absent, and naming its SYS_* is still a compile",
           "   error -- which is the right answer, and the same one this header gave for",
           "   arm32 before it had any table at all.",
           ""] + stamp + [" */"]
    for num, name in rows:
        out.append("# define __NR_%-28s %d" % (name, num))
    out.append("")
    for _, name in rows:
        out.append("# define SYS_%-29s __NR_%s" % (name, name))
    return "\n".join(out) + "\n"


def main():
    rows = sorted(read_map())
    problems = check(rows)
    if problems:
        print("gen_crtl_arm32_syscalls: REFUSING to write:", file=sys.stderr)
        for p in problems:
            print("  " + p, file=sys.stderr)
        return 1

    text = HDR.read_text()
    old_else = ("#else\n/* arm32, xtensa: see the note at the top of this file. "
                "Naming any SYS_* here\n   is a compile error, which is the point. */\n")
    new_else = ("#else\n/* xtensa: see the note at the top of this file. Naming any SYS_* here\n"
                "   is a compile error, which is the point. */\n")

    if BEGIN in text:
        start = text.index(BEGIN)
        end = text.index("#else\n", start)
        text = text[:start] + block(rows) + text[end:]
    elif old_else in text:
        text = text.replace(old_else, block(rows) + new_else, 1)
    else:
        print("gen_crtl_arm32_syscalls: could not find the insertion point", file=sys.stderr)
        return 1

    HDR.write_text(text)
    print("gen_crtl_arm32_syscalls: wrote %d arm32 numbers (controls pass)" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
