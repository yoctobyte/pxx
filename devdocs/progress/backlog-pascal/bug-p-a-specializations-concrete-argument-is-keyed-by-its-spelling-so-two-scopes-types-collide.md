---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: frankS
---

# A specialization's concrete argument is keyed by its SPELLING, so two scopes' types of one name collide into a single specialization

```pascal
generic TBox<T> = record f: T; end;
procedure Outer;
type TRec = packed record p, q, r: Byte; end;   { 3 }
     TBoxRec = specialize TBox<TRec>;
  procedure Inner;
  type TRec = packed record s: Byte; end;       { 1 }
       TBoxRec = specialize TBox<TRec>;
  var ib: TBoxRec;
  begin Writeln(SizeOf(ib.f)); end;             { fpc 1, pxx 3 }
```

A bare `TRec` in `Inner` resolves correctly now (the five name tables are
scoped), so the compiler knows perfectly well which type is meant one line
earlier. The specialization does not ask it. `ParseSpecialization`'s
already-declared shortcut compares `SpecConcreteNames[...]` — the argument's
SPELLING — against the existing row, finds `TRec` = `TRec`, and reuses the outer
specialization whole. **The type identity is carried by a string, and two
distinct types in two scopes have the same string.**

Split out of `bug-p-routine-local-name-scoping-is-implemented-in-one-of-three-tables`
after the scoping fix landed: it was invisible while the bare name resolved
wrong too, because both halves agreed on the wrong type and the program looked
merely consistent.

## The mirror image is already open, and they should be fixed together

`bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization`
[p55, working, same owner] is the SAME keying flaw in the opposite direction:
there, two aliases of ONE specialization mint TWO classes (`a1 is TIntBox2`
answers FALSE where fpc says TRUE). Here, two DIFFERENT types collapse into one
specialization. Over-minting and under-minting from a single cause — a name
standing in for the thing it names — and its body already says the canonical key
exists and is already correct for the inline spelling (`TBox$Int64`). If that
key were also what the dedup compares, both directions close.

Do not fix this one by making the comparison stricter in isolation: that mints a
second specialization per scope and lands on the other ticket's defect from the
other side.

## What is green over it

`tgeneric94.pp` passes and cannot see this either, for the reason recorded in
`bug-p-a-nested-routines-local-type-does-not-shadow-the-enclosing-routines`: its
expected value comes from the same lookup as its actual. The assertion that does
fail is the one in this ticket's own repro.
