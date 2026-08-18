---
track: N
prio: 65
type: bug
blocked-by: []
summary: "`return (a, b)[i]` inside a function or method segfaults at runtime, no diagnostic. Both tuple and list literals; constant or variable index; constant or variable contents — all crash. The SAME expression at module level works, binding the literal to a local first works, and subscripting a string literal works. Found writing lib/rtl/mimic_urllib_parse.py, where a ParseResult's __getitem__ is exactly this shape."
---

# Subscripting a container literal inside a function segfaults

- **Type:** bug — **Track N** (Nil-Python frontend / lowering).
- **Found:** 2026-08-18 by frank3-fc, writing `ParseResult.__getitem__` for
  [[feature-b-mimic-six-moves-needs-http-client-and-urllib]].
- **Measured against:** `pinned` **v351** (`e4ca45a1819c`, pin `a6d6dfb84`).
- CPython accepts and runs every line below.

## Repro

```python
def f():
    return (1, 2)[0]

print(f())      # Segmentation fault -- CPython prints 1
```

Compiles clean. No warning, no note.

## The boundary — crossed, not walked

| shape | result |
| --- | --- |
| **function: `(1, 2)[0]`** — constants, constant index | **SEGFAULT** |
| **function: `(a, b)[i]`** — locals, variable index | **SEGFAULT** |
| **function: `[a, "y"][0]`** — a LIST literal | **SEGFAULT** |
| **method: `(self.a, "y")[0]`** | **SEGFAULT** |
| function: `t = (a, "y")` then `t[0]` | ✅ |
| function: `"xy"[0]` — a STRING literal | ✅ |
| module level: `(1, 2)[0]` | ✅ |
| module level: `(a, "y")[i]` | ✅ |

So neither the contents nor the index kind matters, and it is not tuples
specifically — it is **subscripting a container literal in a function body**.
Binding it to a local first is correct, and the same expression at module level
is correct.

The axes were crossed rather than walked, after
`devdocs/dev/debugging-playbook.md`: contents (constant / variable), index
(constant / variable), container (tuple / list / str), and site (module /
function / method). Only the last one, plus literal-vs-bound, predicts the
crash.

Reading, not a measurement: a literal in a function body appears to be built
somewhere that does not survive being subscripted in place — a temporary whose
lifetime ends before the index, or one that is never materialised at all.

## Why it matters

`(x, y)[i]` is how Python spells a small lookup table, and the idiom is
everywhere: `__getitem__` over a fixed field list, `("no", "yes")[flag]`,
selecting from a literal of branches. It is a crash rather than a wrong value,
so it fails loudly — but it fails at RUNTIME with no compile-time hint, in code
that reads as ordinary Python.

## Track B site

`lib/rtl/mimic_urllib_parse.py` — `SplitResult.__getitem__` and
`ParseResult.__getitem__` bind the field tuple to a local before indexing it
instead of `return (self.scheme, ...)[i]`. Registered in
`devdocs/dev/track-b-workarounds.md`; revert when this lands.
