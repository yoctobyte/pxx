---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`_κ = 5` is legal Python 3 and the NilPy lexer rejects it with `unexpected character`. Non-ASCII in a STRING literal already works, so this is the identifier path only. Two tinycss2 files (color4.py, color5.py) use Greek letters as names for colour-space constants."
---

# A Unicode identifier is rejected by the lexer

- **Type:** bug (lexer) — **Track N**. Small and self-contained.
- **Found:** 2026-08-17 by frank3, from the corrected corpus ladder scan
  (`tools/nilpy_ladder.py`), where it is the `unexpected character` row.
- **Measured against:** `pinned` **v346**.

## Repro

```python
_κ = 5
print(_κ + 1)
```

```
pxx:     pascal26:1: error: unexpected character: <?>
CPython: 6
```

## Boundary

Non-ASCII in a **string literal** already works:

```python
k = "κ appears in a string"
print(len(k) > 0)       # True in both
```

So the UTF-8 source path is fine and this is the **identifier** path only.

## Where it bites

`tinycss2/color4.py` and `color5.py` name their CIE Lab constants with the
conventional Greek letters:

```python
_κ = 24389 / 27
f0 = x ** (1 / 3) if x > _ε else (_κ * x + 16) / 116
```

That is idiomatic for the domain — the spec itself writes κ and ε — so
"just rename them" is not open to us: this is unmodified third-party source, and
the whole point of the corpus ladder is compiling it as shipped.

## Why the priority is low anyway

Two files, and both sit behind `undefined variable (CodecInfo)` in the same
package, so nothing is unblocked by fixing this alone. It is filed because it is
a genuine upward-compatibility break — Python 3 has allowed Unicode identifiers
since PEP 3131 and this is working CPython code — and because it is cheap: the
lexer already accepts these bytes inside a literal.

## Gate

The repro prints `6`. The `unexpected character` row leaves the ladder table.
