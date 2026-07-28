---
track: N
prio: 70
type: bug
---

# `.field` on a dynamically-typed value is refused when two classes disagree

```
pascal26:435: error: Nil Python: .x on a dynamically-typed value is ambiguous
  (several classes declare it at different offsets) — assign to an annotated
  local first
```

The shape is a Tk event handler, which is as ordinary as Python gets:

```python
def get_tab_index_at(event):
    ...event.x...
```

`PyMakeVariantField` (`pyparser.inc`) resolves `.field` on a variant by scanning
EVERY class for one that declares the name and unboxing to it. With exactly one
declarer that is right. With two whose field sits at a different offset or type
it cannot pick, and refuses — correctly, since guessing would read the wrong
bytes silently. But the refusal asks the application to change, and the
application is the thing we are trying to compile unchanged.

## The fix it wants

Runtime dispatch, which the METHOD path already does for the same reason: emit
a chain that tests the receiver's actual class and reads at that class's offset
(`PyParseVariantMethod`'s dual-dispatch arms are the model). Only the candidate
classes that declare the name need arms, and the fallback is the current error
turned into a runtime one.

Cheaper interim: when exactly one candidate is a class the RECEIVER could hold
— e.g. it came from a `bind` callback and tkinter's Event is the only widget
class declaring `x` — prefer it. That is a guess, and this ticket prefers the
dispatch.

## Where it bites

`SongFormatter.py:435` — the last compiler-side wall in the songformatter track
([[feature-demo-songformatter-pxx-target]]). Everything before it now compiles.

## Resolved 2026-07-28 (c141327c)

Runtime dispatch, as recommended: `PyMakeVariantField` collects every candidate
class, and when they disagree on offset or type emits one
`pyvarobj(v) is C ? <read as C> : ...` arm each, forcing the arms to Variant
through pylib's new `pyvar_id` when the field types differ. A single shared
layout still reads directly, so nothing that already compiled changed shape.
Covered by `test/test_nilpy_ambiguous_variant_field.npy` against CPython.

## Gate

`make test-nilpy` plus a `.npy` with two classes declaring the same field name
at different offsets, read through a variant, diffed against CPython.

## Log
- 2026-07-28 — resolved, commit c141327c.
