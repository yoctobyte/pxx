---
summary: "{$R+} range checks (RE 201 / ERangeError): narrowing assignments + array index bounds — the counterpart to the landed {$Q+}"
type: feature
prio: 55
---

# {$R+} / {$RANGECHECKS ON}: runtime range checking

- **Type:** feature (FPC-parity runtime checks). **Track A.**
- **Status:** backlog
- **Opened:** 2026-07-15 night, straight out of the {$Q+} arc
  ([[feature-pascal-overflow-checks-q-plus]] — subword probing showed
  truncation is {$R+} territory, then the oracle probe found pxx's gap
  demonstrating itself: under {$R+}, `a[4] := 1` on `array[1..3]` silently
  clobbered the NEXT VARIABLE while FPC raised ERangeError).

## Oracle (FPC 3.2.2, probe kept in the ticket)

```pascal
{$R+}
i := 256;  b := i;          { byte dest: ERangeError }
i := 4;    a[i] := 1;       { array[1..3]: ERangeError }
i := -1;   b := i;          { ERangeError }
{$R-}
i := 300;  b := i;          { wraps quietly: 44 }
```
FPC caught=3. pxx today: all three proceed; the OOB store corrupts the
neighbour (caught printed 1 BECAUSE a[4] overwrote it).

## Design — mirror the proven {$Q+} machinery

- **Directive:** the lexer ALREADY disambiguates `{$R+}`/`{$R-}` from
  resource includes (lexer.inc ~1384) but discards the value — wire
  `RChecksVal` + per-token `TokRChecks` (the TokPackRecords pattern, exactly
  like TokQChecks).
- **Narrowing assignment:** parser tags AN_ASSIGN when the DEST's ordinal
  width < the promoted width and the token region has R+ (a parallel
  ASTRChk, AllocNode-reset + CloneAST-copied). IR/codegen: before the
  store, compare against the dest type's [lo, hi] (signed/unsigned by dest
  tk) and call a new PXXRangeError (builtinheap mirror of PXXOverflow:
  'Runtime error 201', Halt(201); sysutils hook raises ERangeError —
  the hook pair pattern is already there twice).
- **Array index:** IR_INDEX carries lo + element count is derivable at the
  tag site — emit bounds compare when tagged. Static arrays first; dyn
  arrays have Length at [handle-8] (FPC checks those too — probe first!).
- **Contract per meta-dialect ticket:** default OFF (lax dialect keeps
  today's behaviour), lexically scoped, oracle-verify EVERY sub-behaviour
  against FPC before implementing (the {$Q+} arc hit two doc-vs-oracle
  mismatches: Abs/Sqr and subword are NOT checked by FPC).

## Acceptance

- The probe matches FPC (caught=3, lax wraps).
- tclass5.pp's "range-check error 210" note and any skip-list entries
  keying on range checks get re-triaged after landing.
- x86-64 first; cross legs follow the {$Q+} porting pattern.
