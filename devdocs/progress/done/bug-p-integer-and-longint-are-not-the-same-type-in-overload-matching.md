---
summary: "`Integer` and `LongInt` are one type but carry distinct TypeKinds, so overload resolution's exact phase discriminated on the spelling — `IntToHex(i: integer, 8)` bound the Int64 overload and printed 16 digits where FPC prints 8"
type: bug
prio: 45
track: P
---

# `Integer` vs `LongInt`: the same type lost the exact overload match

- **Type:** bug (overload resolution, `compiler/symtab.inc` `MatchProcCall`).
  Track P / shared core (sole-A confirmed).
- **Status:** done
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (sysutils
  topic) — `IntToHex(-1, 8)` came back sixteen digits wide.

## Symptom

```pascal
var i: integer; li: longint;
begin i := -1; li := -1;
  writeln(IntToHex(i, 8));    { FPC FFFFFFFF   pxx FFFFFFFFFFFFFFFF }
  writeln(IntToHex(li, 8));   { FPC FFFFFFFF   pxx FFFFFFFF         }
```

sysutils declares `IntToHex` three times — `Int64`, `LongInt`, `LongWord` —
precisely so a 32-bit value renders eight digits and not sixteen, and the
`LongInt` body already masks correctly. So the library was right and the
binding was wrong: `longint` hit the exact-match phase, `integer` fell past it
into the compatible phases and bound `Int64`.

Root cause: `integer` types as `tyInteger` and `longint` as `tyInt32` — the
same 4-byte signed type wearing two kinds (FPC declares one as the other's
alias) — and the exact phase compared kinds directly, so it discriminated on
the **spelling**. `integer` is the far more common spelling, which is what made
the wrong half the visible one.

## Fix

`MatchParamExact(paramTk, argTk)` — the exact-match test used by Phase 1 and
Phase 1b — treats `tyInteger` and `tyInt32` as one. A unit cannot legitimately
declare both overloads (FPC rejects the pair as duplicate), so unifying them
cannot make a previously-unambiguous call ambiguous. The ranking phases below
are untouched.

## Residuals (both deliberate, both measured)

- `smallint` still binds `Int64` where FPC binds `LongInt`, because FPC's
  narrowest-that-fits rule lives behind `--strict-overload-width`: the widening
  is the dialect by decision (user, 2026-08-14,
  [[compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload]]).
- `IntToHex(-2147483648, 8)` prints `FFFFFFFF80000000` where FPC prints
  `80000000`: the literal at Integer's exact minimum types as Int64 here
  (`2147483648` exceeds maxint before the unary minus folds). A separate,
  narrower literal-typing question — not this ticket, and filed nowhere yet
  because it needs a decision on when the negation folds.

## Gate

`make compiler/pascal26` fixedpoint; `tools/gate.sh quick` GREEN;
`test/test_integer_longint_overload.pas` (IntToHex across integer/longint/
cardinal/int64 plus a hand-written three-way overload set proving which one
each spelling binds) matches `fpc -O- -Mobjfpc` byte for byte. Six earlier
sweep probes (sysutils strings, strings/Copy, records, exceptions, OOP
dispatch) re-run unchanged.
