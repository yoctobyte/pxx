---
prio: 65
track: P
status: done
summary: "FIXED 2026-09-07. A nested FUNCTION's OWN `Result` was captured as if it were the ENCLOSING function's, snapshotting the enclosing type: PeekOper was declared (OpStackTop:Integer, Result:CLASS, OpStack:array) because DoParseExpression returns TPasExpr, while the sibling call in PopOper resolved the `Result` actual in POPOPER's scope, where it is PopOper's own TToken. Cause found with a new PXXDBG p.lift probe, reduced to 26 lines. The fix is one condition in ParseNestedRoutine's free-variable scan: when the nested routine is a FUNCTION, `Result` is an OWN name and is not captured -- a nested PROCEDURE, which has no result, still captures it. fcl-passrc's pparser.pp now compiles clean (3.5s, 1806 procs) where the pin refuses it. Regression assertion test_nestownres26. The two other Result-spelling defects this ticket had bundled in are MEASURED UNCHANGED by the fix and are filed separately.""
owner: frankS
---

## The construct

`/usr/share/fpcsrc/3.2.2/packages/fcl-passrc/src/pparser.pp`, inside
`function TPasParser.DoParseExpression(AParent: TPaselement; InitExpr: TPasExpr;
AllowEqual: Boolean): TPasExpr` — a METHOD, with a **method-local `type`
section** declaring `TOpStackItem = record Token: TToken; SrcPos:
TPasSourcePos; end`, and locals `ExpStack: TFPList`, `OpStack: array of
TOpStackItem`, `OpStackTop: integer`, `PrefixCnt`, `x`, `i`, `TempOp`,
`NotBinary`.

```pascal
  function PeekOper: TToken; inline;            { :2662 }
  begin
    if OpStackTop>=0 then Result:=OpStack[OpStackTop].Token
    else Result:=tkEOF;
  end;

  function PopOper(out SrcPos: TPasSourcePos): TToken;
  begin
    Result:=PeekOper;                           { :2670  <- the wall }
```

Two further sibling call sites at `:2770` and `:2773` (`TempOp:=PeekOper;`).

## Reproduce

```
./compiler/pascal26 --mimic-fpc \
  -Fu/usr/share/fpcsrc/3.2.2/packages/fcl-passrc/src \
  -Fi/usr/share/fpcsrc/3.2.2/packages/fcl-passrc/src \
  -Fulib/rtl -Fulib/rtl/platform/posix \
  <driver>.pas <out>
```
with `program X; uses pparser; begin end.`. ~5s at compiler `8b10e02e2029`.
`--mimic-fpc` is REQUIRED; without it the run dies on `FPC_FULLVERSION has no
integer value`, an invocation error wearing the shape of a frontend bug.

## Read the diagnostic with all three of its coordinates distrusted

```
pascal26:2670: error: no overload of PeekOper$62727 matches these arguments
  argument types: (Integer, Integer, record)
  candidates:
    PeekOper$62727(Integer, class, array of record)
  in: .../pscanner.pp
  near: FWarnMsgStates [ i ] . Number >>> = Number )
```

- **The LINE is right and the FILE is wrong.** `:2670` is the real construct;
  `pscanner.pp:2670` is the middle of `TFileResolver.FindIncludeFile`. This is
  the third arrangement of this corpus's coordinate problem — see
  [[feature-pascal-corpus-expansion]], which has the other two (a stale `near:`
  across a unit boundary, and a line constant equal to the file length).
- **`near:` is from the wrong file too**, so it corroborates nothing: it is
  `pscanner.pp` content. Two coordinates agreeing does not make two sources —
  they are one reading.
- **`PeekOper$62727` IS NOT A STABLE IDENTIFIER.** Same source, different
  builds: `$62774` earlier the same day, `$62727` now. It is a node counter.
  Never a search key, never a slug; cite `PeekOper` and put the suffix beside
  it.
- **Cheap discriminator for the file attribution**, if it is worth settling:
  compile the accused unit ALONE.

## What is not yet explained

1. **Three hidden parameters for two free variables.** `PeekOper` reads
   `OpStackTop` and `OpStack`. `needSelf` would put the class FIRST
   (`ParseNestedRoutine` emits `Self` before the captures), and it is second —
   so the `class` is probably a captured local, and `ExpStack: TFPList` is the
   only candidate. `PeekOper` does not mention it; `PopExp` (the sibling above
   it) does. **Suspect an over-broad or cross-contaminated free-variable scan**
   — `ParseNestedRoutine`'s scan has a shadow stack for walking INTO inner
   nested routines, and siblings are the neighbouring case.
## SETTLED: argument 3 is not a mismatch at all

frank-coord-core measured it 2026-09-06 rather than reasoning it, with a 12-line
repro in which argument 3 is deliberately CORRECT:

```pascal
type TR = record N: Integer; end;
     TArrR = array of TR;
     TCls = class F: Integer; end;
procedure Q(a: Integer; c: TCls; r: TArrR); begin end;
var ar: TArrR; n: Integer;
begin SetLength(ar,1); n := 1; Q(n, n, ar); end.
```
```
argument types: (Integer, Integer, record)
candidates:    Q(Integer, class, array of record)
```

