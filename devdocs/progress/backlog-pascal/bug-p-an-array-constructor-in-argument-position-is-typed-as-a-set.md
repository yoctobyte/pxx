---
slug: bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set
title: "`['x']` in argument position is typed as a set, so an `array of` overload is never reachable"
track: P
prio: 55
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [overload-resolution, open-arrays, sets, array-constructor]
blocked-by: []
summary: "A `[...]` constructor in an argument position is typed as a SET unconditionally, so an `array of T` parameter can never be selected for one. Two outcomes, and the SECOND is the reason this is not a diagnostic ticket: with no set-typed candidate in scope pxx REFUSES (`no overload of P matches these arguments / argument types: (set)`) where fpc compiles; with a set-typed parameter in scope -- including one that is only a DEFAULT, `f: TF = []` -- pxx compiles and SILENTLY SELECTS THE WRONG OVERLOAD, answering 1 where fpc answers 2 on the same six-line source. Found while writing test/lib_sysutils_executeprocess.pas, whose real declarations have exactly the default-set shape; the fixture passes variables rather than literals to stay a test of ExecuteProcess."
---

# `['x']` is a set, even where only an array can go

## Repro

Six lines, no RTL, no `uses`:

```pascal
program n;
function P(const c: AnsiString): Integer; overload;
begin P := 1; end;
function P(const c: array of AnsiString): Integer; overload;
begin P := 2; end;
begin WriteLn(P(['x'])); end.
```

- fpc 3.2.2 (`-Mobjfpc`): compiles, prints **2**.
- pxx (pinned): **refuses**

```
pascal26:6: error: no overload of P matches these arguments
  argument types: (set)
```

Add a set-typed default parameter to both candidates -- `f: TF = []`, with
`TF = set of (fA, fB)` -- and the refusal becomes something worse:

- fpc: prints **2**
- pxx: compiles and prints **1**

The literal is typed as a set, the set-shaped candidate now accepts *something*,
and the `array of AnsiString` overload is never in the running. Nothing is
reported.

## Why the silent arm matters more than the refusal

A refusal is a wall: it stops, it names a line, somebody fixes it. The
default-parameter arm compiles clean and calls a different function, and the
only way to notice is to have an oracle beside you. Against the real
`sysutils.ExecuteProcess` declarations -- which carry `Flags: TExecuteFlags = []`
on both overloads, so they ARE this shape --
`ExecuteProcess('/bin/sh', ['x'])` answers **0** under pxx and **2** under fpc,
because pxx never passes the argument to a child at all.

A multi-element literal of multi-character strings takes a third door and
refuses with a message about the wrong construct entirely:
`ExecuteProcess('/bin/sh', ['-c', 'exit 4'])` gives
`pascal26:5: error: set item must be one character`, where fpc runs it and
answers 4.

## What it is NOT

Not a corpus blocker. FPC's own `cfileutl.pas` call sites pass variables, so
this does not gate `umbrella-pxx-compiles-fpc-itself`. It is filed on the
strength of the silent arm, not on population.

## Shape of the fix

The decision needs the CANDIDATE's parameter type to reach the constructor's
typing, rather than typing the constructor first and matching afterwards --
`[...]` is ambiguous by construction in this dialect and only the target type
disambiguates it. Whether that is a re-type-on-retry in the overload loop or a
deferred literal kind is an implementation question, not a fork.

## Provenance

