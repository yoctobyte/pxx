---
track: A
prio: 25
type: feature
blocked-by: []
---

# `Extended` is silently an alias for `Double`

**User, 2026-08-10: "we also need to support extended in the future."** Filed
from the float-formatting discussion; deliberately not urgent.

## Measured (x86-64, `{$mode objfpc}`, HEAD `f20a7363d`)

| | FPC | pxx |
| --- | --- | --- |
| `SizeOf(Extended)` | **10** | **8** |
| `e := 1.0/3.0; WriteLn(e)` | `3.33333333333333333342E-0001` | `3.3333333333333331E-001` |

pxx accepts `Extended` and maps it to `Double`. It compiles, it runs, and it is
**silently less precise** — which is the part that matters: FPC code that uses
`Extended` deliberately (accumulators, iterative refinement, anything relying on
80-bit intermediates to avoid drift) gets a quietly worse answer with no
diagnostic. That is a compat trap, not merely a missing type.

## Scope, honestly

This is not a formatting change — it is a TYPE with 80-bit x87 semantics:

- **x86-64 only.** aarch64/arm32/riscv32/xtensa have no 80-bit format, so the
  alias is the only sane behaviour there and must stay. Any implementation is
  necessarily target-conditional, which also means `SizeOf(Extended)` becomes
  target-dependent — code that assumes 10 breaks on the cross targets exactly as
  it does on FPC's own non-x86 targets.
- **x87, not SSE.** pxx's float codegen is SSE-based; 80-bit needs the x87 stack
  (`fld`/`fstp` `tbyte`), a different register file and a different
  control-word/rounding story.
- **Storage is 10 bytes, alignment is not.** FPC pads to 16 in records/arrays on
  x86-64; get this wrong and every `Extended` field offset in a ported record is
  wrong.
- **The RTL surface**: `FloatToStr`, `Str`, `Val`, `WriteLn`'s formatter and the
  math routines all currently assume Double.

## Interim, cheap option worth considering first

If full 80-bit is not wanted soon, a **diagnostic** beats silence: warn (or
error under `--strict-fpc`) when `Extended` is declared on a target where it
aliases `Double`, so a port that depends on the precision finds out at compile
time instead of drifting. That is a small change and removes the trap without
the x87 work.

## Related

The default-output-format question for `Extended` (FPC prints 20 significant
digits and a 4-digit exponent) is deliberately postponed —
`rainy-day/decide-default-float-output-format-and-constant-precision`. Note that
question becomes moot for `Extended` if this lands, since the digits would then
be real rather than Double's rendered wider.

## Gate

`SizeOf(Extended) = 10` on x86-64 and `= 8` elsewhere; the 1/3 row matching FPC
to 20 significant digits; a record containing an `Extended` field laying out with
FPC-compatible offsets; `make test` + self-host byte-identical + cross.
