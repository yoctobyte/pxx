---
track: A
prio: 45
type: bug
blocked-by: []
owner: claude-A
status: done
---

# A metaclass-typed FIELD is not recognised as a receiver

- **Type:** bug (wrong refusal) — **Track A**
- **Found:** 2026-08-10 by an FPC differential over the class / property /
  metaclass surface.
- **Pre-existing.**

```pascal
type TBaseClass = class of TBase;
     TCfg = record m: TBaseClass; end;
var cfg: TCfg;
begin cfg.m := TDer; WriteLn(cfg.m.Kind); end.
```

FPC prints `der`. pxx refused:

    "Kind": a pointer has no members (dereference it with ^, or the pointee
    type is unknown here)

## The shape — a list of base kinds, one entry short. Again.

`ParseLValueAST` decides "is this node a metaclass value?" from an explicit
**list of base node kinds**, each taught separately:

| base | added |
| --- | --- |
| a `class of T` VARIABLE (`AN_IDENT`) | original |
| a metaclass CAST (`AN_PTR_CAST`) | for the streamer's `TComponentClass(GetClass(n)).Create` |
| an array ELEMENT (`AN_INDEX`) | **b328**, `bug-pascal-metaclass-array-element-not-a-receiver` |
| a record/class FIELD (`AN_FIELD`) | **missing — this ticket** |

This is the third time the same list has been extended one case at a time, and
it is the identical failure mode as
[[bug-a-indexing-a-function-call-result-drops-the-field-selector]]
(`ResolveNodeRec`'s `AN_INDEX` arm, also a list by base kind, also missing
exactly one entry). See
[[project_record_field_and_selector_resolution_landmines]].

The field already carries everything needed — `UFldPtrElemTk` /
`UFldPtrElemRec`, mirroring the symbol's `PtrElemTk` / `PtrElemRec` — so the
new arm is four lines and reuses the existing `ci` handoff.

## Fixed

`AN_FIELD` added to the receiver list. `test/test_metaclass_field_receiver.pas`
covers a named record field, an anonymous-record field, a CLASS field, and
virtual-constructor dispatch through the field (`cfg.m.Create` running the
right ctor chain, asserted as `B|BD`), with the variable / array-element /
parameter spellings kept as controls. Diffed against `fpc -O1`; the field rows
fail on `pinned`.

`tools/gate.sh quick` GREEN, self-host fixedpoint converged in 1 round.

## Found alongside, filed separately

A metaclass returned from a FUNCTION (`Give.Kind` for
`function Give: TBaseClass`) is a fourth missing base kind, in a DIFFERENT list
— `ApplyCallResultPtrSuffix` routes a typed-pointer call result to the
record-field walker, which builds an `AN_FIELD` for what is actually a class
method and then cannot lower it (`IR_UNSUPPORTED`, kind 8). Filed as
[[bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver]].

## Log
- 2026-08-10 — resolved, commit bc977325f.