`ar` matches `r` exactly and still renders as the third of three mismatches —
shape for shape identical to `:2670`. **A fix applied to one half of a double
case**: `ParamSpellingForReport` (`symtab.inc:11800`) exists to spell the
CANDIDATE side IsArray-aware, and the argument side never got the sibling
treatment — both printers render arguments with a bare
`TypeKindSpelling(argTypes[j])`. Matching is CORRECT and no value is wrong: the
loop compares `Params[j].TypeKind` against `argTypes[j]` and when the parameter
is an array both hold the ELEMENT kind. Only the rendering disagrees.

Its own ticket: [[bug-p-the-two-halves-of-an-overload-report-spell-an-array-argument-differently]]
(prio 50; not a one-liner — `MatchProcCall` takes `argTypes` with no companion
array-ness, there is no `argIsArray` in the tree, and seven call sites across
two frontends would have to thread it).

**For this wall that means: chase argument 2 and nothing else.**

## Reductions that do NOT reproduce

Recorded so the next attempt does not re-run them. All match fpc 3.2.2:

- one nested routine with an `out` param capturing a scalar and a dyn array
- siblings where one calls the other, scalar- and array-capturing
- the above plus own parameters on the caller
- all of the above inside a class METHOD rather than a plain procedure
- `inline` on the callee

The one reduction that DID fire turned out to be a different defect
([[bug-p-a-nested-functions-bare-own-name-read-is-compiled-as-a-recursive-call]]),
because both print `no overload of <name>$<n> matches` with a mangled name and
a capture-shaped candidate list. **The error message cannot tell the two
apart.** Confirm any new reduction against `pparser.pp` itself before believing
it.

The untried axis, and the one the sibling-set differences point at: a
method-local `type` section, and a sibling that captures something the callee
does not.

## The other cause on this unit is CLOSED

`pparser.pp` was three errors from two causes and is now **one**.
`TPascalScanner.IndexOfResourceHandler`'s `.Name` lookup on a dynamic array's
record ELEMENT was the other cause, counted twice because the poison node typed
as Integer and the arity check then reported `CompareText` as well —
frank-coord-core closed it at `86852f93a` (element is a class AND the array is a
parameter; the param chain had `parr and tyRecord` but no `parr and tyClass`, so
array-of-class fell into the SCALAR arm and its element rec id went to
`RecName`, where `ResolveNodeRec` never looks).

Measured at binary `6950458c2da2`: `:2670` alone, 9.6s. **Count causes, not
errors** — this rung has now over-reported that way twice.


## CAUSE, measured 2026-09-07 at compiler `10b68db9ca4a`

**This ticket's standing hypothesis was wrong and is retracted here.** It read
that the `class` in position 2 "matches no name in its body -- the only
class-typed local of the enclosing method is `ExpStack: TFPList`, which
`PeekOper` never mentions but its SIBLING `PopExp` does." It is not `ExpStack`.
It is **`Result`**.

Added `PXXDBG p.lift`, which prints every lift descriptor as recorded — the
routine, whether it takes Self, and each captured name with its kind:

```
PXXDBG p.lift PopExp$62710   self=FALSE caps=2 : ExpStack(6) Result(6)
PXXDBG p.lift PushOper$62717 self=TRUE  caps=2 : OpStackTop(1) OpStack(5)
PXXDBG p.lift PeekOper$62727 self=FALSE caps=3 : OpStackTop(1) Result(6) OpStack(5)
PXXDBG p.lift PopOper$62734  self=FALSE caps=3 : Result(6) OpStackTop(1) OpStack(5)
```

`PeekOper` reads two free variables and has **three** captures. The third is
`Result`, kind 6 = class — `DoParseExpression` returns `TPasExpr`. `PeekOper`'s
own result is a `TToken`.

So the declaration is `PeekOper(OpStackTop: Integer, Result: CLASS, OpStack:
array)`, and the sibling call inside `PopOper` resolves the `Result` actual in
**PopOper's** scope, where `Result` is PopOper's own `TToken` — an Integer.
`(Integer, Integer, record)` against `(Integer, class, array of record)`, which
is the reported mismatch exactly, with argument 2 the only real one, as this
ticket already established for a different reason.

## Reduced — 26 lines, no corpus

```pascal
type TBox = class FV: LongInt; end;
function Outer: TBox;                 { enclosing returns a CLASS }
var top: LongInt;
  function PeekIt: LongInt;
  begin
    if top >= 0 then Result := top else Result := -1;   { its OWN Result }
  end;
  function PopIt: LongInt;
  begin
    Result := PeekIt;                                   { the SIBLING call }
    Dec(top);
  end;
begin top := 3; Result := TBox.Create; Result.FV := PopIt; end;
```

```
pascal26:18: error: no overload of PeekIt$23 matches these arguments
  argument types: (LongInt, LongInt)
  candidates:  PeekIt$23(LongInt, class)
PXXDBG p.lift PeekIt$23 self=FALSE caps=2 : top(11) Result(6)
```

