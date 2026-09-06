---
track: P
prio: 50
type: bug
blocked-by: []
status: backlog
tags: [diagnostics, overload, param-kind-union, corpus]
summary: "The argument half of `no overload of X matches` prints a raw TTypeKind and the candidate half prints an IsArray-aware spelling, so a CORRECT array argument reads as a mismatch: `argument types: (Integer, Integer, record)` against `candidates: Q(Integer, class, array of record)` where argument 3 is fine and only argument 2 is wrong. 12-line repro. Matching itself is CORRECT — both sides compare element kinds — so this is the report lying, not the compiler. It is actively misleading the live reduction of pparser.pp:2670."
---

# The two halves of an overload report spell an array argument differently

## Repro — 12 lines, and argument 3 is DELIBERATELY CORRECT

```pascal
program spell;
{$mode objfpc}
type
  TR = record N: Integer; end;
  TArrR = array of TR;
  TCls = class F: Integer; end;
procedure Q(a: Integer; c: TCls; r: TArrR); begin end;
var ar: TArrR; n: Integer;
begin
  SetLength(ar,1); n := 1;
  Q(n, n, ar);          { arg2 wrong (Integer for class), arg3 CORRECT }
end.
```

```
error: no overload of Q matches these arguments
  argument types: (Integer, Integer, record)
  candidates:
    Q(Integer, class, array of record)
```

`ar` matches `r` exactly. It still reads as the third of three mismatches.

## The cause is a fix applied to one half of a double case

`Procs[pi].Params[j].TypeKind` is one field with two meanings — the parameter's
OWN kind when `IsArray` is False, its ELEMENT kind when True
([[refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither]]).

`ParamSpellingForReport` (symtab.inc:11800) exists precisely to spell the
CANDIDATE side correctly, and its own comment says why:

> The report read it as the first, unconditionally, so `OnlyArr(3)` refused the
> call and then offered `OnlyArr(LongInt)` as the candidate — which is a
> spelling of the call the programmer had just made. **That is the worst shape a
> diagnostic can take: it does not merely fail to help, it argues for the
> mistake.**

The ARGUMENT side never got the sibling treatment. Both printers —
`pasparser_call.inc:3556` and `symtab.inc:12350` — render arguments with a bare
`TypeKindSpelling(argTypes[j])`. Exactly the case
`normalise-dont-special-case.md` names: *fixed one arm of a double case? grep
for the sibling before closing.*

## What is NOT wrong

**Matching is correct and this is not a wrong-value bug.** The match loop
compares `Procs[i].Params[j].TypeKind <> argTypes[j]`, and when the parameter is
an array BOTH sides hold the ELEMENT kind, so the comparison is consistent. Only
the rendering disagrees. A call that should compile still compiles.

## Why it is worth more than a cosmetic

It is misreading a live reduction. `pparser.pp:2670` — rung 7's last remaining
wall, [[bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals]] —
reports:

```
  argument types: (Integer, Integer, record)
  candidates:
    PeekOper$62727(Integer, class, array of record)
```

which is the repro above, shape for shape. **Argument 3 there is fine and
argument 2 is the whole mismatch**, consistent with wrong capture actuals being
spliced in. Anyone reducing that wall while believing it has two bad arguments
is chasing one that does not exist. frankD flagged the suspicion; this measured
it.

## The obstacle, so nobody starts expecting a one-liner

`MatchProcCall` receives `const argTypes: array of TTypeKind` and **no
companion array-ness**, and there is no `argIsArray` anywhere in the tree. Every
call site would have to thread it (`symtab.inc:11845`,
`pasparser_lval.inc:7619/7625/7650/7694/7743`, `pyparser.inc:666`). That is why
it is filed rather than fixed in passing: it is a signature change across two
frontends, not a printer tweak.

Cheaper interim if someone wants the misleading half gone sooner: the argument
side could omit the type list entirely when any candidate has an array
parameter, rather than print a spelling it cannot make comparable. **A report
that says less is better than one that argues for the mistake** — that is this
file's own precedent, quoted above.
