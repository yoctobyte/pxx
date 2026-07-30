---
track: N
prio: 70
type: bug
---

# `acc = acc + chr(n)` inside a function yields an EMPTY string

```python
def f():
    acc = ""
    acc = acc + chr(97)
    return acc
print("[" + f() + "]")     # CPython: [a]     pxx: [[]]  (empty)
```

## Boundary

| shape | pxx |
| --- | --- |
| the program above | **empty** |
| the same three lines at TOP LEVEL | correct ✓ |
| `acc = acc + s[0]` — a char from an INDEX, not from chr | correct ✓ |
| `acc = chr(97)` (assign, no concat) | correct ✓ |
| `return chr(97)` directly | correct ✓ |
| `print(chr(ord(c)))` — no accumulator | correct ✓ |

So: string `+` a `chr()` result, inside a function. A char from a subscript
concatenates fine, so it is not "char concat" in general — it is specifically
the value `chr()` produces.

## Why it matters

It is what blocks every character-transforming loop, which is the natural way to
write one:

```python
def rot13(s):
    acc = ""
    for c in s:
        o = ord(c)
        if o >= 97 and o <= 122:
            o = ((o - 97 + 13) % 26) + 97
        acc = acc + chr(o)
    return acc
```

caesar and rot13 both return garbage or raise
`TypeError: expected a str or a list, got str` because of this line.

## What the IR shows

The failing and working forms lower to the SAME shape — only the callee kind
differs:

```
acc + chr(97)     (empty)          acc + s[0]        (correct)
  load_sym acc      tk=23            load_sym acc      tk=23
  const_int 97      tk=1             call 446 pystr_at tk=3     <- a real proc
  call -48          tk=3   <- the    binop  ... tkPlus tk=23
  binop ... tkPlus  tk=23     Chr    store_sym acc     tk=23
  store_sym acc     tk=23     INTRINSIC (negative proc index)
```

Both produce a `tk=3` (tyChar) value feeding a `tk=23` (tyAnsiString) `+`. So
the concat lowering is identical and the difference is that one operand comes
from the `-tkChr` INTRINSIC rather than from a call. Whatever the string-concat
codegen does with a char operand, it works for a value returned by a proc and
not for one produced inline by the intrinsic — and only inside a function,
since the same expression at top level is correct.

That is where to look: the tkPlus/string-concat path's handling of a tyChar
operand whose producer is an intrinsic, in a frame context.

## Not a regression

Reproduced identically on the 2026-07-27 stable, on pinned v231, and on current
HEAD.

## Family

This is the fifth bug traced to pxx having a `tyChar` where Python has only
`str`:

- [[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]] (fixed)
- [[bug-nilpy-chr-of-a-variant-reads-the-slot-not-the-value]] (fixed)
- [[bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type]]
- [[bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage]]
- this one

Worth considering the shared fix those tickets point at: do not produce
`tyChar` on the NilPy path at all — a one-character value is a `str` in Python,
and every place the ordinal leaks is a divergence. That would subsume several of
these rather than patching each concat/compare/slot site.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output and a rot13 round trip
(`rot13(rot13(s)) == s`) as the end-to-end case.
