---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: ""
summary: "In {$MODE DELPHI} a bare method name passed as an ARGUMENT is read as a CALL, not as a method reference: `Take(HashIt)` answers `no overload of Take matches these arguments / argument types: (LongInt)` -- the method's RESULT type, one reading past the actual gap, so it reads as an overload defect and is nothing of the kind. fpc 3.2.2 -Mdelphi compiles it. 14-line repro, NO generics. The ASSIGNMENT arm already works (`F := HashIt`, `Result := HashIt`), so this is the sibling arm of the parenless-method-reference family that was never built: TryParseParenlessMethodRef has callers for a method-pointer CAST and for assignment, and argument position has TryDelphiBareProcArg, which asks FindProc and so cannot see a METHOD at all. This is the LIVE WALL of feature-pascal-corpus-generics at generics.defaults.pas:2729. A first fix was written, measured and REVERTED -- see below; it fixes the free-callee half and turns the method-callee half into a SEGFAULT, which is worse than today's honest refusal."
---

# A bare method name in argument position is called instead of referenced

## Repro — 14 lines, no generics

```pascal
program p; {$mode delphi}
type
  TOnHash = function(const v: LongInt): LongInt of object;
  TC = class
    function HashIt(const v: LongInt): LongInt;
    procedure Take(const h: TOnHash);
    procedure Go;
  end;
function TC.HashIt(const v: LongInt): LongInt; begin Result := v + 1; end;
procedure TC.Take(const h: TOnHash); begin WriteLn('took ', h(41)); end;
procedure TC.Go; begin Take(HashIt); end;      { <-- here }
var c: TC;
begin c := TC.Create; c.Go; end.
```

fpc 3.2.2 `-Mdelphi`: `took 42`. pxx: `no overload of Take matches these
arguments / argument types: (LongInt)`.

**The dialect is load-bearing.** In `objfpc` a bare method name IS a call and
`@` is required — fpc rejects the same program there, with a different message.
A probe written in objfpc mode says nothing about this bug; the corpus unit is
`{$MODE DELPHI}`.

## The matrix — which contexts already work

| context | pxx | fpc |
| --- | --- | --- |
| `F := HashIt` (assignment) | ok | ok |
| `Result := HashIt` (return) | ok | ok |
| `Take(HashIt)` (argument) | **refused** — `no overload of Take matches` | ok |
| `Take(Self.HashIt)` (qualified argument) | **refused** — `wrong number of parameters` | ok |

Two diagnostics, one missing reading — which is why it can read as two bugs.

## Mechanism

`TryParseParenlessMethodRef` (pasparser_call.inc) is the ONE place an
`AN_METHODREF` is built for this family, and its own comment says to count
construction sites rather than add to them. It has callers for a method-pointer
CAST and for the assignment site. **Argument position has a different door,
`TryDelphiBareProcArg` (pasparser_lval.inc), and that door asks `FindProc` —
which does not see a method.** So a bare method name in an argument list never
reaches the reference reading at all and falls to `ParseArgExpr`, which reads a
call. A rule spelled per CALLER, failing by an absent copy.

## What was tried, measured, and REVERTED

Routing the method case into the one helper from `TryDelphiBareProcArg`:

- **Fixes the free-callee half.** A bare method name given to a FREE procedure
  went refused -> correct (`freetake 42`, matching fpc).
- **Breaks the method-callee half into a SEGFAULT.** `Take(HashIt)` where `Take`
  is a method compiled and died calling through the pair. `PXXDBG=a.ast` shows
  the argument is still `kind=8` (AN_CALL), never `AN_METHODREF` (45), yet typed
  `tk=11` (record) — so it slips past overload matching and is marshalled as a
  method pointer it is not. **There is a third site deciding this that I did not
  locate**, and until it is found this fix must not land: today's refusal is
  honest and a segfault is not.

Two facts any future attempt needs, both measured:

- **`Params[0]` of a method is the implicit `Self`** (`pn[0] := 'Self'`), so the
  free-routine precedence tests — paramless function, all-defaulted — must read
  slot 1 and compare `ParamCount = 1`, not 0. Reading slot 0 asks whether SELF
  has a default; both mis-aimings are silently false and both err toward
  addressing what Delphi calls. `MethodResultSatisfiesTarget` already makes this
  adjustment in its `ParamCount > 1` test.
- **The overload probe in `FindUMethOverloadAhead` (pasparser_call.inc) parses
  arguments with a bare `ParseArgExpr` and no hook**, then rewinds. When the
  probe and the real parse disagree about call-vs-reference, the probe wins the
  SELECTION and the real parse builds the node. That is a real gap and worth
  closing on its own, but it is NOT this bug's cause: the probe only runs with
  more than one candidate, and the repro has a single `Take`.

## Why the precedence cannot simply be the assignment site's

The assignment site knows its DESTINATION and can ask
`MethodResultSatisfiesTarget` — would calling this already produce the method
pointer the target wants? In argument position the destination is not known yet,
because overload resolution has not run. The question available there is the
free-routine one: can this be called parenless at all? A paramless function can,
and Delphi calls it; a routine that REQUIRES arguments cannot, so the reference
is the only reading that compiles.

# 2026-09-09 — the parse half is SOLVED and it is not enough (frankuser)

Attempted, measured, **not landed**. `TryDelphiBareProcArg` in
`compiler/pasparser_lval.inc` asks `FindProc`, which sees free routines only,
so inside a method body the reference reading was never reached at all. Adding a
method arm — mirroring `TryParseParenlessMethodRef`'s implicit-Self arm in
`pasparser_call.inc` verbatim, `ASTRight := UMthVirSlot` included — makes the
repro COMPILE. It then **segfaults at the indirect call**:

```
ok: bare  [code=69400B data=3504B bss=43532B procs=140]
took            <- prints the literal, dies calling h(41)
Segmentation fault (core dumped)
```

So the ticket's own warning holds and this is the same wall the earlier attempt
hit: **the parser is now right and something downstream is not.** What that
changes is the search area — it is no longer 'find the third site that decides
the reading'. The reading is decided correctly; the defect is in lowering the
`AN_METHODREF` argument to a method-pointer temp, or in the temp's layout at the
call. `ir.inc:5659` already routes `AN_METHODREF` to `IRMethodRefToTemp` when the
param is `tyRecord`, so the route exists and the value it produces is wrong —
check the `Self` operand actually reaches the temp, and check the two-word
method-pointer layout against what the `of object` call site reads.

**Do not land the parser arm alone.** Today's `no overload of Take matches` is an
honest refusal; a segfault is not, and the arm converts one into the other.

Three measured facts worth keeping, all cheap to get wrong:

- `Params[0]` of a method is the implicit `Self`, so the free-routine precedence
  tests must read slot 1 and compare `ParamCount = 1`. Reading slot 0 asks
  whether `Self` has a default — always false, and false in the direction that
  silently takes an address where Delphi would have called.
- `ASTRight := UMthVirSlot[rmmi]` is load-bearing. Omit it and a **virtual**
  method binds the base rather than the override — a silently wrong target that
  no repro in this ticket exercises.
- `FindUMethOverloadAhead` probes arguments with a bare `ParseArgExpr` and no
  hook. That is a real second gap, and it is NOT this bug's cause: the repro has
  a single `Take`.

The working arm is reproducible from this description in about ten minutes; it
was deliberately not committed, because a patch that turns a diagnostic into a
crash is worse to inherit than a description of one.
