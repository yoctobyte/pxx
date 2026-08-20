---
track: P
prio: 30
type: compat
blocked-by: []
summary: "Every subrange type gets the 4-byte default instead of the smallest type that holds it: SizeOf(10..20) is 4 where FPC says 1, so a `packed record` of subranges is 12 bytes where FPC lays out 3. Values are all correct — this is a layout divergence, not a wrong-value bug, and it breaks binary interop and costs 4x memory."
status: backlog
---

# A subrange type is always 4 bytes

- **Track P** (Pascal frontend: subrange type sizing), tag **compat-pascal**.
- Found 2026-08-20 by an FPC differential probe over enums, sets and subranges.

## What differs

```pascal
type
  TSmall = 10..20;
  TNeg   = -5..5;
  TBig   = 0..70000;
  TR = packed record a: TSmall; b: TNeg; c: 0..255; end;
  TA = array[0..3] of TSmall;
```

| | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `SizeOf(TSmall)` | 1 | **4** |
| `SizeOf(TNeg)` | 1 | **4** |
| `SizeOf(TBig)` | 4 | 4 |
| `SizeOf(TR)` (packed) | 3 | **12** |
| `SizeOf(TA)` | 4 | **16** |

Every *value* agrees — `r.a`, `r.b`, `a[0]`, `Low`, `High`, `Ord`, `Succ`,
`Pred` all match. FPC picks the smallest integer type that spans the declared
range (Byte for `0..255`, ShortInt for `-5..5`, and so on); pxx gives every
subrange the 4-byte default.

## Why it is a compat item and not a bug

Nothing computes a wrong answer, and pxx is self-consistent: a program that only
ever reads and writes its own subranges cannot observe this. What it does cost:

- **binary interop** — a `packed record` written by an FPC program and read by a
  pxx one (or a `file of TR`, or a struct handed to C) has a different layout;
- **memory** — 4x for a large array of subranges, which is the whole reason a
  program declares `array[0..N] of 0..255` rather than `array of Integer`.

Both are real, and neither is silent wrong arithmetic, so this stays a compat
ticket rather than escaping to a `bug-` one.

## Sketch

The size decision wants the same treatment `AliasIsSub` / `AliasSubLo` /
`AliasSubHi` already give the bounds: pick the narrowest ordinal spanning
`lo..hi`, signed when `lo < 0`. The hazards are the ones the narrowing-cast work
already mapped — a narrower field means a narrower LOAD, so anything that
re-tags a load in place has to widen the value rather than the access (see the
notes in `ir.inc`'s `AN_PTR_CAST` arm) — and the range-check path, which must
keep using the DECLARED bounds, not the storage type's.
