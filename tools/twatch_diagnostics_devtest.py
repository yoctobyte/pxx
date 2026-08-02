#!/usr/bin/env python3
"""Devtest for the report/stub diagnostic hoist.

A raw log TAIL is the wrong thing to read when a compiler fails: FPC keeps
emitting warnings after the error that stopped it, so the last 4000 characters
of a seed-build failure are `Comment level 2 found` and the one line that
matters is nowhere in the report. On 2026-08-02 that happened three times in
one day — three separate FPC seed drifts — and each cost a full local
reproduction to recover a fact the log already contained.

The hoist is additive: the tail is still printed underneath, so a failure whose
signature is not recognised reads exactly as it did before.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402

fails = []


def check(name, cond, got=""):
    print(("  ok   " if cond else "  FAIL ") + name +
          (("  got: %r" % (got,)) if not cond else ""))
    if not cond:
        fails.append(name)


# the real shape: one Error, then thousands of warnings after it
FPC = ('parser.inc(14378,26) Error: Identifier not found "PyWiden"\n'
       + "rparser.inc(2147,15) Warning: Comment level 2 found\n" * 3000)

CASES = [
    ("FPC error buried above the tail", FPC,
     'parser.inc(14378,26) Error: Identifier not found "PyWiden"'),
    ("ETXTBSY exec race",
     "ok: /tmp/x/pascal26-next  [code=6020619B]\n"
     "sh: 99: /tmp/x/pascal26-next: Text file busy\n",
     "sh: 99: /tmp/x/pascal26-next: Text file busy"),
    ("fixedpoint mismatch",
     "ok: a\nok: b\n/tmp/a /tmp/b differ: byte 4096, line 1\n",
     "/tmp/a /tmp/b differ: byte 4096, line 1"),
    ("pxx compiler error",
     "pascal26:135867: error: global fixup overflow\n",
     "pascal26:135867: error: global fixup overflow"),
    ("segfault", "OPT DIFF -O3: test/x.c (rc 0 vs 0)\nSegmentation fault (core dumped)\n",
     "Segmentation fault (core dumped)"),
    ("linker failure", "/usr/bin/ld: undefined reference to `foo'\n",
     "/usr/bin/ld: undefined reference to `foo'"),
]


def main():
    for name, body, want in CASES:
        got = twatch.diagnostic_lines(body)
        check(name, got == want, got)

    check("the buried error really is outside the tail window",
          "Error:" not in FPC[-4000:])

    # no false positives: a clean log, and prose that merely says "error"
    check("a passing log hoists nothing",
          twatch.diagnostic_lines("ok: /tmp/x  [code=1B]\ntotal ok 27 / 27\n") == "")
    check("prose mentioning error handling is not hoisted",
          twatch.diagnostic_lines(
              "note: this test checks error handling\n"
              "Warning: Comment level 2 found\n") == "")
    check("empty and None are safe",
          twatch.diagnostic_lines("") == "" and twatch.diagnostic_lines(None) == "")

    # bounded, and deduplicated — a loop that fails 5000 times must not paste
    # 5000 identical lines into a ticket
    many = "".join("t.c:%d: error: boom\n" % i for i in range(500))
    out = twatch.diagnostic_lines(many)
    check("bounded to DIAG_MAX lines",
          len(out.splitlines()) <= twatch.DIAG_MAX, len(out.splitlines()))
    dup = "x.c:1: error: same\n" * 50
    check("duplicates collapse", twatch.diagnostic_lines(dup) == "x.c:1: error: same")

    print()
    print("FAILED: " + ", ".join(fails) if fails else "all diagnostic-hoist cases pass")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
