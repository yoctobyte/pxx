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
summary: "A `[...]` constructor in an argument position is typed as a SET whenever there is more than one candidate, so an `array of T` parameter can never be selected for one: `P(['x'])` against an `AnsiString` / `array of AnsiString` overload pair is REFUSED (`argument types: (set)`) where fpc compiles and answers 2. With exactly ONE candidate it already works -- the lowering is fine and only overload RANKING is blind (measured 2026-09-16, frankb-56). The DEFAULT-PARAMETER arm this summary used to describe as the worse half -- `f: TF = []` making pxx compile and silently answer 1 -- turned out NOT to be about sets at all: it was [[bug-p-a-defaulted-trailing-parameter-disables-argument-type-checking]], a defaulted trailing parameter switching off argument type checking for every type, fixed 2026-09-17. pxx now selects fpc's candidate there (2) and still presents the argument as a SET, so the callee reads a garbage length -- one defect where there were two, not a fix. The remaining divergence is exactly the multi-candidate rows; the binding rule fpc actually follows is measured below and is narrower than this ticket's own \"shape of the fix\"."
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

## MEASURED 2026-09-17 (frankS) — the derived rule, and one of the two arms was a different bug

Picking this up from `d7946acb6` as instructed rather than from the body above.
Two things changed since that handoff.

### The named next probe cannot be run, and the code answers it anyway

`d7946acb6` ends by naming one probe: dump the argument node with
`PXXDBG=a.ast` and check whether `ASTSLen` is 1 on the node the matcher
receives. **That probe cannot answer it.** The refusing compile aborts before
any AST dump runs, and there is no `PXXDBG` topic for overload matching at all
(`a.ast`, `a.ir`, `n.locals`, `n.ctorargs` are the four). Read instead:
`ParseSetLiteralAST` parks the flag as `if SetLitNonSet then ASTSLen[node] := 1
else ASTSLen[node] := 0` (pasparser_lval.inc), and the save/restore around a
nested `[...]` at 4267-4270 is correct — the restore happens before the string
check, so a nested literal cannot clear an outer tally.

### THE FLAG IS NOT THE DISCRIMINATOR, AND THE ONE-CHARACTER ROW PROVES IT

A ONE-character string literal is folded as a **Char**, so `['x']` is a
perfectly good set and `SetLitNonSet` never fires on it. Yet:

```pascal
procedure P(const c: array of AnsiString);   { the ONLY candidate }
begin WriteLn('count=', Length(c), ' [0]=', c[0]); end;
begin P(['x']); end.        { fpc: count=1 [0]=x   pxx: count=1 [0]=x }
```

pxx already lowers that correctly. So the single-candidate success **does not
depend on the non-set flag**, and the banked framing *"only a literal that
cannot be a set may be re-presented"* is not the rule — it would have to refuse
this row, which works. Whatever decides the single-candidate case
(`TryParseBracketArgForSlot`, which asks the PARAMETER) is already the right
mechanism; ranking simply never consults it.

### The boundary, measured

All rows fpc 3.2.2 `-Mobjfpc` against pxx at HEAD **after** the defaulted-
parameter fix. "receiving param" is the parameter at the argument's own
position, in each candidate.

| # | receiving-param candidates | literal | fpc | pxx |
| --- | --- | --- | --- | --- |
| n | `AnsiString` / `array of AnsiString` | `['x']` | 2 | **REFUSES** `(set)` |
| c5 | same, plus a later set-typed default `f: TF = []` | `['x']` | 2 | **2, garbage arg** |
| c3 | `set of Char` / `array of AnsiString` | `['x']` | 1 | 1 |
| c4 | `set of Char` / `array of AnsiString` | `['xy']` | refuses | refuses |
| c6 | `array of AnsiString` ONLY | `['xy']` | 2 | 2 |
| c7 | `set of Char` ONLY | `['x']` | 1 | 1 |
| c8 | `array of AnsiString` ONLY | `['x']` (set-able) | 2 | 2 |
| Q | `TF` set / `array of Integer` | `[fA]` | 1 | 1 |

**Derived rule, and it reproduces all eight:** the `[...]` binds as a SET when
the RECEIVING parameter is a set type, and may be an array constructor
otherwise. A set-typed parameter **elsewhere in the signature** does not make it
a set — c5 is the row that settles that, and it is the row the old summary read
as the set machinery misfiring.

That rule keeps `Q([fA])` at 1 (its receiving parameter IS a set) without any
appeal to what the elements can be, so it satisfies frankb-56's constraint —
*"let the parameter type disambiguate is too wide"* — by being about the
RECEIVING parameter rather than about the signature. The divergence narrows to
exactly two rows, n and c5, and both are "no candidate's receiving parameter at
this position is a set type".

### What the defaulted-parameter fix changed here, and what it did not

`bug-p-a-defaulted-trailing-parameter-disables-argument-type-checking` (done,
2026-09-17) removed the fallback that was rescuing the `AnsiString` candidate
in row c5. pxx now picks fpc's candidate there. **The argument is still a set**:
instrumented, the array overload runs and reports `count=17297991344808736`.
So c5 moved from "wrong overload, garbage" to "right overload, garbage" — worth
recording because a bare re-run of the old six-line repro now prints **2**,
fpc's own answer, and reads as fixed. It is not. Instrument the callee before
believing that row.

Rows n, c3, c4, c6, c7, c8 and Q are unmoved by that fix.
