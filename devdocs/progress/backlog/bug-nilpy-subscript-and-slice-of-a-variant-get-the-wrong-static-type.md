---
track: N
prio: 75
type: bug
---

# `return s[0]` gives back the character CODE — a subscript return infers an int type

```python
def f():
    s = "ab"
    return s[0]
print(f())        # CPython: a     pxx: 97
```

`97` is `ord("a")`. The function's inferred return type is integer, so the
character is returned as its code.

With an unannotated PARAMETER the same shape raises instead:

```python
def f(s):
    return s[0]
print(f("ab"))    # CPython: a     pxx: TypeError: expected a number, got str
```

— the value is a str-tagged variant, the integer return coercion runs, and
`pyvar_to_int` rejects it. Same cause, different symptom depending on whether
the receiver is statically a string or a variant.

## Boundary — only the DIRECT return

| shape | pxx |
| --- | --- |
| `return s[0]` (local str) | **`97`** |
| `return s[0]` (unannotated param) | **TypeError** |
| `c = s[0]` then `return c` | `a` ✓ |
| `def f(s) -> str: return s[0]` | `a` ✓ |
| `return s[0] == "a"` | correct ✓ |
| `return s[0] + "!"` | correct ✓ |
| `print(s[0])` inside the body | correct ✓ |

So assigning to a local first, annotating, or using the value in an expression
all work. It is specifically a bare `return <subscript>` driving the inference.

## Cause

An unannotated def's return type is inferred from its first `return <expr>`
(`pyparser.inc` — "The return type of a def with NO `-> ret`, inferred from the
FIRST `return <expr>`"). A string subscript yields `tyChar`, and pxx spells a
Char as an ordinal, so the inference lands on an integer type rather than on
str. The `c = s[0]; return c` path works because the local's own typing widens
it to a string kind first.

This is the SHAPE-BLINDSPOT family again — `tyChar` is Python's `str` of
length 1, and every place that treats it as an ordinal instead is a divergence.
Related: [[bug-nilpy-char-vs-string-literal-ordering-compares-an-address]].

## Not a regression

Reproduced on the stable compiler from 2026-07-27.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` of the table above
against CPython's own output — including the working rows, so a fix that
re-types Char everywhere does not break them.

## The SLICE half — same root, worse symptoms

Slicing a variant is typed as a LIST, so a string slice comes back empty:

```python
def f(s):
    return s[0:2]
print(f("abcd"))      # CPython: ab     pxx: []

def common(a, b):
    i = 0
    while i < len(a) and i < len(b) and a[i] == b[i]:
        i = i + 1
    r = a[0:i]
    return r
print(common("prefix_one", "prefix_two"))   # CPython: prefix_   pxx: SIGSEGV
```

| shape | pxx |
| --- | --- |
| `return s[0:2]` (unannotated param) | `[]` |
| `r = s[0:2]` then `return r` | `[]` — the LOCAL is mistyped too |
| `def f(s) -> str: return s[0:2]` | correct ✓ |
| `print(s[0:2])` inside the body | correct ✓ (print takes a variant) |
| `s = "abcd"; s[0:2]` at top level | correct ✓ |
| the common-prefix function above | **SIGSEGV** |

The IR confirms it is not the runtime: `pyvar_slice` IS called and does handle a
string tag correctly. The result is then coerced by the CALLER, because the
expression's static type says list — so the string variant gets unboxed as an
object.

## Unified fix

Both halves are one decision: **what static type does `v[...]` get when `v` is a
variant?** Today the subscript answers `tyChar` (an ordinal) and the slice
answers list, and both are guesses that the runtime can already make correctly
from the tag.

Typing both as `tyVariant` and letting the tag decide at run time removes the
guess entirely — `pyvar_getitem` and `pyvar_slice` both already dispatch on the
tag and both already return a Variant. The annotated and `print()` rows work
today precisely because they do not force a scalar type onto the result.

Watch the paths that currently depend on the char typing — `ord(s[i])`,
`s[i] == "a"` and `chr()` round-trips all work now and must keep working; they
are covered by `test/test_nilpy_variant_str_index.npy`.
