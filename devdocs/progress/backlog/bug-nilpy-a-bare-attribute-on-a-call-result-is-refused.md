---
track: N
prio: 50
type: bug
summary: "`g(3).v` — a bare ATTRIBUTE (no parens) on a call result is a parse error, while `g(3).show()` and `g()[1]` now work. The runtime getter it would need, pydynattr_get_v, only consults the dynamic-attribute side store and never the object's DECLARED fields, so wiring the parse alone turns the error into a false AttributeError."
---

# A bare attribute on a call result is refused

Split from `bug-nilpy-a-method-call-on-a-callable-values-result-is-refused`,
which asked for `.attr` and `[` to be checked alongside `.method()`. Two of the
three landed; this is the third, and it is NOT just a parser gap.

```python
class A:
    def __init__(self, v): self.v = v
    def show(self): return "A" + str(self.v)

def mk(v): return A(v)
g = mk
g(3).show()   # works now
g()[1]        # works now (list case)
g(3).v        # pascal26: error: unexpected token   —  CPython: 3
```

`o = g(3); o.v` works, so the field read itself is fine; only the chained,
non-ident receiver is refused.

## Why the parser fix alone is NOT the fix — measured

Every `.`-loop in ParseFactor's suffix cluster requires `.name(`, so a bare
attribute on a non-ident receiver is claimed by nobody. Adding a loop that
routes it to `PyMakeDynAttrGet` (the same builder an ident receiver uses) makes
it PARSE — and then it raises at run time:

```
Unhandled exception: AttributeError: 'A' object has no attribute 'v'
```

`pydynattr_get_v` (pylib.pas) looks only in `PyDynAttrStore`, the side table for
attributes created by assignment/`setattr`. A field DECLARED by the class is
invisible to it, so the getter answers "no attribute" for a field that plainly
exists. The ident-receiver path does not go through this helper at all — the
frontend knows the receiver's class and emits a static field read.

That change was written, measured, and **reverted**: turning a loud compile
error into a plausible-but-false `AttributeError` moves the failure away from
the cause, which is the expensive failure class here. The parse gap stays
visible until the runtime half exists.

## What the runtime half needs

The RTTI blob already carries the fields — `lib/rtl/typinfo.pas`:

```pascal
TClassRTTI = record ... FieldCount: Int64; FieldsPtr: PFieldInfo; end;
TFieldInfo = record NamePtr: PString; Offset, TypeKind, RecId, Flags: Int64; end;
```

So the fallback is: walk `FieldsPtr` up the `ParentRTTI` chain (as
`PyFindMethCI` does for methods), match the name case-insensitively, then box
`inst + Offset` by `TypeKind`. pylib does not mirror `PFieldInfo` yet, so that
record and a kind switch (int/int64/double/bool/char/ansistring/class/variant)
are the work — roughly the same shape `PyFindMethCI` + `PyHostCall` have for
methods, and it would serve `getattr()` on a declared field too.

## Gate

`make test-nilpy` + self-host byte-identical, with `.npy` cases for `g(3).v`,
a chain `g(3).v + 1`, an INHERITED field, a field of each scalar kind, and a
genuinely missing attribute still raising AttributeError — diffed against
CPython. Extend `test_nilpy_postfix_after_parens`, which already carries the
`.method()` and `[i]` halves.
