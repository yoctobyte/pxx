---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: frankS
---

# A specialization in a routine-local `type` section desyncs the parse

`type TLocal = specialize TT<Word>;` inside a routine's own declaration part
breaks the routine: the specialized declaration is spliced at `TokPos`, where
the surrounding grammar is a routine body rather than a top-level declaration
list, and the parse never finds the routine's `begin`.

```pascal
type generic TT<T> = record f: T; end;
function B: Integer;
type TLocal = specialize TT<Word>;     { <- here }
var t: TLocal;
begin t.f := 5; Result := t.f; end;
```

`pascal26:6: error: expected 'begin' before ':='` — a diagnostic about the
routine BODY for a defect in where a declaration was inserted, so it points
several lines past the cause.

## Three-way control, measured at compiler `10797249be20`

| program | result |
| --- | --- |
| routine-local `type` section, plain record | compiles |
| global `specialize`, the type then used inside a routine | compiles |
| routine-local `type` section containing `specialize` | **desyncs** |

So it is neither local type sections nor specialization. It is the combination,
which isolates the splice POSITION as the only variable. The template in the
control has NO methods, so this is not the method-body splice — the type
DECLARATION alone is enough to break it.

## The assumption, stated in the code

`ParseSpecialization` splices through `SpecializeStream(...)` at `TokPos`, and
the comment immediately below it says what that is for:

> the streamed `procedure`/`function` bodies land after the whole `type` block
> and are parsed as ordinary top-level subroutines

True at file scope. False inside a routine, where "after the whole type block"
is the routine's `var` section and then its body. Nothing is wrong with the
comment — it is an accurate description of the only case that existed when it
was written.

## Shape of the fix

A specialized type is a GLOBAL entity: it has no dependency on the routine it
was named in, and FPC treats a local specialization as a local NAME for a
global type. So the declaration wants hoisting to a position where the
surrounding grammar is a declaration list, with only the alias left behind in
the routine's scope.

Not attempted on the way past. This is the second member of a family with
`bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section`,
and both want the same answer from the same four call paths
(`ParseGenericFunctionDef`, `ParseTopLevelSpecialize`,
`SpecializeImportedGenericFuncUses`, `ExpandGenericMethod`). Doing them
together is the work; doing either alone risks a third splice site.

## Corpus

`tgeneric95.pp` and `tgeneric94.pp`. Both skip reasons were wrong and are
corrected in the same commit as this file: tgeneric95's said "specialize inside
a generic routine SIGNATURE" — the routine is not generic, no signature
contains a specialization, and the construct is a local type section. Measure
the wall, do not read it.
