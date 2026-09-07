---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: frankS
---

# A generic routine's specialization renames a FIELD spelled like the routine

`SpecializeToBuffer` (pasparser_generic.inc:698) rewrites **every** token
spelled like the template name to the specialization's name. A member name is
not a type or routine reference, so a field spelled like the generic routine is
captured too:

```pascal
generic function Test<T>(aArg: T): LongInt;
begin
  Result := aArg.Test;          { <-- Test here is a FIELD }
end;
type TRec = record Test: LongInt; end;
```

MEASURED 2026-09-07 at compiler `c3b9c27982f0`:

| probe | pxx | fpc |
| --- | --- | --- |
| field named `Test`, routine named `Test` | `"Test_TTestGlobal": no such member on this record/class` | prints 42 |
| identical, field renamed `Fld` | prints 42 | prints 42 |

The rename is the only difference, which is what makes it the lookup and not the
record. It is a REFUSAL, not a wrong value.

## The shape of the fix

The arm immediately above it already carves out one position where the template
name cannot mean the specialization — a base-class position, keyed on the two
preceding tokens being `class` `(`. A token preceded by `.` is the second such
position: a member name.

**Not yet applied, and one thing to settle first.** A `.` also introduces a
UNIT-QUALIFIED name (`SomeUnit.TFoo`), where the token after the dot IS a type
reference and DOES need rewriting. The token stream at this stage cannot tell a
unit qualifier from a member selector. Two options: take the `.` guard
generally and let the 550-file corpus judge, or thread a flag so the guard
applies only on the generic-ROUTINE path (`GenericFuncs[sg].Name`, line 4565),
where `Unit.RoutineName` inside the routine's own body is vanishingly rare,
while the CLASS-template path — where `Unit.TFoo` is plausible — keeps the
current behaviour. The first is cheap to measure and cheap to revert.

## Where it was found

`test/pascal-conformance/pxx.skip`'s `tgenfunc10.pp`, whose body is exactly this
shape (`generic function Test<T>` … `Result := aArg.Test`). **That row's skip
reason is wrong** — it reads "inline `specialize` expression inside generic
function body" and the file contains no such thing: it is `{ %NORUN }`, the
generic's body is a single field access, and the `specialize Test<TTest>(t)`
calls sit in ordinary procedures.

The row has a SECOND blocker behind this one: its two `TTest` types are
ROUTINE-LOCAL, and a routine-local type as a specialization argument answers
`unknown type: TTest` — see
[[bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling-so-two-scopes-types-collide]],
for which this file is the corpus row: the two locals are deliberately
DIFFERENT (one `LongInt`, one `String`), so a spelling-keyed cache collides even
once visibility is fixed.
