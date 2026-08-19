---
track: A
prio: 40
type: bug
blocked-by: []
summary: "A typed const array is emitted as BSS plus generated code that fills it element by element at startup, instead of being stored as initialised data. Measured at ~29 bytes of code per element for UInt64; Int64, Double and Cardinal all do it too, so it is every typed const array, not a 64-bit case. A 696-entry table costs 20 KB of code and 0 bytes of data. A string constant of the same bytes costs ~0 code and lands in .data, so the data path exists — the array lowering just does not use it."
---

# A typed const array is built by startup code, not stored as data

- **Type:** bug (codegen / const lowering) — **Track A**.
- **Filed:** 2026-08-19 by frank3-b, from
  [[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]], where
  Eisel-Lemire's 696-entry power-of-ten table cost **+42 KB of code** in every
  binary that links `sysutils` — about 31 KB more than the table's own bytes.

## The bug

A typed constant array does not become initialised data. It becomes a BSS
reservation plus generated code, one store per element, run at program start.
Cost measured at **~29 bytes of code per element** for `UInt64`, plus the
startup time to run it, in **every** binary — including one that never reads
the array.

**Not specific to 64-bit types.** Same 696-element shape, same result — `data`
never moves and the storage is uninitialised BSS:

| element type | code delta vs 1-element | data | bss delta |
| --- | --- | --- | --- |
| `UInt64` | +20,152 | unchanged | +5,560 (695 x 8) |
| `Int64` | +16,680 | unchanged | +5,560 |
| `Double` | +20,228 | unchanged | +5,560 |
| `Cardinal` | +15,986 | unchanged | +2,776 (694 x 4) |

## Repro — two programs differing only in element count

```pascal
program tsz0;
const T: array[0..0] of UInt64 = ($1);
var s: UInt64; i: Integer;
begin s:=0; for i:=0 to 0 do s:=s+T[i]; writeln(s<>0); end.
```

versus the same with `array[0..695]` and 696 literals.

| | code | data | bss |
| --- | --- | --- | --- |
| 1 element | 54,204 | 1,560 | 9,512 |
| 696 elements | 74,356 | 1,560 | 15,072 |
| delta | **+20,152** | **0** | +5,560 |

`+5,560` bss is exactly `695 * 8`, so the storage is reserved but uninitialised;
`data` does not move at all; and `+20,152` code over 695 extra elements is
**29 bytes per element** of fill-in-at-startup.

## The data path exists — a string constant uses it

The same 5,568 bytes written as an `AnsiString` constant of `#nn` escapes:

| | code | data |
| --- | --- | --- |
| baseline | 54,204 | 1,560 |
| 696 u64 as a string const | 54,217 | 7,144 |

**+13 bytes of code and +5,584 of data.** So the backend can and does place
constant bytes in `.data`; the typed-array lowering simply does not take that
route.

## Why it matters beyond one table

Any lookup table — CRC tables, codec tables, trig tables, the power-of-ten
table that prompted this — pays 4x its own size in code and a startup pass. It
also puts a real thumb on the scale against writing table-driven code at all,
which is the wrong incentive: the natural, readable spelling is the one being
penalised.

It is worst for the targets least able to afford it. On ESP32/xtensa a 10 KB
table becomes ~40 KB of flash plus boot-time stores.

## Not worked around, deliberately

`lib/rtl/sysutils.pas` keeps the plain const array. Re-encoding the table as a
string blob to dodge this would have hidden the bug and made the table
unreadable, which is exactly what
`CLAUDE.md`'s platonic-code rule forbids. The cost is recorded in that unit's
header instead. **When this is fixed, sysutils gets ~31 KB smaller with no
change to its source** — worth re-measuring then as the check that the fix
landed.

## Suggested check when fixing

The table above is the regression check — every one of those `code` deltas
should collapse to roughly the element bytes moving into `data`. Also confirm
the array lands in a **read-only** section where the target supports one, since
nothing may write to a typed constant.
