---
slug: bug-a-64-bit-multiply-overflow-is-unchecked-under-q-plus-on-riscv32-and-xtensa
track: A
prio: 25
type: bug
blocked-by: []
status: backlog
found: 2026-09-01
found-by: frankA
owner: unassigned
summary: "{$Q+} does not catch a 64-bit*64-bit product that overflows Int64 on riscv32 or xtensa; x86-64 raises Runtime error 215. Both 32-bit backends print the wrapped value and carry on. Pre-existing on riscv32 (its own source says unsigned checked mul is deferred) and found while bringing xtensa to parity with it, so this is the gap they SHARE rather than anything new."
---

# 64-bit multiply overflow is unchecked under `{$Q+}` on riscv32 and xtensa

## The fact

```pascal
{$Q+}
var x, y, z: Int64;
begin x := 4000000000000000000; y := 4; z := x * y; WriteLn(z); end.
```

| target | result |
| --- | --- |
| x86-64 | `Runtime error 215 (arithmetic overflow)` |
| riscv32 | `1553255926290448384` — wrapped, no trap |
| xtensa | `1553255926290448384` — wrapped, no trap |

Note both wrong answers are **the same** wrong answer, which is the tell that
this is one shared mechanism and not two coincidences.

## Why it is separate from the narrowing-store check

32-bit overflow under `{$Q+}` IS caught on both, because Pascal widens the
arithmetic to Int64 and the wrap is caught at the narrowing store
([[bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently]]).
This case has **no narrowing** — destination and value are both Int64 — so the
store-side check cannot see it by construction. It has to be detected where the
64-bit product is formed.

## Where it would go

`EmitBinop64RISCV32` already takes `qchk`/`qchkUns` and handles checked add and
subtract of pairs; `tkStar` is the arm it does not check, and its own comment
records the deferral (*"unsigned checked mul stays deferred, like the 64-bit
pair path records"*). `EmitBinop64Xtensa` takes no `qchk` parameter at all and
would need one.

A 64×64 checked multiply needs the full 128-bit product, or an equivalent
pre-check on the operand magnitudes. On xtensa that is harder again: `muluh` is
UNSIGNED, so the signed high word must be reconstructed as
`hi_s = hi_u - ((l sar 31) and r) - ((r sar 31) and l)` — and under
`--xtensa-soft-mulhigh` there is no `muluh` instruction at all, so it becomes a
helper call inside an arithmetic operation.

## Ranking

Low deliberately. It needs an Int64 product past 2^63 with `{$Q+}` on, on a
32-bit cross target. Real, silent, and worth recording — but the 32-bit shapes
that reach it are the ones already covered. **Do not raise the prio to make it
visible**; it is reachable and correctly ranked, and both backends should be
done in one pass when someone takes it.
