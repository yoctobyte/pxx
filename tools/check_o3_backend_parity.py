#!/usr/bin/env python3
"""Freeze the per-backend -O3 gate delta, so a one-armed optimisation says so.

CLAUDE.md scopes per-backend optimisation effort to **x86-64 + aarch64** and to
nothing else. That is a stated scope, and for most of the -O3 campaign nothing
checked whether it was being met. When someone finally counted (2026-08-30,
`feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen`),
the two in-scope backends were **22 : 6** -- one arm of a two-arm chain extended
many times and the other twice. "aarch64 is in scope" and "aarch64 got 4 of 15"
are consistent statements, which is exactly why prose could not catch it.

This script is that count made recurring and enforcing. It does not forbid a
one-armed slice -- most of them legitimately are one-armed, because an x86-64
encoding often has no one-to-one aarch64 spelling. It forbids a one-armed slice
that nobody NOTICED was one-armed: the numbers below are the delta of record, so
widening it is an edit to this file, in the same commit, visible in the diff.

WHY IT COUNTS TWO SPELLINGS, which is the second half of the story. The original
count grepped `OptLevel >= 3`. About a fifth of the campaign's gates are written
`if OptLevel < 3 then Exit;` -- an early return at the top of a predicate, the
shape W1 slices 7, 8 and 10 all use -- and that grep cannot see them. It surfaced
only because slice 10 added a gate and the raw count did not move: 17 before,
17 after. **"Count arms by parsing, not by reading" buys nothing when the parse
matches one of the two ways the arm is written**, so the pattern here catches
every way of spelling "this arm is -O3 only" -- `>= 3`, `> 2`, `< 3`, `<= 2`,
`= 3`, with or without spaces.

Then the hand-corrected replacement, **23 : 7**, was ALSO wrong -- by one on each
row, because a raw grep counts prose. Both files carry exactly one continuation
line INSIDE a `{ }` block that mentions a gate in passing, and neither is caught
by "does this line start with a comment marker?". The counts below are 22 : 6,
from properly comment-stripped source, and they are the first ones that did not
need a footnote. Three tries, and every wrong answer was the measuring
instrument rather than the thing measured; the census printed by `--census` is
what makes the fourth checkable by a reader instead of trusted.

A GATE CAN ONLY FAIL ON WHAT IT WAS TOLD TO LOOK AT, so the backend list is
DERIVED from a glob rather than written down. A seventh backend file added later
inherits the check (expected 0) instead of escaping it.

Usage:
  tools/check_o3_backend_parity.py            # the assertion; exit 1 on drift
  tools/check_o3_backend_parity.py --census   # every matching line, with file
                                              # and line number, for review
"""

import glob
import os
import re
import sys

# Every way this codebase spells "this arm exists only at -O3". Anchored on the
# identifier so `CsDepth < 3` and friends cannot match.
GATE = re.compile(r"\bOptLevel\s*(>=\s*3|>\s*2|<\s*3|<=\s*2|=\s*3)\b")

