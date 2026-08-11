---
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-A
---

# An Integer-valued BINOP argument binds the Double overload, not the Integer one

- **Type:** bug (wrong overload chosen; silently different answer) — **Track A**
- **Found:** 2026-08-11 while fixing
  [[bug-a-an-integer-argument-binds-a-fixed-array-overload]] (which was hiding
  it: the array overload used to swallow the same call).
- **Pre-existing on `pinned`** (controlled).

```pascal
{$mode objfpc}
function Sum(x: Integer): Integer; overload; begin Sum := x * 10; end;
function Sum(x: Double): Integer;  overload; begin Sum := Trunc(x) + 1000; end;
var n: Integer;
begin
  n := 5;
  WriteLn(Sum(n));     { FPC 50   — pxx 50   }
  WriteLn(Sum(n + 1)); { FPC 60   — pxx 1006 }
  WriteLn(Sum(7));     { FPC 70   — pxx 70   }
  WriteLn(Sum(2.5));   { FPC 1002 — pxx 1002 }
end.
```

Only the BINOP row diverges: a plain variable and a literal both bind Integer,
`n + 1` binds Double. So the argument type an arithmetic expression reports is
not the one an exact match needs — presumably a widened kind (tyInt64 /
tyNativeInt) that misses the Integer parameter in Phase 1 and then lands in a
compatible phase where Double accepts it.

## Where to start

`MatchProcCall` in `symtab.inc`: Phase 1 is exact-only, and the compatible
phases that follow rank by fit. Either the binop's result kind should narrow
back to the operands' kind when both are Integer, or the compatible phase needs
to prefer an integer parameter for an integer-valued argument over a float one.
Measure the actual `argTypes[]` value for `n + 1` first — do not assume which
kind it is.

Related, same family: `project_overload_resolution_single_side_channel_entry`
(per-argument facts belong in the MatchArg* side channel, not in argTypes).

## Gate

The program above matching `fpc -O1`; `test/test_overload_array_vs_scalar.pas`
still green; self-host byte-identical.

## Resolution (2026-08-11) — the rule is broader than the ticket's repro

Measured against `fpc 3.2.2` first, because the repro only showed the BINOP row
and the real rule is not about binops at all: **an integer-valued argument
prefers an INTEGER parameter over a FLOAT one, and that holds even when the
integer parameter NARROWS.** `f(Integer)` vs `f(Double)` takes Integer for an
Int64 argument; `f(Byte)` vs `f(Double)` takes Byte for an Integer argument.
pxx had no such preference at all, so Phase 1d — which ranks purely by
losslessness, and a float parameter never "narrows" an integer — handed those to
the float overload. `n + 1` was merely the row where the argument is wide enough
for the narrowing to matter, which is why it looked like a binop bug.

Fixed as a new phase pair before Phase 1d, since losslessness still ranks WITHIN
the integer candidates: pass 0 takes an integer parameter that does not narrow
(so `f(Integer)`/`f(Int64)` with an Int64 argument still binds Int64), pass 1
then takes a narrowing integer parameter ahead of any float one. New
`TypeIsMachineInt` deliberately excludes Boolean/Char/Pointer/Bool8/UCS4Char —
ordinals that take no part in integer-vs-float ranking — and the promo kinds,
which have their own lossless rules in `ArgNarrowsInt`.

Verified against `fpc -O1`: all three overload truth tables (Integer/Double,
Byte/Double, Int64/Double) and the integer-vs-integer control (Integer/Int64)
now match row for row, on x86-64 and all four cross targets.

**Full `test/*.pas` sweep, HEAD vs `pinned`: 1023 files, 12 diffs, no
regression** — 9 are environmental (timestamps, PIDs, a socket bind race, a
binary name inside a loader error) and 3 are `pinned` predating a fix
(`test_stmt_call_result_deref_b387`, `test_write_char_field_width`,
`test_variant_part_string_field`). A sweep this wide was worth it: overload
resolution is consulted by every call in every library.

New `test/test_overload_int_prefers_int.pas`.

## Log
- 2026-08-11 — resolved, commit 82a5c65a5.
