---
track: N
prio: 30
type: bug
---

# NilPy: `\xHH` (and presumably `\0`-style) escapes in a BYTES literal are not decoded

`len(b"\x00\xff")` is 8 (the raw source characters), CPython says 2 — the
bytes-literal lexer keeps the backslash sequences as text instead of decoding
them. Found writing test_nilpy_bytes_repr (its `b"\x00\xff"` case is omitted
until this is fixed; the repr side is correct and CPython-matched). `\n`/`\t`
in bytes literals: verify while in there — b"abc\n" has len 4 (correct), so the
NAMED escapes appear to decode; it is the numeric \xHH family that does not.

Where: the .npy lexer's bytes-literal scanner (pylexer.inc).
Gate: len(b"\x00\xff") = 2 and print matches CPython; test-nilpy green.
