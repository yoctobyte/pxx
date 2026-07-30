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
| a bare `return` first, then `return "str"` | `str` | FIXED ✓ |
| a bare `return` first, then `return [1]` | `[1]` | FIXED ✓ |
| a bare `return` first, then `return 5` | `5` | FIXED ✓ |
| `xs = ["a","b"]` then **`return xs[0]`** | `a` | **TypeError: expected a number, got str** |
| `xs = [1,2]` then `return xs[0]` | `1` | `1` ✓ |
| `v = xs[0]` then `return v` | `a` | `a` ✓ |
| `d = {"k":"v"}` then `return d["k"]` | `v` | `v` ✓ |
| `return g()` / `return k.m()` (a call) | correct | correct ✓ |
| mixed `return 1` / `return "a"` in two branches | correct | correct ✓ |
| `xs = [1,2,3]` then `return xs[0:2]` (slice) | correct | correct ✓ |

Two distinct causes behind one symptom:

1. **A value-less `return` decides the type — FIXED.** The scanner already
   kept looking past `return None`; a bare `return` hit an `Exit` instead. In
   Python they are the same statement, so it now takes the same path. Covered by
   `test/test_nilpy_return_type_inference.npy`.

   Original description: A def with no value-returning
   `return` is deliberately `tyInteger` ("the harmless case", per pyparser) —
   but when a BARE `return` is merely the first of several, that integer wins
   over the real returns that follow. Only the later-int case survives, by
   coincidence. The first return should not count as value-typing when it
   carries no value.

2. **`return <list element>` always infers INT**, whatever the list holds.
   Measured across element types:

   | returned expression | CPython | pxx |
   | --- | --- | --- |
   | `xs = ["a","b"]` -> `return xs[0]` | `a` | **TypeError: expected a number, got str** |
   | `xs = [1.5]` -> `return xs[0]` | `1.5` | **`1`** (truncated) |
   | `xs = [True]` -> `return xs[0]` | `True` | **`1`** |
   | `xs = [[1]]` -> `return xs[0]` | `[1]` | **TypeError: ... got object** |
   | `g = [["a"]]` -> `return g[0][0]` | `a` | **TypeError** |
   | `xs = [1,2]` -> `return xs[0]` | `1` | `1` ✓ (coincidence) |
   | `d = {"k":"v"}` -> `return d["k"]` | `v` | `v` ✓ |
   | `v = xs[0]` then `return v` | correct | correct ✓ |

   So it is not "strings raise" — the subscript form falls to the tyInteger
   default for every element type, and only a list of ints comes out right by
   accident. A DICT lookup is typed correctly, which is the useful clue: the
   scanner has a path for one container form and not the other.

   Same root as the `chr` case above and as
   [[bug-nilpy-subscript-and-slice-of-a-variant-get-the-wrong-static-type]]:
   the inference reads a container element as a scalar instead of leaving it a
   variant.

   **The missing arm, located.** `PyInferExprType` (pyparser.inc ~2093) tests
   for `[` only at the START of the expression — a list LITERAL:

   ```pascal
   if ... ((Tokens[startIdx].Kind = tkLBrack) or (Tokens[startIdx].Kind = tkBegin)) then
   ```

   There is no arm for `<ident> [ ... ]`, i.e. a SUBSCRIPT, so the expression
   comes back `tyUnknown` and `PyInferDefRetType`'s `Result := tyInteger`
   default stands. That is why assigning to a temp first works — a bare
   `return <ident>` DOES have a chase path, back to the ident's last
   assignment.

   Suggested shape: give the scanner an `<ident>[...]` arm that answers
   `tyVariant` rather than falling through. A variant is what the value
   actually is at run time (the temp-variable form proves it round-trips
   correctly), and it costs nothing on the paths that already work. Check the
   DICT form while doing it — `d["k"]` is typed correctly today by some other
   route, and must not regress.

Every other chain checked infers correctly — float, str-from-int, list, bool
and dict accumulations all round-trip — so this is not general breakage; it is
these specific shapes.

## CLOSED — the missing arm, plus the chr-accumulator half

Added the suggested arm: `<ident>[...]` on a list/dict/unconstrained-variant
receiver now answers `tyVariant` and skips the whole bracket group, instead of
falling through to the token walk that widened on the INDEX/KEY token's own
type. Verified against every element kind in the table above (str/float/
bool/nested-list/dict) plus the double-subscript `g[0][0]` shape — all now
match CPython. The DICT form's pre-existing correct behaviour is unchanged
(it now goes through the same tyVariant arm as everything else, rather than
reaching the right answer by the token-walk accident described above).

Separately, the `acc = acc + chr(97)` shape at the top of this ticket needed a
second fix in `PyInferDefRetType`'s bare-`return <ident>` re-chase: it
re-scanned each prior assignment to the returned name from scratch with no
memory of the CHAIN's running type, so a self-referential accumulator's
leading `acc` on the RHS resolved to tyUnknown (this raw re-scan has no
PyLocals) and the assignment's inferred type came from `chr()` alone
(tyChar) — throwing away that `acc` already held a string built up by an
earlier assignment. Fixed by folding the chain's running type in via PyWiden
instead of re-deriving each assignment in isolation. `rot13`/`caesar`-shaped
functions now round-trip correctly end to end.

Tests: test/test_nilpy_bare_return_subscript_slice.npy (every row above,
CPython's own output), plus the pre-existing
test/test_nilpy_return_type_inference.npy (bare-return-first family) stays
green. Gate: make test-nilpy green, self-host fixedpoint, testmgr --tier
quick.

Ticket closed.

## Log
- 2026-07-31 — resolved, commit 238fc891a.
