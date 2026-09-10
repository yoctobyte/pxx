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

THREE RULES, and they are different defects
-------------------------------------------
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
import os
import re
import sys

# What counts as an assertion FOR THE VACUOUS RULE (the SILENT rule uses CMP).
# assert_no_leak.sh and assert_alloc_ceiling.sh belong here: they are assertions,
# 104 recipe lines invoke them, and `assert ; assert` discards the first one's
# status exactly as it does for `test` and expect_same.sh. Measured 2026-09-05:
# none of the 104 is currently chained that way, so this widening flags nothing
# today -- it is a latent hole being closed before it is occupied, not a fix for
# a live defect. Widening ASSERT cannot create SILENT false positives, because
# the SILENT rule does not consult it; these tools always print and exit nonzero,
# so they were never SILENT candidates in the first place.
ASSERT = re.compile(r'(?:\btest\s|\btools/expect_same\.sh\s|\btools/assert_no_leak\.sh\s|\btools/assert_alloc_ceiling\.sh\s)')
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
# The STALE-PIN rule.  A pin, and the source files a row names.  The extension
# list is what keeps `-Futest/incdiag` and `$(TESTTMP)/foo26` out: those are a
# directory and an output, and neither has a line count to compare against.
LINE_PIN = re.compile(r'pascal26:(\d+):')
NAMED_SRC = re.compile(r'(?<![\w/.-])((?:test|lib|examples)/[\w./-]+\.(?:pas|npy|c|h|inc|py|rs|zig))')
# A row that also asserts an `in:` line is saying IN THE ASSERTION that the
# diagnostic names a different file -- an include or a used unit -- so its
# pin indexes that file and not the one on the command line.  Excluded rather
# than guessed at: three such rows are live (the incdiag family), all correct.
NAMES_OTHER_FILE = re.compile(r"\^\s*in:|'\s*in:|\"\s*in:")
# ...and the rows that do NOT assert `in:` because they pipe through `head -1`
# say so in their comment block instead.  A MARKER RATHER THAN A WIDER
# POPULATION, and the choice is measured, not stylistic: the obvious
# alternative is to also count files under the row's `-Fu`/`-I` directories,
# which sounds strictly better and DESTROYS THE RULE.  test/ffi_headers/nolib.h
# is 13 lines, so under that widening the nine-line .npy pinned at
# `pascal26:10:` -- the defect this rule was built from -- stops being
# flagged.  A guard that cannot catch its own founding case is not a guard.
# Exactly one live row needs the marker today, so the burden is one comment.
PIN_ELSEWHERE = re.compile(r'PIN NAMES ANOTHER FILE')


def _line_count(path):
    """Lines as a COMPILER counts them, which is not `content.count(chr(10)) + 1`.

    That spelling is right only for a file whose last line has no terminator,
    and it is wrong by one for every ordinary file -- which is the common case.
    The first draft used it and the guard's own positive control caught it: the
    nine-line fixture measured 10, the pin was 10, `10 > 10` is False, and the
    rule reported the file clean while looking straight at the defect it was
    written from.  A guard that cannot fail prints PASS.
    """
    try:
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    if not data:
        return 0
    return data.count(b"\n") + (0 if data.endswith(b"\n") else 1)


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


def preceding_comment_block(lines, lineno):
    """The contiguous recipe-comment lines directly above physical `lineno`."""
    out, i = [], lineno - 2
    while i >= 0:
        ln = lines[i]
        if not ln.startswith("\t"):
            break
        if not ln[1:].lstrip("@").lstrip().startswith("#"):
            break
        out.append(ln)
        i -= 1
    return "\n".join(out)


def scan(text):
    silent, vacuous, stale = [], [], []
    lines = text.split("\n")
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
        pins = [int(m.group(1)) for m in LINE_PIN.finditer(body)]
        if (pins and not NAMES_OTHER_FILE.search(body)
                and not PIN_ELSEWHERE.search(preceding_comment_block(lines, lineno))):
            counts = [n for n in (_line_count(f) for f in
                                  set(NAMED_SRC.findall(body))) if n is not None]
            if counts:
                longest = max(counts)
                over = [n for n in pins if n > longest]
                if over:
                    stale.append((lineno, body.strip(), max(over), longest))
    return silent, vacuous, stale


def main(argv):
    path = argv[1] if len(argv) > 1 else "Makefile"
    with open(path) as fh:
        silent, vacuous, stale = scan(fh.read())
    for label, hits, why in (
        ("SILENT", silent,
         "prints nothing on mismatch -- use tools/expect_same.sh <label> <actual> <expected>"),
        ("VACUOUS", vacuous,
         "its exit status is discarded by the following `;` -- join with && or add || exit 1"),
    ):
        for lineno, body in hits:
            print(f"{path}:{lineno}: {label} assertion: {why}")
            print(f"    {body[:200]}")
    for lineno, body, pin, longest in stale:
        print(f"{path}:{lineno}: STALE-PIN assertion: pins pascal26:{pin}: but the "
              f"longest source file this row names is {longest} line(s) -- the pin "
              f"cannot be indexing it, so the row is asserting a line number "
              f"nothing produces from that file. Re-derive it by RUNNING the "
              f"recipe, not by copying the number the compiler prints today: if "
              f"the diagnostic is itself reporting the wrong line, copying it "
              f"makes the two wrong numbers agree and the row cannot fail for "
              f"the right reason. If the diagnostic legitimately names another "
              f"file -- a used unit, an include -- assert its `in:` line too, or "
              f"write PIN NAMES ANOTHER FILE in the comment block directly above "
              f"the row, and this rule steps aside")
        print(f"    {body[:200]}")
    n = len(silent) + len(vacuous) + len(stale)
    if n:
        print(f"silent-assertion-check: {len(silent)} silent, {len(vacuous)} vacuous, "
              f"{len(stale)} stale-pin")
        return 1
    print("silent-assertion-check: OK -- every Makefile assertion can fail and can say why")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
