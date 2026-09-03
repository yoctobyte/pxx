#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Refuse a Makefile assertion that cannot say why it failed, or cannot fail.

    tools/silent_assertion_check.py [Makefile]     (exit 0 = clean)

WHY
---
`test` PRINTS NOTHING when it fails: it captures both operands, compares them,
discards both, and exits 1.  testmgr's `job_reason()` records the log TAIL --
deliberately, because a signature list goes stale silently while "what the job
printed last" is true for every failure shape.  So a silent assertion hands a
faithful tail-recorder whatever happened to precede it, which for a compile-then-
assert recipe is two compile summaries.  For a cross-target row those are the
SAME program built for two targets with different code sizes, and that reads as
a codegen divergence.  A Track T session read one that way, told a peer, and had
to retract it.

    A silent assertion does not merely fail to explain itself.  It makes
    everything downstream explain something ELSE, confidently.

`tools/expect_same.sh` fixes that and has been applied to ~3900 recipe lines.
THIS TOOL EXISTS SO THAT WORK CANNOT ROT.  A conversion with no guard is a
one-time cleanup; a guard makes it a property of the file.

TWO RULES, and they are different defects
-----------------------------------------
SILENT   an equality or NUMERIC comparison where an operand is a command
         substitution and nothing prints on mismatch -- a red job with a
         confidently wrong reason.
VACUOUS  an assertion immediately followed by `;` and ANOTHER assertion -- make
         checks only the LAST command's status, so the first one CANNOT FAIL.
         A green suite; the defect ships.  Narrower than "any `;` after an
         assertion" on purpose: `if ...; then assert; else echo skip; fi` is
         fine, because `fi` yields the taken branch's last status, and a rule
         that flagged it would be noise and would be switched off.

CONTINUATIONS ARE JOINED FIRST, and that is not a detail.  The first draft of
this scan read PHYSICAL lines and reported ten offenders; four of them carry
their `|| { echo ...; exit 1; }` on the NEXT continued line and were never
silent.  The scanner was answering a narrower question than the shell asks --
the same failure this whole ticket family is about, committed by its own guard.
"""
import re
import sys

ASSERT = re.compile(r'(?:\btest\s|\btools/expect_same\.sh\s)')
# An operand is a double-quoted string or a bare token; the comparison is `=`
# or any of test(1)'s NUMERIC operators. `-ge` was outside the first draft's
# population and four assertions on a `grep -c` count sat silent behind it --
# a scan reporting zero is indistinguishable from an absence of defects, so
# the population has to be the one the RULE is about ("nothing prints when
# this fails"), not the one the first example happened to use.
_OPERAND = r'(?:"(?:[^"\\]|\\.)*"|[^\s;&|()]+)'
CMP = re.compile(r'\btest\s+(' + _OPERAND + r')\s+(?:=|-eq|-ne|-ge|-gt|-le|-lt)\s+'
                 + r'(' + _OPERAND + r')')
FAIL_BRANCH = re.compile(r'\|\|\s*[\{(]')


def logical_recipe_lines(text):
    """Recipe lines with backslash continuations joined, keyed by first line no."""
    out, buf, start = [], None, None
    for i, ln in enumerate(text.split("\n"), 1):
        if buf is None:
            if not ln.startswith("\t"):
                continue
            buf, start = ln[1:], i
        else:
            buf += " " + ln.lstrip()
        if buf.rstrip().endswith("\\"):
            buf = buf.rstrip()[:-1]
            continue
        out.append((start, buf))
        buf = None
    if buf is not None:
        out.append((start, buf))
    return out


def next_separator(seg):
    """The first UNQUOTED `;`, `&&` or `||` in seg, as (kind, index)."""
    q = None
    i = 0
    while i < len(seg):
        c = seg[i]
        if q:
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == ";":
            return ";", i
        elif seg[i:i + 2] in ("&&", "||"):
            return seg[i:i + 2], i
        i += 1
    return None, len(seg)


def scan(text):
    silent, vacuous = [], []
    for lineno, body in logical_recipe_lines(text):
        stripped = body.lstrip().lstrip("@").lstrip()
        if stripped.startswith("#"):
            continue
        if "expect_same.sh" not in body:
            for m in CMP.finditer(body):
                a, b = m.group(1), m.group(2)
                if "$$(" not in a and "$$(" not in b:
                    continue          # both literal: the reason names wrong lines,
                                      # but it does not fabricate a finding
                if FAIL_BRANCH.search(body[m.end():]):
                    continue          # it explains itself
                silent.append((lineno, body.strip()))
                break
        for m in ASSERT.finditer(body):
            kind, off = next_separator(body[m.start():])
            if kind != ";":
                continue
            rest = body[m.start() + off + 1:].lstrip()
            if ASSERT.match(rest):
                vacuous.append((lineno, body.strip()))
                break
    return silent, vacuous


def main(argv):
    path = argv[1] if len(argv) > 1 else "Makefile"
    with open(path) as fh:
        silent, vacuous = scan(fh.read())
    for label, hits, why in (
        ("SILENT", silent,
         "prints nothing on mismatch -- use tools/expect_same.sh <label> <actual> <expected>"),
        ("VACUOUS", vacuous,
         "its exit status is discarded by the following `;` -- join with && or add || exit 1"),
    ):
        for lineno, body in hits:
            print(f"{path}:{lineno}: {label} assertion: {why}")
            print(f"    {body[:200]}")
    n = len(silent) + len(vacuous)
    if n:
        print(f"silent-assertion-check: {len(silent)} silent, {len(vacuous)} vacuous")
        return 1
    print("silent-assertion-check: OK -- every Makefile assertion can fail and can say why")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
