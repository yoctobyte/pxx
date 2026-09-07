---
track: P
prio: 45
type: bug
blocked-by: []
status: done
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

## The fix — APPLIED 2026-09-07, corrected at compiler 46709f4e7648

The arm immediately above it already carved out one position where the template
name cannot mean the specialization — a base-class position, keyed on the two
preceding tokens being `class` `(`. A token preceded by `.` is the second such
position, and it is now a second arm beside the first.

Fixture `test/test_specialization_does_not_rename_after_a_dot.pas` (+
`test/units/uspecdotname.pas`), differential against fpc, three rows: the field
case, the unit-qualified case, and — the point of the file — a CONTROL with the
field renamed `Fld`, which was always correct. Without that row, the field row
alone is equally consistent with the record being wrong rather than the lookup.
Positive control is pin v407, which refuses it with BOTH `"Test_TRecTest": no
such member` and `"Tag": no such member`, one per defective row.

**MEASURED 2026-09-07, and it settles the obvious objection.** The worry was
that a `.` also introduces a UNIT-QUALIFIED name (`SomeUnit.TFoo`), where the
token after the dot IS a type reference and might need rewriting. It does not,
and the guard is not a judgement call:

1. A template cannot be reached as `SomeUnit.Template` meaning itself-
   specialized. **fpc refuses the syntax**: `specialize ugq.TBox<T>` gives
   `Type identifier expected` / `Syntax error, "<" expected but "." found`.
2. A unit-qualified name after a dot means the OTHER unit's type — and pxx
   ALREADY gets that wrong, in the same direction and for the same reason:

   ```pascal
   generic TBox<T> = class
     V: T;
     P: uother.TBox;    { uother's plain record, NOT this specialization }
   end;
   ```
   fpc prints `7 9`; pxx says `"Tag": no such member on this record/class`,
   because `TBox` after the dot was rewritten to the specialization's name.

So both of those dot cases — member selector and unit qualifier — want the same
answer, which is *do not rewrite*.

**THERE IS A THIRD READING, AND THIS TICKET SAID THERE WAS NOT.** A generic
method's IMPLEMENTATION HEADER puts the template name after a dot too:

```pascal
generic class function TTest.Add<T>(aLeft, aRight: T): T;
```

and there the name IS the routine being defined and MUST be rewritten. The first
cut of the guard dropped it and broke FOUR corpus rows — tgenfunc3, tgenfunc4,
tgenfunc9, tgenfunc12, all `unresolved forward: TTest.Add_LongInt` — **while
`gate.sh quick` stayed GREEN**, because nothing in the quick tier declares a
generic method out of line. `407 pass, 4 fail` on the conformance corpus is what
caught it, and the corpus was run only because this change touches the
specializer.

The two probes that convinced me there was no third reading were both real and
both correct; they were just not a survey. A measurement that kills one
objection does not establish that no other objection exists, and writing "there
is no third one" turned two checked facts into an unchecked universal.

So the test is not "is there a dot" but WHAT THE DOT JOINS, and a header is what
the two preceding tokens say: `function`/`procedure` then the class name.
`Result := aArg.Test` has `:=` in that slot and `P: uother.TBox` has `:`.

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

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 923c0a581.
