---
track: N
prio: 60
type: bug
---

# `except OSError: pass` on one line is a parse error

Found 2026-10-19 in sysdash's backend.py: `expected 'newline' before 'pass'`.
One-line `if`/`while` bodies worked, and so did one-line `def`/`class` bodies.

**Cause:** the try parser reads every clause as `: NEWLINE INDENT`, with no
inline branch, and so does the `except ... as e` binder scan.

**Fix:** the lexer already turned a one-line `def`/`class` body into
NEWLINE INDENT ... DEDENT. That now also applies to lines that open with `try`,
`except` or `finally` (compiler/pylexer.inc). One-line `else:` after a try is
still not covered.

**Test:** test/test_nilpy_one_line_except_body.npy.
