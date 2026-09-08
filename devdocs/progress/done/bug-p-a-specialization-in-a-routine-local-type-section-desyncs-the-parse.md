---
track: P
prio: 45
type: bug
blocked-by: []
status: done
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

## FIXED at `2f1fe06b9` — resolved 2026-09-08, and NO DIFF WAS ADDED TODAY

`fix(P): a routine-local type section is parsed in PASS 2, so its specialize
splice must move the spans` landed on 2026-09-06 and is this ticket's fix. It
was never resolved; only the paperwork lagged. Saying so plainly matters,
because a ticket that closes with an empty diff is indistinguishable from one
quietly re-filed, and the P-bug umbrella (`6a768f917`) asks for the split.

**The mechanism was not the one this ticket predicted, and that is worth
keeping.** This file says the splice lands "where the surrounding grammar is a
routine body" and proposes HOISTING the declaration to a declaration list. The
measured cause was narrower: `SpecializeStreamAt` called `AdjustSrcRanges` and
deliberately not `AdjustPass2Spans`, on a documented argument that no splice
site is reachable while `Pass2Active` — and `ParseSubroutine`'s own
`tkVar/tkConst/tkType` loop is the second caller of `ParseTypeSection`, running
during the BODY pass. `Pass2BodyTok` stayed put while the stream grew by seven
tokens, so the pass-2 driver re-entered the body seven tokens early. **A defect
in an INDEX, reported as a scope error, several lines from the splice** — which
is exactly why this ticket's own diagnostic pointed past the cause. Nothing had
to be hoisted.

### Re-measured today at compiler `cd2d264c72df`, this ticket's own three-way control

|  | pxx | fpc 3.2.2 |
| --- | --- | --- |
| routine-local `type`, plain record | 5 | 5 |
| global `specialize`, used inside a routine | 5 | 5 |
| routine-local `type` containing `specialize` | **5** | 5 |

The third row is this ticket's headline repro, verbatim, and it now compiles and
runs. **Positive control: pin v407 still refuses it with the exact reported
diagnostic** — `pascal26:7: error: expected 'begin' before ':='` — so the fix is
INERT for anything built against `$(PXX_STABLE)` until the next pin.

### The corpus rows named here are already burned

`tgeneric94.pp` and `tgeneric95.pp` are **no longer in
`test/pascal-conformance/pxx.skip`** — `2f1fe06b9` burned both (128 -> 126 gap
rows at the time). Both compile and run `rc=0` at `cd2d264c72df`. Regression
fixture `test/test_routine_local_specialization.pas`, seven rows, wired.

### The FAMILY claim in this ticket is still TRUE and the sibling is still OPEN

`bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section`
was measured today at `cd2d264c72df` rather than assumed: `tgenfunc19.pp:32`
still answers `undefined variable (TTest2)`. **So the two did NOT want the same
answer after all** — this one needed a span adjustment and nothing moved, while
that one genuinely needs the body splice separated from the call-site rewrite.
The prediction that doing either alone "risks a third splice site" did not
happen; attribution: it was a reasonable guess and the measurement went the
other way. That sibling, and the generic-ROUTINE arm of
`bug-p-a-specializations-concrete-argument-is-keyed-by-its-spelling-so-two-scopes-types-collide`
(`tgenfunc10.pp`, same splice-position cause seen from the template side), are
the live members of the family.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