# Prose ABOUT a gate is not a gate. The aarch64 file's original count carried
# the footnote "4 (a 5th match is prose)", and a per-line "does it start with a
# comment marker?" test does NOT remove it: the prose match sits on a
# CONTINUATION line inside a `{ ... }` block, which starts with an ordinary
# word. So the source is comment-stripped for real -- `{ }`, `(* *)`, `//`, and
# string literals -- before anything is counted. That footnote is the whole
# reason: a number that needs an asterisk is a number nobody can re-derive.
def strip_comments(src):
    """Blank out Pascal comments and string literals, PRESERVING line count."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "{":
            j = src.find("}", i + 1)
            j = n if j < 0 else j + 1
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j]))
            i = j
        elif c == "(" and src.startswith("(*", i):
            j = src.find("*)", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j]))
            i = j
        elif c == "/" and src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c == "'":
            j = i + 1
            while j < n and src[j] != "'" and src[j] != "\n":
                j += 1
            j = min(j + 1, n)
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)

# The delta of record. Raising one of these is a deliberate act: it is the line
# in the diff that says "this slice is one-armed and I know it".
#
# in scope per CLAUDE.md ("per-backend effort = x86-64 + aarch64 only"):
#   ir_codegen.inc           the x86-64 emitter
#   ir_codegen_aarch64.inc   the aarch64 emitter
# out of scope, and the zeros are the scope statement made executable:
#   386 / arm32 / riscv32 / xtensa
EXPECTED = {
    "ir_codegen.inc": 23,
    "ir_codegen_aarch64.inc": 11,
    "ir_codegen386.inc": 0,
    "ir_codegen_arm32.inc": 0,
    "ir_codegen_riscv32.inc": 0,
    "ir_codegen_xtensa.inc": 0,
}

TICKET = "feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen"


def scan(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    code = strip_comments(src)
    raw = src.splitlines()
    hits = []
    for n, line in enumerate(code.splitlines(), 1):
        if GATE.search(line):
            hits.append((n, raw[n - 1].rstrip()))
    return hits


def main():
    census = "--census" in sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, "compiler", "ir_codegen*.inc")))
    if not files:
        print("check-o3-parity: no compiler/ir_codegen*.inc found — wrong cwd?")
        return 1

    actual, problems = {}, []
    for path in files:
        name = os.path.basename(path)
        hits = scan(path)
        actual[name] = len(hits)
        if census:
            print(f"--- {name}: {len(hits)}")
            for n, line in hits:
                print(f"  {name}:{n}: {line.strip()}")

    for name, count in sorted(actual.items()):
        if name not in EXPECTED:
            problems.append(
                f"{name}: {count} -O3 gate site(s), and this file is not in the "
                f"frozen table. A new backend emitter inherits the scope rule: "
                f"add it to EXPECTED in {os.path.relpath(__file__, root)} with "
                f"the count it should have (0 unless CLAUDE.md's per-backend "
                f"scope has changed)."
            )
        elif count != EXPECTED[name]:
            way = "GREW" if count > EXPECTED[name] else "SHRANK"
            note = ""
            if name == "ir_codegen_aarch64.inc" and count > EXPECTED[name]:
                note = "  <- the gap CLOSING; this is the good direction"
            problems.append(
                f"{name}: {EXPECTED[name]} -O3 gate site(s) expected, {count} "
                f"found ({way}).{note}"
            )
    for name in sorted(EXPECTED):
        if name not in actual:
            problems.append(f"{name}: frozen at {EXPECTED[name]} but the file is gone.")

    if not problems:
        pairs = ", ".join(f"{n.replace('ir_codegen', '').strip('_.inc') or 'x86-64'}={c}"
                          for n, c in sorted(actual.items()))
        print(f"check-o3-parity: OK — {pairs}")
        return 0

    print("check-o3-parity: the per-backend -O3 gate delta MOVED.\n")
    for p in problems:
        print(f"  {p}")
    print(
        "\nThis is not a failure, it is a question. Which question depends on\n"
        "which way it moved:\n"
        "\n"
        "  aarch64 GREW  -- the gap is closing. Nothing to argue: bump the\n"
        "     number in EXPECTED in this file, in the same commit, and name the\n"
        "     ported slice in the commit message.\n"
        "  x86-64 GREW   -- a new one-armed slice. Either port it (and both\n"
        "     numbers move), or, if it is legitimately x86-64-only because the\n"
        "     encoding has no one-to-one aarch64 spelling, bump the number and\n"
        "     SAY SO in the commit message.\n"
        "  either SHRANK -- a pass was removed or a gate re-spelled. Confirm\n"
        "     that was intended before lowering the number.\n"
        "\n"
        "What is NOT an answer is landing it and letting the count drift, which\n"
        "is how the ratio drifted this far with a stated scope saying otherwise.\n"
        f"Context and the standing count: devdocs/progress/**/{TICKET}.md\n"
        "Review the matches yourself with: tools/check_o3_backend_parity.py --census"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
