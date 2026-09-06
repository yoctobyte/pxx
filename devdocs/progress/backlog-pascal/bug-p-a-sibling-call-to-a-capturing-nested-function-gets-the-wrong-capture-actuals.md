---
prio: 65
track: P
status: open
summary: "fcl-passrc rung 7's LAST remaining error on `pparser.pp` -- the unit went 3 -> 1 when frank-coord-core's `86852f93a` closed the `.Name`-on-a-dynamic-array-element cause (which was two of the three, one defect counted twice). `Result:=PeekOper;` at `pparser.pp:2670` -- a SIBLING call between two nested routines of `TPasParser.DoParseExpression`, both capturing -- reports `no overload of PeekOper$62727 matches these arguments / argument types: (Integer, Integer, record) / candidates: PeekOper$62727(Integer, class, array of record)`. **ARGUMENT 3 IS FINE AND ARGUMENT 2 IS THE WHOLE MISMATCH -- SETTLED by frank-coord-core 2026-09-06, do not reduce this believing two arguments are bad.** The `record` vs `array of record` asymmetry is a RENDERING defect, not a typing one: the candidate side is spelled IsArray-aware by `ParamSpellingForReport` and the argument side is not, so a perfectly matching array argument reads as a mismatch. Matching itself is correct -- both sides hold the ELEMENT kind and compare consistently. Filed separately as [[bug-p-the-two-halves-of-an-overload-report-spell-an-array-argument-differently]]. WHAT IS STILL UNEXPLAINED IS ONE THING, NOT TWO: the candidate has THREE hidden parameters where `PeekOper` reads only TWO free variables (`OpStackTop: Integer`, `OpStack: array of TOpStackItem`), with a `class` in position 2 that matches no name in its body -- the only class-typed local of the enclosing method is `ExpStack: TFPList`, which `PeekOper` never mentions but its SIBLING `PopExp` does. NOT the own-name-read defect: [[bug-p-a-nested-functions-bare-own-name-read-is-compiled-as-a-recursive-call]] was found while reducing this one, is fixed, and does NOT move this wall."
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
