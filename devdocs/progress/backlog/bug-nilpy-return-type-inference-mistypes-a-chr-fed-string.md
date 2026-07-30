---
track: N
prio: 70
type: bug
---

# A def returning a string that was built with `chr()` infers the wrong return type

```python
def f():
    acc = "x"
    acc = acc + chr(97)
    return acc
print("[" + f() + "]")     # CPython: [xa]     pxx: [8]
```

The value is built correctly — printing it INSIDE the function is right. Only
what comes back out is wrong.

## Boundary — it is the RETURN, not the concat

| shape | pxx |
| --- | --- |
| `acc = acc + chr(97)` then **`return acc`** | **`8`** (garbage) |
| the same, but `print(acc)` INSIDE the function | correct ✓ |
| the same at TOP LEVEL (no function) | correct ✓ |
| `def f() -> str:` — annotated | correct ✓ |
| `c = chr(97)` first, then `acc = acc + c`, return | correct ✓ |
| `acc = acc + "y"` (no chr anywhere), return | correct ✓ |
| an earlier `return acc` BEFORE the chr line | correct ✓ |
| `acc + str(chr(97))` | correct ✓ |
| `"" + chr(97)` / `"x" + chr(97)` (literal left operand) | correct ✓ |

My first framing of this ticket — "string + chr yields empty, inside a
function" — was wrong on both counts: the concat is fine, and the function
boundary only matters because that is where a return type is inferred.

The last row is the tell. An unannotated def's return type comes from its FIRST
`return <expr>`; putting a `return acc` before the `chr()` line fixes it, and so
does routing the chr result through a temp or through `str()`. So the inference
walks the assignment chain feeding the returned name, meets the `tyChar` that
`chr()` produces, and types the result as a char rather than a str — the
returned string is then truncated to one byte-ish value (`8`).

## Same family

This is the subscript case of
[[bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type]] seen
from the other end: there `return s[0]` infers an INT return type and hands back
`97`; here a chr-fed string infers a char one. Both are the inference treating
pxx's `tyChar` as a scalar when Python only has `str`.

Running total of bugs traced to that one design mismatch: two fixed
([[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]],
[[bug-nilpy-chr-of-a-variant-reads-the-slot-not-the-value]]) and three open
(this, the subscript/slice one, and
[[bug-nilpy-for-variable-reused-after-a-non-string-binding-iterates-garbage]]).
The shared fix those keep pointing at — do not produce `tyChar` on the NilPy
path at all — would subsume all of them.

## Why it matters

It is what blocks every character-transforming helper, which is the natural way
to write one:

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

caesar and rot13 both come back wrong because of the `return`.

## Not a regression

Reproduced identically on the 2026-07-27 stable, on pinned v231, and on current
HEAD.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output and a rot13 round trip (`rot13(rot13(s)) == s`) as
the end-to-end case. Keep the working rows — several of them are the workarounds
people will have written, and they must not break.
