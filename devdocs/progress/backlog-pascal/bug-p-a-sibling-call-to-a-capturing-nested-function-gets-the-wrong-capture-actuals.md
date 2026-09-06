---
prio: 65
track: P
status: open
summary: "fcl-passrc rung 7's last frontend wall on `pparser.pp`. `Result:=PeekOper;` at `pparser.pp:2670` -- a SIBLING call between two nested routines of `TPasParser.DoParseExpression`, both capturing -- reports `no overload of PeekOper$62727 matches these arguments / argument types: (Integer, Integer, record) / candidates: PeekOper$62727(Integer, class, array of record)`. TWO THINGS ARE UNEXPLAINED AND ONE IS A LEAD, NOT A FINDING: the candidate has THREE hidden parameters where `PeekOper` reads only TWO free variables (`OpStackTop: Integer`, `OpStack: array of TOpStackItem`), with a `class` in the middle that matches no name in its body -- the only class-typed local of the enclosing method is `ExpStack: TFPList`, which `PeekOper` never mentions; and the third argument prints as `record` on the call side against `array of record` on the candidate side, which is the SHAPE of the parameter-kind union (`Params[j].TypeKind` is the ELEMENT kind when `IsArray`) being read raw by one printer and IsArray-aware by the other -- if that is what it is, argument 3 is FINE and the diagnostic is lying about which argument is wrong. NOT the own-name-read defect: [[bug-p-a-nested-functions-bare-own-name-read-is-compiled-as-a-recursive-call]] was found while reducing this one, is fixed, and does NOT move this wall."
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
2. **`record` vs `array of record` on argument 3.** If that is the parameter-
   kind union (`ParamOwnKind` / `ParamElemKind` / `ParamStoredKind`, 142 raw
   readers still in IR+lowering per
   `refactor-p-a-parameters-own-kind-and-element-kind-share-one-field`), the
   two sides are printed by different code and argument 3 is not the defect.
   **Settle this before reducing anything**, or the reduction chases a
   correctly-typed argument.

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

## The other two errors on this unit

`pparser.pp` is at THREE errors from TWO causes. The other cause is one defect
counted twice — `TPascalScanner.IndexOfResourceHandler` does
`CompareText(aExt, FResourceHandlers[Result].Name)`, the `.Name` lookup on a
dynamic array's record ELEMENT fails, the poison node types as Integer, and the
arity check then reports `CompareText` as well. **Count causes, not errors**;
this rung has already over-reported once that way.
