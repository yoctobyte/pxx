# RTL gaps — string/number conversion + a bit-set type (surfaced by the demos)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (from the Sudoku + Prime-sieve demo apps)
- **Relation:** sibling to feature-random-library and feature-writeln-as-library
  — the reusable-RTL lane. The demo apps in `examples/` are the motivating
  tests: written "platonically" (assume idiomatic RTL exists), so the missing
  routines below are the gaps the demos expose by design. Companion to
  feature-demo-sudoku.

## Motivation

Two new platonic demo apps were written to exercise the surface, deliberately
without workarounds:

- `examples/sudoku/sudoku_game.pas` — interactive generator + line-oriented UI
  (desktop terminal / ESP32 serial). Uses `Val` to parse `r c v` moves.
- `examples/primes/sieve.pas` — Sieve of Eratosthenes with hand bit-packing
  into an `array of Integer`. Uses `IntToStr` to render primes.

They compile against an idiomatic RTL surface that does not yet exist. Rather
than hand-roll the conversions in each app, capture the gap here.

## Gap 1 — number/string conversion (a SysUtils/StrUtils slice)

Missing, both demos and essentially every real app want them:

- `IntToStr(n)` / `IntToStr` for the integer widths
- `Val(s, v, code)` — standard parse with an error code (the FPC-compatible form)
- `StrToInt(s)` / `StrToIntDef(s, def)`
- adjacent: `Trim`, `UpperCase`/`LowerCase` likely fall out of the same unit

FPC-compatible signatures so existing/Lazarus code is unaffected. Deterministic,
integer-only core → byte-identical across all targets (good cross-target oracle).

## Gap 2 — a bit-set / bit-array type (TBitArray-ish)

The sieve packs bits by hand (`w := n div 32; bits[w] := bits[w] or (1 shl b)`).
That is fine as a demo of raw `shl/and/or` codegen, but the reusable type is
wanted:

- dynamic, length-set bit vector over packed machine words
- `SetBit` / `ClearBit` / `TestBit`, `Count` (popcount), iteration
- the right primitive for sieves, candidate sets, presence maps

Naming/shape TBD (TBitArray vs a `bitset` unit) — decide when picked up. Watch
the `set of 1..9`-from-runtime-values gap noted in feature-demo-sudoku; a proper
bit-set type may be the pragmatic answer to that lane too.

## Constraints

- Per memory: write our OWN units with FPC naming; do NOT port real FPC RTL/LCL.
  These libs get cleaner as the compiler gains features.
- `.pas` units, not `.inc` (per the .inc→units direction).
- Must not regress the self-host fixedpoint or cross-bootstrap.

## Acceptance

- `sudoku_game.pas` and `sieve.pas` compile and run unmodified against the new
  units, byte-identical across x86-64 / i386 / aarch64 / arm32.
- Conversion routines: scripted input → fixed output oracle in `make test`.
- Bit-set: a sieve built on the type matches the hand-packed sieve's prime count.

## Log
- 2026-06-19 — Opened from the two demo apps. Gaps confirmed: `IntToStr` and
  `Val` referenced by name in neither test nor lib (`grep` clean), i.e. not yet
  provided. Demos left platonic on purpose to drive this ticket.
- 2026-06-20 — **Gap 1 expanded** (track B): `lib/rtl/sysutils.pas` gained
  `FloatToStr`, `FloatToStrF`, `StrToFloatDef`, `StrToFloat`, `Pos`, `PadLeft`,
  `PadRight`, `Delete`, `Insert`, `Concat`. Float conversion avoids the `Str`
  builtin (which breaks when sysutils's own `Copy` shadows the compiler's
  intercept). `Val` still absent (builtin name collision); `StrToFloatDef` is
  the replacement.
- 2026-06-20 — **Gap 2 landed** (track B): `lib/rtl/bitset.pas` ships
  `TBitArray` with `BitArrayInit`, `BitArraySetBit`, `BitArrayClearBit`,
  `BitArrayToggle`, `BitArrayTestBit`, `BitArrayCount`, `BitArrayNextSet`.
  Uses 32-bit Integer words (Int64 bitwise ops — `not`, `and` on sign-bit
  values — are unreliable on the pinned stable). `shr` on negative Integer is
  arithmetic (sign-extending), so NextSet uses direct bit-index scanning.
  `BitArrayClearBit` avoids `not` via conditional subtraction. Tested in
  `test/lib_bitset.pas` with golden-output verification (`make lib-test`).

  **Compiler gaps discovered:**
  - `not` on Integer is boolean, not bitwise — cannot be used for mask
    complement
  - `shr` on negative Integer is arithmetic shift (sign-extending), not
    logical — breaks bit-scanning on words with bit 31 set
  - Int64 `and`/`or`/`not` are unreliable — 32-bit Integer is the safe word
    type for now
  - `ba.bits := nil` on a managed record field through `var` param segfaults
