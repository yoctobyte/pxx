---
slug: bug-p-a-generic-routine-supports-exactly-one-type-parameter
title: "A generic routine supports exactly ONE type parameter — the second is a syntax error"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-05
found-by: frankS
summary: "`generic procedure Pair<T, S>(a: T; b: S);` is refused at the IMPLEMENTATION with `expected '>' before ','`. Not a parse slip: `GenericFuncs[].Param` is a single AnsiString and `SetGenericRoutineSubs` takes one paramName, so the data model holds exactly one type parameter for a routine. Generic CLASSES take several (`generic TPair<T, S> = class` parses and builds), so this is routines only. The interface line is accepted and the implementation line is not, which makes the diagnostic point at the wrong section. Blocks measuring the SWAP case of bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface, and that is the reason it was found."
---

# A generic routine supports exactly one type parameter

## Repro — three programs, and the boundary is sharp

```pascal
{ 1. ONE type parameter: works end to end, prints solo=5 }
unit u_one; {$mode objfpc}
interface  generic procedure Solo<T>(a: T);
implementation
generic procedure Solo<T>(a: T); begin WriteLn('solo=', a); end;
end.

{ 2. TWO type parameters on a CLASS: parses and builds }
unit u_cls2; {$mode objfpc}
interface  type generic TPair<T, S> = class FA: T; FB: S; end;
implementation end.

{ 3. TWO type parameters on a ROUTINE: refused }
unit u_match; {$mode objfpc}
interface  generic procedure Pair<T, S>(a: T; b: S);
implementation
generic procedure Pair<T, S>(a: T; b: S); begin WriteLn('a=', a, ' b=', b); end;
end.
```

```
pascal26:5: error: expected '>' before ','
  in: u_match.pas
  near: implementation generic procedure Pair < T >>> , S >
```

FPC 3.2.2 compiles all three.

## It is a data-model limit, not a missing loop

`pasparser_generic.inc:4498` onwards parses the header and stores
`GenericFuncs[gfi].Param` — **one** `AnsiString`. `SetGenericRoutineSubs`
(`:4459`) takes a single `paramName`, and the specialization sites call it once
per routine. Supporting a list means changing the record to an array and
threading it through every substitution site, so it is not a one-liner and is
not attempted here.

**The error points at the implementation, and that is misleading.** The
interface line is accepted — only the implementation-side header refuses — so a
reader is told the two lines differ when in fact neither form is supported. Whoever
takes this should check whether the interface path is genuinely more permissive
or merely defers the failure; they are different bugs.

## Why this was found, and what it blocks

Measuring the SWAP case of
[[bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface]].
A *rename* (`<T>` declared, `<S>` implemented) cannot mislead, because both
spellings denote the same position. A *swap* can — `<T,S>` declared against
`<S,T>` implemented, with the signature held fixed, is a program that means
something different from what it says. That distinction decides whether the
skip-list bucket is `wontfix: dialect-pass` or `gap: accepts-invalid`.

**The swap case is unreachable today**, because no two-parameter generic routine
parses at all. So the hazard cannot bite anyone at present, and the rename case
alone is a genuine dialect-pass. **Whoever fixes THIS ticket re-opens that
question** and must re-measure the swap before assuming the existing bucket
still applies — the note in the skip list will by then be answering a question
that has changed underneath it.

## Fixed — and the substitution engine was never the limit

The ticket reads this as needing a change "to an array and threading it through
every substitution site". Only the first half was true, and the second half was
already done: `SpecSubNames` / `SpecSubValues` / `SpecSubKinds` are
`MAX_TEMPLATE_PARAMS` wide and generic CLASSES have always filled them. Three
sites simply wrote `SpecSubCount := 1` and read slot 0.

So it was three places, not "every substitution site":

1. the header parser in `ParseGenericFunctionDef` — `<T>` became a list;
2. `SpecializeInlineGenericFuncUses` — the use matcher reads an argument LIST
   and mangles `F_A_B`;
3. `ParseTopLevelSpecialize` — the `specialize F<A, B> as N` form.

## The wall the ticket did not know about: TGenericFunc is a BUILT-IN record

The obvious change — `Params: array[...] of AnsiString; NParams: Integer` as
fields — **cannot be compiled by the compiler that precedes it.** Round 0 of the
fixedpoint answered `"NParams": no such member on this record/class`, because
`TGenericFunc`'s layout is hard-coded in `symtab.inc`'s `REC_TGENERICFUNC` table
and baked into the compiler BINARY.

This is already recorded — `defs.inc` at `GenericFuncIsDelphi` states it, and it
was measured on 2026-09-05 with the table, the size check and the declaration
all updated together and all agreeing with each other. I hit it anyway by
reaching for the record before reading the note two screens below it. The
established remedy is what `GenericFuncIsDelphi` and `GenericFuncSrcKey` already
are: **parallel arrays**. `GenericFuncParams` (flat, one row of
`MAX_TEMPLATE_PARAMS` per routine) and `GenericFuncNParams`.

The dead `Param` field stays declared, with a comment saying why: removing a
field from that record is exactly as impossible as adding one.

## The diagnostic the ticket asks about

The ticket says the error pointing at the implementation is misleading and asks
whether the interface path is genuinely more permissive. **It is not** — the
interface line is BUFFERED, not parsed through the header parser, so neither
form was supported and the reader was told the two lines differed. That is now
moot, but it is the answer to the question.

A second diagnostic came out of the fix. An arity MISMATCH must not be
rewritten, so the matcher declines — and declining silently left the run in the
stream to be read as an expression, which reported `undefined variable
(specialize)`: a true statement about the token that survived, naming neither
the routine nor the count. With the `specialize` keyword written, a name match
at the wrong arity cannot be anything else, so it now says `generic routine Pair
takes 2 type argument(s), not 1`. The bare Delphi surface stays quiet and falls
through, because there the same tokens are a legal comparison chain.

## Measured

`test/test_generic_routine_type_parameter_arity.pas` + `generic_routine_arity_units/`,
`.expected` from fpc 3.2.2, wired into `test-core`. Arity 1, 2 and 3 across a
uses clause, both surfaces, and `Pair<string, Integer>` versus `Pair<Integer,
string>` as two distinct specializations — the row that fails if the mangled
name stops carrying the whole list, and the only one that can. Pin v404 refuses
the unit outright with this ticket's own `expected '>' before ','`.

The Delphi surface `function Combine<T, S>(a: T; b: S): Integer` matches fpc
when the result goes through `Result`; fpc refuses the `Combine :=` spelling of
its own accord, reading the function's own name as the generic template. We
accept it, which is not a defect.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
