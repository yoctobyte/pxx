---
track: N
prio: 75
type: bug
---

# An unannotated def's inferred return type is wrong for several common expression shapes

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

## MORE SHAPES, measured after the first write-up

An unannotated def's return type comes from its FIRST `return <expr>`. Three
more shapes get it wrong, all silently:

| shape | CPython | pxx |
| --- | --- | --- |
| a bare `return` first, then `return "str"` | `str` | **`5302411`** |
| a bare `return` first, then `return [1]` | `[1]` | **`123731992`** |
| a bare `return` first, then `return 5` | `5` | `5` ✓ |
| `xs = ["a","b"]` then **`return xs[0]`** | `a` | **TypeError: expected a number, got str** |
| `xs = [1,2]` then `return xs[0]` | `1` | `1` ✓ |
| `v = xs[0]` then `return v` | `a` | `a` ✓ |
| `d = {"k":"v"}` then `return d["k"]` | `v` | `v` ✓ |
| `return g()` / `return k.m()` (a call) | correct | correct ✓ |
| mixed `return 1` / `return "a"` in two branches | correct | correct ✓ |
| `xs = [1,2,3]` then `return xs[0:2]` (slice) | correct | correct ✓ |

Two distinct causes behind one symptom:

1. **A value-less `return` decides the type.** A def with no value-returning
   `return` is deliberately `tyInteger` ("the harmless case", per pyparser) —
   but when a BARE `return` is merely the first of several, that integer wins
   over the real returns that follow. Only the later-int case survives, by
   coincidence. The first return should not count as value-typing when it
   carries no value.

2. **`return <list element>` is typed from the wrong thing.** Returning
   `xs[0]` where the list holds strings raises; where it holds ints it is
   fine; assigning to a temp first is fine. Same shape as the `chr` case above
   and as [[bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type]]:
   the inference reads a container element as a scalar of the wrong kind
   instead of leaving it a variant.

Every other chain checked infers correctly — float, str-from-int, list, bool
and dict accumulations all round-trip — so this is not general breakage; it is
these specific shapes.
