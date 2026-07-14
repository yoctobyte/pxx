---
summary: "qword -> double conversion treats the value as SIGNED: q >= 2^63 converts to a negative double"
type: bug
prio: 45
---

# `double(q)` / implicit qword→double converts as signed for values ≥ 2^63

- **Type:** bug (silent wrong value). **Track A** (IR float-conversion lowering,
  all backends).
- **Status:** working
- **Opened:** 2026-07-14
- **Found by:** tint642.pp burn-down (testqwordtypecast, `do_error(20)`) while
  resolving [[bug-pascal-record-cast-field-offset]].

## Repro

```pascal
var q: qword; d: double;
begin
  q := qword(1) shl 63;      { $8000000000000000 }
  d := q;
  writeln(d);                { FPC: 9.223372036854775808E+18 }
                             { pxx: -9.2233720368547758E+18 (signed cvt) }
  if q <> 2.0*double($80000000)*double($80000000) then writeln('BAD');
end.
```

`cvtsi2sd` (and its cross equivalents) is a SIGNED conversion; an unsigned
64-bit source with the top bit set needs the unsigned fixup (test top bit →
halve, convert, double — the standard u64→f64 sequence) or a range-based
branch. Mixed qword/double COMPARISONS convert the qword operand the same way,
so they inherit the bug.

## Impact

- tint642.pp (FPC testsuite) fails at error 20 — this is now the ONLY residual
  blocking it (record-cast field offsets and bitwise `not (q or q)` landed
  tonight; skip-list entry points here).
- Any program mixing qwords ≥ 2^63 with floating point gets silently wrong
  values on every backend.

## Acceptance

- Repro matches FPC on x86-64 + cross targets.
- tint642.pp passes and drops from `test/pascal-conformance/pxx.skip`
  (check the rest of the test runs green past error 20 — it is a torture test,
  more walls may hide behind this one).
