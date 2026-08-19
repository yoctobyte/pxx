---
track: N
prio: 45
type: bug
blocked-by: []
commit: 5a81d19aa
summary: "`sorted(xs, key=str)` SEGFAULTED — a builtin type held as a value is a VT_BTYPE variant, the key slot is a raw code Pointer, and the coercion passed the variant's TAG WORD as a code address, so the program jumped to address 13. Fixed with the second half it exposed: str() of a container through the dynamic path answered the empty string."
---

# `sorted(xs, key=str)` jumps to address 13

```python
xs = [3, 1, 20]
print(sorted(xs, key=str))     # CPython [1, 20, 3]   pxx: Segmentation fault
print(min(xs, key=int))        # CPython 1            pxx: TypeError: expected a number, got object
```

`key=str`, `key=int`, `key=float` crashed; `key=len` raised; `key=abs` failed to
compile; `key=repr`, `key=<lambda>` and `key=<def>` were fine. Found 2026-08-15
by a CPython differential sweep — the probe died with SIGSEGV and no output.

## Cause — the three callable representations, crossed

A builtin type in value position is `pybtype(code)`, a **VT_BTYPE variant**
(`t = str; t(5)` works through it). A `key=` parameter is a raw code
**Pointer**: `PyCallKey1` calls straight through it. Coercing the variant into
the pointer parameter passed the variant's FIRST WORD — the tag, 13 — as the
code address, and `f1 := TPyKeyCbF1(13); f1(a0)` jumped to address 13.

Exactly `project_nilpy_callable_has_three_representations`, whose tell is
recorded there: **the faulting PC is a small tag number**.

`repr` survived because it is a pylib proc, not a type name, so it took the
function-value path instead.

## Fix

`PyFixCallableTypeArgs` rewrites a `pybtype(<code>)` argument in a callback slot
to the ADDRESS of the one-argument routine that type performs — new pylib
`pyconv_str` / `_int` / `_float` / `_bool` / `_list` / `_dict` / `_set`, each a
one-liner over the existing `pybtype_call1`. Only the codes that routine
implements are mapped; the rest keep its own named refusal.

**Before overload matching, not after** — which is the measurement that shaped
the fix. A post-match version fixed `sorted` and left `min(xs, key=str)` binding
the scalar `min(Variant, Variant)` overload with the type as its second operand
("expected a number, got object"): the argument's TYPE is what picks the
overload, so a fixup after the fact cannot undo a wrong pick. That is also why
the callback question is asked of the NAME's whole overload family
(`PyNameWantsCallbackAt`) rather than of a chosen proc.

## The second bug it exposed

With the crash gone, `sorted(d.items(), key=str)` came out in the wrong ORDER:
every key was the empty string. `pystr_of(const v: Variant)` had no VT_OBJECT
arm and fell through to `VariantToStr` — builtin.pas's low-level SCALAR
formatter, which knows nothing about pylib's objects and answers `''`. So
`map(str, [(1,2), [3], {"k":1}])` gave `['', '', '']` while the identical
`[str(x) for x in ...]` was correct, because only the DYNAMIC path comes here.
Now renders through `pyvar_print_of`, the same renderer `print` uses —
`project_nilpy_three_rendering_paths_print_str_fstring`, again.

## Gate

`test/test_nilpy_builtin_type_as_callback.npy` (+`.expected`, in the Makefile),
byte-identical to CPython: `key=str/int/float/bool/repr/len/lambda` over
`sorted`, `min`, `max`, over ints, floats, strs and dict items; a type still
usable as a VALUE (`t = str; t(5)`, `L = list; L("ab")`, `type(5) == int`); and
`str()` of a tuple, list, dict and set through `map`, through a comprehension
and directly. `gate.sh quick` GREEN. Pinned (`compiler/builtin/**`).
