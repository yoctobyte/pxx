---
slug: bug-p-a-generic-routine-supports-exactly-one-type-parameter
title: "A generic routine supports exactly ONE type parameter — the second is a syntax error"
track: P
prio: 40
type: bug
blocked-by: []
status: working
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
