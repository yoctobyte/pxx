---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`xs[0].foo = 1` SEGFAULTS (rc 139) where CPython raises `'int' object has no attribute 'foo' and no __dict__ for setting new attributes`. pydynattr_set_v checks the CLASS-REFERENCE tag and nothing else, so a scalar-tagged variant falls through to `pydynattr_set(pyvarobj(v), ...)` and scalar bits are reinterpreted as an object address. THE MECHANISM, so this does not decay when the instance is fixed: ONE concept with TWO runtime entry points whose authors held different beliefs about the same population -- the twin `pydynattr_get_v` DOES check the tag and its own comment says why (`for any other tag (str/int/float/bool) it is scalar bits reinterpreted as an address, and ClassName on that would dereference garbage`), while set_v's comment says `Only a CLASS REFERENCE needs telling apart here`, which is the claim that is false. Found by grepping for the sibling while fixing the GETTER's compile-time twin (bug-n-an-attribute-on-a-scalar-returned-by-a-call-segfaults), not by a test. Measured 2026-09-21 at HEAD; the getter's fix does not touch this and the two are independent. compiler/builtin/pylib.pas."
---

# A dynamic attribute STORE on a scalar variant segfaults

## Repro

    xs = [5]
    xs[0].foo = 1
    print("survived")

| | result |
| --- | --- |
| CPython | `AttributeError: 'int' object has no attribute 'foo' and no __dict__ for setting new attributes` |
| pxx @ HEAD | **SIGSEGV, rc 139** |

## Cause

`pydynattr_set_v` (`compiler/builtin/pylib.pas`) tells apart exactly one tag:

```pascal
  if pyvartag(v) = 11 then    { VT_CLASSREF }
  begin
    if PyClsAttrRefSet(v, name, val) then Exit;
    raise AttributeError.Create(...);
  end;
  pydynattr_set(pyvarobj(v), name, val);
```

`pyvarobj(v)` on a `VT_INT64` payload yields the integer reinterpreted as an
address. Every non-object, non-classref tag reaches it.

## Why this is a CLASS and not one row — the part worth keeping

**The read twin already does it right, and says so in its own comment:**

> *"Unlike `pydynattr_get` above, `pyvarobj(v)`'s raw payload is only a real
> object pointer when the tag says so (VT_OBJECT); for any other tag
> (str/int/float/bool) it is scalar bits reinterpreted as an address, and
> ClassName on that would dereference garbage. **Check the tag first.**"*

`pydynattr_get_v` gates its object work on `tg = 7`. `pydynattr_set_v` gates on
nothing. So the condition that springs a bug of this shape is **a concept with
two runtime entry points where only one carries the guard** — and this file's
own comments keep calling that out (`normalise-dont-special-case.md` is cited
three times in it). The sibling here is not a different SHAPE, it is the
opposite DIRECTION of the same operation, which is why grepping for the
construct does not find it and grepping for the other spelling's handler does.

## The fix, and the thing to check before writing it

Gate on the tag: `VT_OBJECT` (7) takes the store, `VT_CLASSREF` (11) keeps its
existing arm, anything else raises. CPython's wording is uniform across kinds —
measured, all eight of int/float/bool/str/list/tuple/dict/NoneType give
`'<kind>' object has no attribute '<name>' and no __dict__ for setting new
attributes` — and `PyVarTypeNameOf` already exists in the same unit.

**Check first whether any tag OTHER than 7 legitimately reaches the store
today.** The getter's route census is not evidence about the setter, and a
`None` receiver in particular needs its answer chosen rather than inherited.

## Acceptance

`xs[0].foo = 1` raising with CPython's message rather than crashing, a
positive control showing the fixture reds on the current compiler, and the
existing class-reference row (`c.num = 9`,
`bug-nilpy-class-attribute-through-a-class-reference-reads-garbage`) unchanged.

## Note on the neighbouring parse gap, so it is not conflated

`mk().foo = 1` does not parse at all — a call result is not accepted as an
assignment target, where CPython accepts it and raises at run time. Loud, no
wrong value, and a different ticket if it is worth one.
