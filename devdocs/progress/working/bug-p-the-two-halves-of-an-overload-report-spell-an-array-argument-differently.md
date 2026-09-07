---
track: P
prio: 50
type: bug
blocked-by: []
status: working
tags: [diagnostics, overload, param-kind-union, corpus]
summary: "FIXED 2026-09-07, both halves, and the free half was a different bug from the method half. The argument side of `no overload of X matches` printed a raw TTypeKind while the candidate side printed an IsArray-aware spelling, so a CORRECT array argument read as a mismatch. TWO causes: the printers had no array-aware argument spelling (one new function, `ArgSpellingForReport`, reading the MatchArgArray channels that already existed — the tickets stated signature-change obstacle was wrong), and on the FREE path the failed variadic-bracket-elision retry overwrote OverloadReport with a report about the argument list IT invented. Both halves now print `array of record`; two negative fixtures in test-core, controlled against a compiler with the fix stashed out."
owner: frankA
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

---

## FIXED 2026-09-07 — and the free half was NOT the same bug as the method half

Both halves now print the same string for the same argument:

```
=== free                                     === method
  argument types: (Integer, Integer,           argument types: (Integer, Integer,
                   array of record)                             array of record)
  candidates:
    P(Integer, class, array of record)
```

Measured against a control compiler built with the three edits stashed out
(`09170224a3c4`): **both halves print `record` there**, both print
`array of record` with the fix (`c7eb35aff4ce`).

### 1. The stated obstacle was about an instrument that already exists

The section above says the fix is a signature change threading `argIsArray`
through six call sites across two frontends. It is not. **`MatchArgArray`,
`MatchArgArrayElemTk` and `MatchArgDynDepth` already exist** (defs.inc
~3437-3471), are filled from the AST node for every argument of every call by
the shared `FillMatchArgChannelsAt`, and are live for the whole of
`MatchProcCall` under `MatchArgArrayValid`. They were added for
`bug-p-an-array-argument-binds-a-scalar-overload` and the probe refactor; the
ticket read the SIGNATURE and concluded the knowledge was absent, when what was
absent was only a way to ask for it through that signature.

So the printer half is one new function, `ArgSpellingForReport` (symtab.inc),
the mirror of `ParamSpellingForReport`, gated on `MatchArgArrayValid` so a
caller that never filled the channels gets the old bare spelling rather than a
stale one.

### 2. The method printer reads the channels by PARAMETER slot, not by argument

`pasparser_call.inc`'s method probe fills the channels **at the candidate's
parameter slot `pj`** (:3628) and invalidates them per candidate (:3697), which
is right for matching and wrong for a report indexed by argument. Its printer
refills by ARGUMENT index in the measured no-parse window before spelling.

### 3. The free half had a SECOND cause, and it is the interesting one

With the printer fixed the method half was correct and **the free half still
printed `record`**. Instrumented rather than reasoned about (a temporary
`{XNOTARR}` marker in the spelling function, then a trace of the node kind seen
at each fill): `MatchArgArrayValid` was True and `MatchArgArray[2]` was False,
and the node the channels described had kind **50 = AN_VARREC_ARRAY** — a node
the programmer never wrote.

`TryElideVariadicBrackets` (pasparser_lval.inc) is the variadic
bracket-elision fallback. It runs from the `procIdx < 0` arm, splices a
`TVarRec` vector in place of the trailing arguments, and **re-resolves through
the real resolver** — and `MatchProcCall` writes `OverloadReport` as a side
effect on the way out. So a retry that FAILS overwrites the diagnostic with one
describing the argument list the fallback invented. The report was not
inconsistent with itself; **each half was correct about a different argument
list.**

Why this call reaches the fallback at all: `ParamIsVarRecArrayAt` answers True
for ANY open array whose element is a record, so a plain `array of TR`
parameter is scanned as a possible `array of const`. Its own comment states the
contract — *"a candidate scan that is too loose costs a rejected retry, never a
wrong bind"* — and that was true right up until something downstream of the
retry was read. **The looseness is left alone deliberately**: narrowing it to
`TVarRecId` would hide this instance and not the class, because a genuine
`array of const` candidate whose retry fails clobbers the report just the same.

Fix: `TryElideVariadicBrackets` saves `OverloadReport` on entry and restores it
on the failure path, for the same reason it already rolls the argument chain
back. A speculative retry's diagnostic is speculative too.

### Tests

Two negative fixtures, because the two printers are different code AND because
the method half halts where the free half recovers:

- `test_an_overload_report_spells_an_array_argument_the_same_at_a_method_call.pas`
- `test_an_overload_report_spells_an_array_argument_the_same_at_a_free_call.pas`

Both greped in `test-core` for the identical string. The free fixture's
parameter must stay a record-element array or the elision fallback never fires
and it stops testing cause 3 — that is written into the fixture.

### Residual

`ParamIsVarRecArrayAt`'s scan is loose by design and now has a reader that
cares; nothing is broken by it today. Not filed: the save/restore makes the
class safe, and a ticket saying "this scan is loose" with no observable would be
`rejected/` on arrival.
