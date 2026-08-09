---
prio: 50
track: N
type: bug
blocked-by: []
---

# `max()` of a VARIANT holding a list read it as a string

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-09, running a realistic grid program against CPython.
- **Status:** FIXED the same session.

```python
grid = [[1, 2], [4, 3]]
for row in grid:
    print(max(row))     # CPython 2, 4     pxx ValueError: max() arg is an empty sequence
```

`sum(row)`, `len(row)` and `sorted(row)` on the SAME value were all correct.

## Cause

A loop element is a VARIANT. pylib's only single-argument `min`/`max` overload
took an `AnsiString` (added for `max("abc")`, which iterates characters), so a
variant holding a list matched it, came out empty and raised.

The two-argument forms and a statically-typed list both had exact matches and
always worked — which is what kept this out of every API sweep. It needs the
value to arrive as a variant, and that only happens through a loop element, a
parameter, a dict value or a nested subscript.

Same family as [[bug-nilpy-dict-update-with-a-variant-argument-segfaults]]
fixed the same night: **a variant argument matches no typed overload and takes
whichever single-argument one exists.** Worth a grep for other single-argument
overload sets in pylib with a variant-reachable caller.

## Fix
`max(const v: Variant)` / `min(const v: Variant)` that dispatch on the runtime
tag: a string iterates characters as before, a TPyList iterates elements, and
anything else raises TypeError. Comparison goes through `pyvar_gt`, so a list of
user objects honours `__lt__`/`__gt__` exactly as `sorted()` does.

## Three latent bugs this surfaced — worth recording

Adding the forward declaration **in the middle of the implementation section**
made unrelated, long-standing forward uses start failing to compile
(`PySliceBounds`, `PyVarText`). Moving the declaration to the unit's TOP
declaration block fixed that.

But the failures it exposed were real: three sites added EARLIER THE SAME NIGHT
(`pystr_translate`, `pystr_startswith_any`, `pystr_endswith_any`) called
`PyVarText`, which is defined ~3000 lines below them. Those forward uses do not
fail to compile — they link to a plausible wrong address
([[project_bodyless_procaddr_links_to_entry_minus_one]]) — so all three passed
their tests by luck. They now use `VariantToStr` from `builtin.pas` instead.

**The lesson for this unit: check where a helper is DEFINED before calling it,
not just that it exists.** A passing test does not prove the call resolved.

## Verified
`test/test_nilpy_min_max_of_a_variant_list.{npy,expected}` (`.expected` from
CPython): every route to a variant (loop element, enumerate element, parameter,
dict value, nested subscript), the string case that owns the overload it was
stealing, floats, strings, and a list of user objects with `__lt__`.
`gate.sh quick` GREEN; nine realistic programs and the str/sort test families
re-diffed against CPython.
