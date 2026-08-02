---
track: N
prio: 65
type: bug
summary: "`o.ClassName` on a TObject local compiles to a NilPy DYNAMIC ATTRIBUTE fetch instead of the RTTI call, while `TObject(obj).ClassName` compiles correctly — same expression, different shape, different meaning"
status: done
owner: claude-AN
---

# `o.ClassName` on a `TObject` local silently becomes a dynamic-attr fetch

- **Type:** bug (NilPy lowering / name resolution) — **Track N**
- **Found:** 2026-08-02, while implementing
  [[bug-nilpy-type-name-reports-the-internal-pascal-class]] (fixed in `e6768db40`).

## The two spellings

Both inside `compiler/builtin/pylib.pas`, both on the same object:

```pascal
var obj: Pointer; o: TObject;
...
o := TObject(obj);
Result := o.ClassName;            { WRONG — becomes a dynamic attribute fetch }
Result := TObject(obj).ClassName; { RIGHT — the RTTI ClassName call }
```

The first form does not read RTTI at all. It lowers to NilPy's dynamic
attribute path, so at run time a user NilPy class instance dies with:

```
Unhandled exception: AttributeError: 'Dog' object has no attribute 'ClassName'
```

The second form, which is what the two neighbouring `AttributeError` sites in
`pydynattr_get` / `pydynattr_get_v` already use, compiles to the RTTI call and
works. The fix that hit this simply adopted the working spelling.

## Why this matters more than the one call site

This is the **shape-blindspot pattern** again
([[project_string_conversion_shape_blindspot_pattern]]): a lowering decision
keyed on the syntactic SHAPE of the receiver (a bare local vs an explicit cast)
rather than on its resolved TYPE. `o` is declared `TObject`; there is nothing
ambiguous about it. Any Pascal code in `pylib.pas` that reaches for a `TObject`
method through a plain local is exposed, and the failure is a run-time
AttributeError far from the source line — not a compile error.

It is *loud* when it fires (an unhandled AttributeError), which is why this is
prio 65 and not higher. But it is loud only if that branch is reached: the
fallback arm in `pytype_name_v` is taken solely for user classes, so it survived
the container cases and only surfaced when a test covered `type(Dog()).__name__`.

## Repro

The compact repro is a Pascal one inside pylib, but it is observable from NilPy:
add to `pytype_name_v`'s fallback arm `Result := o.ClassName;` (with
`o: TObject` assigned from the pointer), rebuild, then:

```python
class Dog:
    pass
print(type(Dog()).__name__)     # AttributeError: 'Dog' object has no attribute 'ClassName'
```

## What to investigate

Which lowering decides that a `.<ident>` on a class-typed receiver goes to the
NilPy dynamic-attr path. The guard is presumably "is this a NilPy compilation
and did the member lookup miss?" — but `ClassName` is not a declared field, it
is a `TObject` method, so the member lookup has to consult the RTTI/method side
before concluding "miss → dynamic attr". The cast form evidently takes a
different route that does consult it.

Worth checking whether the same divergence affects other `TObject` members
(`ClassType`, `InheritsFrom`, `Free`) through a plain local, and whether it is
NilPy-only or also reachable from Pascal (`isNilPy` gates a lot of this).

## Gate

A `.npy` that calls `type(<user class instance>).__name__` already covers the
regression (`test/test_nilpy_type_name.npy`). A direct test wants a Pascal unit
in the NilPy builtin set calling `o.ClassName` on a plain `TObject` local.


## Resolved 2026-08-02 — commit e455ff322

The ticket's "What to investigate" was right about where to look and the answer
was one predicate.

The dynamic-attribute fallback (`parser.inc`, the `FindUField`/`FindUMeth`/
`FindUProp` all-miss branch) was gated on **`isNilPy`**, which is true for the
WHOLE compilation — every Pascal unit loaded into a NilPy program included. So a
Python-only rule was deciding member resolution inside `pylib.pas` and friends: a
`TObject` method reached through a plain local is not a declared member of the
receiver's UClass, all three lookups miss, and the branch concluded "undeclared
-> dynamic attribute". The cast form takes a different route that consults RTTI,
which is why one spelling worked and the difference looked arbitrary.

Changed to **`NilPyUserCode`**, the predicate that already gates every other
NilPy-only rule ("the main `.npy`/`.py` the user wrote, not the Pascal units
compiled alongside it").

### Answers to the ticket's open questions

- **Other `TObject` members through a plain local:** measured, same bug, same
  fix. `ClassName`, `ClassType.ClassName` and `InheritsFrom` all resolve now;
  all three were on the dynamic-attr path before.
- **NilPy-only or also Pascal-reachable?** NilPy-only. The branch was
  `isNilPy`-gated, so a pure-Pascal compilation never entered it. What was
  exposed is precisely "a Pascal unit inside a NilPy build".
- **Did the fallback itself survive?** Yes, and it is tested in the same file:
  an attribute no class declares, read, written and augmented from NilPy code.

### Test

`test/test_nilpy_tobject_member_via_local.npy` + `test/nilpy_units/tobjprobe.pas`
(wired into `make test-nilpy`). Both spellings are kept side by side on purpose:
a regression that re-breaks only the local form should read as the one-line
divergence it is rather than as a whole-file failure.

### Noted in passing, NOT chased

`InheritsFrom(TObject)` on a NilPy user-class instance returns **False**. That is
consistent with pxx's model — a NilPy class is registered as a UClass with no
parent, so it is not a TObject descendant even though `TObject(p)` casts to one —
but it is worth knowing before anyone writes `InheritsFrom` into pylib expecting
Delphi semantics. Not filed: it is a modelling question, not a wrong value, and
nothing depends on it today.

Gate: `gate.sh quick` GREEN, self-host fixedpoint byte-identical.

## Log
- 2026-08-02 — resolved, commit e455ff322.