**WHY EVERY EARLIER REDUCTION FAILED, and it is a named trap.** Make the nested
functions return the same type as the enclosing one and the program compiles and
prints the right answer — the spurious capture is still there, but its type
matches, so nothing can fail. That is
*"choose a probe whose right answer differs from the default"*: the wrong
capture and the right one are indistinguishable whenever the two result types
agree, and the obvious small reduction makes them agree.

## The SECOND defect, same cause

```pascal
function Outer: LongInt;
  function Inner: string;
  begin
    Outer := 99;         { the ENCLOSING function's name, in a nested FUNCTION }
    Result := 'inner';   { and its own Result }
  end;
```

| | |
| --- | --- |
| fpc 3.2.2 | runs; `outer Result = 99` |
| pxx | `pascal26:7: error: incompatible types: cannot assign Integer to AnsiString` |

`ParseNestedRoutine` rewrites the enclosing function's name to the token
`Result` — correct for a nested PROCEDURE, which has no result of its own, and
wrong for a nested FUNCTION, where that token now means something else.

## Why they must be fixed together

**Two different variables are spelled `Result`.** Excluding `Result` from the
capture set of a nested FUNCTION fixes the first defect and makes the second one
WORSE: `Outer := 99` would stop being a type error and start silently writing
`Inner`'s own result whenever the two types happen to agree. Trading a loud
wrong answer for a quiet one.

The fix is to give the enclosing result its own spelling inside a nested
routine, so each name means one thing:

- nested PROCEDURE — no result of its own, so `Result` and the enclosing name
  both mean the enclosing result. fpc confirms: a nested procedure's
  `Result := 42` is visible in the enclosing function afterwards (measured).
- nested FUNCTION — `Result` is its own and must not be captured; the enclosing
  NAME still refers to the enclosing result and needs the distinct spelling.


## FIXED — `14d483f74974`, and the "must be fixed together" claim was wrong

`ParseNestedRoutine`'s free-variable scan, `compiler/pasparser_decl.inc`, one
condition ahead of the capture logic:

```pascal
if (Tokens[nestedStart].Kind = tkFunction) and CaseEqual(nm, 'Result') then
begin
  Inc(i); Continue;
end;
```

`nestedStart` is the `procedure`/`function` token itself, so the discriminator
costs nothing and is exact. A nested PROCEDURE is untouched: it has no result of
its own, so its `Result` really is the enclosing function's and fpc confirms the
write survives the enclosing return.

**AND THE CAPTURED PARAMETER WAS DEAD.** Inside the lifted body the function's
own result shadows a parameter of the same name, so nothing ever read it —
measured before and after: a nested function's `Result := 7` leaves the
enclosing result untouched either way. This is a REMOVAL, not a behaviour swap,
which is the whole reason it can land alone.

### The section above headed "Why they must be fixed together" is RETRACTED

It reasoned that dropping the capture would turn defect 2 (`Outer := 99` in a
nested FUNCTION) from a loud type error into a silent mis-assignment. **It does
not, and the reason is the shadowing above** — `Outer := 99` was rewritten to
the token `Result`, which already bound to the nested function's own result and
never to the dead parameter. Measured on both compilers with the same 15-line
program:

| | |
| --- | --- |
| pin v407 | `pascal26:6: error: incompatible types: cannot assign Integer to AnsiString` |
| HEAD `14d483f74974` | *identical, byte for byte* |

A prediction about a behaviour change, refuted by running it. Filed as
[[bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results]]
(prio 55), which now carries the correct account of why it is not a one-liner:
the enclosing result needs its own spelling, and after this change there is no
lifted parameter to aim the rewrite at either.

A THIRD defect surfaced while building the fixture and is unrelated to capture:
`Outer.FV := 33` in ANY nested routine is read as a recursive CALL and spins
until it segfaults, because the enclosing-name rewrite is gated on the next
token being `:=`. Also identical on the pin.
[[bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses]] (prio 60).

## Verified

- **The corpus wall is gone.** `program X; uses pparser;` against
  `/usr/share/fpcsrc/3.2.2/packages/fcl-passrc/src` compiles clean at
  `14d483f74974` — 3.5s, `code=1031960B procs=1806`. The pinned compiler on the
  same command still prints `no overload of PeekOper$62727 matches these
  arguments / (Integer, Integer, record) / PeekOper$62727(Integer, class, array
  of record)`, this ticket's error exactly. Positive control, right population.
- **`test_nestownres26`** —
  `test/test_a_nested_functions_own_result_is_not_the_enclosing_ones.pas`, five
  rows identical to fpc 3.2.2. **The enclosing function returns a CLASS and the
  nested ones return LongInt on purpose**: make the two result types agree and
  the spurious capture becomes type-compatible and nothing can disagree with it,
  which is why every earlier reduction compiled cleanly. The pin refuses this
  file with the ticket's own error message.
- **`test_nestres26`** (the enclosing-name rewrite's existing control, including
  `Recurse := Recurse(k - 1) + 1`) unchanged and green.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9fe654f24.