Found 2026-09-11 while writing `test/lib_sysutils_executeprocess.pas` for
[[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]. The note that
survived into that fixture's header recorded the diagnostic as
`(ShortString, set, set)`; re-derived against the declarations as they actually
stand, the single-element case does not refuse at all -- it is the silent arm.
The remembered spelling was a refusal variant with the extra arguments still on
it. Recording that because the header comment still quotes the old spelling as
the reason it uses variables, and the reason is sound either way.

## MEASURED 2026-09-16 (frankb-56) — the fix is NARROWER than this ticket assumed, and an attempt is reverted

Attempted, not landed. The work is reverted and the tree is clean; what follows
is what the attempt established, so the next seat does not re-derive it.

**THE LOWERING IS NOT THE PROBLEM. ONLY RANKING IS BLIND.** With exactly ONE
candidate in scope, this already works today:

```pascal
function P(const c: array of AnsiString): Integer;   { no overload }
begin P := Length(c); end;
begin WriteLn(P(['x', 'yy'])); end.        { fpc 2, pxx 2 }
```

So the `AN_SET_LIT -> AN_ARRAY_CTOR` retag (`RetagSetLitAsArrayCtor`, ir.inc)
is reached and correct for an argument. This ticket's "shape of the fix" says
the candidate's parameter type must reach the constructor's TYPING; measured,
the typing downstream is already fine and it is **overload ranking alone** that
never lets the array candidate compete.

**THE AMBIGUOUS CASE MUST NOT MOVE, AND A GENERAL FIX WOULD MOVE IT.** With an
ordinal element and BOTH candidates in scope, fpc picks the SET:

| source | fpc | pxx |
| --- | --- | --- |
| `Q([fA])`, `Q(const c: TF)` + `Q(const c: array of Integer)` | 1 | **1 — already correct** |
| `P(['x'])`, `P(const c: AnsiString)` + `P(const c: array of AnsiString)` | 2 | refuses |
| `P(['xy'])`, same candidates | 2 | refuses |
| ...with a set-typed DEFAULT on both | 2 | **1, silently** |

So "let the parameter type disambiguate" is too wide — it would regress row 1,
which costs nothing today. Only the not-a-set literal may be re-presented.

**FOUR THINGS THE ATTEMPT ESTABLISHED, each one a dead end closed:**

1. `MatchArgArray` alone is NOT enough. Setting it moves the diagnostic from
   `argument types: (set)` to `(array of set)` and still refuses — the
   argument's KIND must also present as the ELEMENT kind, which is how every
   real array argument presents (`an array symbol's TypeKind is its element
   kind`, symtab.inc).
2. `AssignKindsIncompatible` (symtab.inc:4678, `(dstTk = tySet) <> (srcTk =
   tySet)`) is a kind-pair function and is CORRECT as it stands. The fix does
   not belong there; the architecture's own answer is a side channel, since
   every existing channel exists because "the kind pair alone gave a WRONG
   ANSWER".
3. **There are TWO argTk sites, a sibling pair** — `FindUMethOverloadAhead`
   (pasparser_call.inc, methods) and `MatchCallDelphiProcAddr`
   (pasparser_lval.inc, free functions, whose `argTypes` is built by FOUR
   callers). Patching one leaves the other; normalising inside
   `MatchCallDelphiProcAddr` reaches all four, and its existing `litTypes` /
   `litRetry` corrected-copy retry is the right vehicle.
4. **THE PARSER ALREADY COMPUTES THE SIGNAL AND IT DID NOT FIRE.**
   `ParseSetLiteralAST` sets `SetLitNonSet` for a string element and parks it as
   `ASTSLen[node] := 1` (pasparser_lval.inc), precisely so a later consumer can
   tell the two spellings apart. Keying off that flag still produced no change
   for `P(['xy'])`.

**THE ONE PROBE THE NEXT SEAT SHOULD RUN FIRST**, because everything above is
downstream of it: dump the argument node (`PXXDBG=a.ast`) at the call and check
whether `ASTSLen` is actually 1 on the node the matcher receives, and whether
that node is the `AN_SET_LIT` at all. Either the flag is not being set on this
path, or the matcher is handed a different node — and which of those it is
decides the whole fix. Do not re-derive the element kind from the elements: an
attempt to do that answered `tyUnknown` for exactly the shape the flag already
had right, which is the two-tables defect one scope down.
