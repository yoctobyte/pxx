---
track: A
prio: 45
type: bug
summary: "aarch64 ignores the field WIDTH in writeln(d:w:n) — `writeln(x:10:4)` prints `3.1416` where FPC and x86-64 print `    3.1416`. Pre-existing; the aarch64 emitter never took a width parameter at all"
owner: claude-A
---

# aarch64: `writeln(d:width:decimals)` drops the width

- **Type:** bug — Track A (aarch64 float output)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track A, while shimming the aarch64 float emitters for
  `bug-a-writeln-nonfinite-float-aarch64-emitters-unchecked`. **Pre-existing** —
  the `pinned` compiler drops the width identically, so it is not from that
  change.

## Repro

```pascal
var d: Double;
begin
  d := 3.14159; writeln(d:10:4);
  d := -2.5;    writeln(d:8:3);
end.
```

| | `d:10:4` | `d:8:3` |
| --- | --- | --- |
| FPC | `    3.1416` | `  -2.500` |
| pxx x86-64 | `    3.1416` | `  -2.500` |
| **pxx aarch64** | **`3.1416`** | **`-2.500`** |

The digits are right; only the left-padding to the field width is missing.

## Cause

x86-64's emitter is `EmitWriteFloatFixed(wid, decs)` — it takes the width. The
aarch64 twin was declared `EmitWriteFloatFixedA64(decimals: Integer)` and never
received one, so there was nothing to pad with. The call site passes only
`decs`.

The same gap exists in the portable helper it now shims onto:
`PXXWriteFloatFixed(p: Pointer; decimals: NativeInt)` has no width parameter
either, and its own comment on the Sci path notes "field-width padding for
64-bit values is not yet wired". So **i386, arm32 and riscv32 have this too** —
they route through the same helper. Only x86-64 pads.

## Fix

Add the width to `PXXWriteFloatFixed` (and `PXXWriteFloatSci`, which has the
same note) and pass it from every backend, then x86-64's native emitter can
shim onto it as well and the last hand-written copy goes away. Padding is
left-justified spaces to `width` when the rendered text is shorter — the rule
x86-64 already implements.

Doing it in the runtime rather than per-backend is the point: this is the fourth
float-output defect traced to the same "N copies of one formatter" shape.

## Related

- `bug-a-writeln-float-exponent-form-not-correctly-rounded` — collapsed the Sci
  formatters to one; this is the same treatment for the Fixed pair.
- `bug-a-x86-64-writeln-fixed-saturates-at-int64` — the other half of the
  x86-64/aarch64 disagreement found in the same run.

## Resolution (2026-08-05)

`PXXWriteFloatFixed` gained a `width` parameter and every backend now passes its
own. That fixed the reported bug and, as the ticket predicted, let the last
hand-written float formatter go: **x86-64 now has none.**

- **Runtime:** the padding is computed **after** the rounding, because a carry
  out of the fraction (`9.96:6:1` -> `10.0`) gains an integer digit and padding
  counted first would emit one column too many. The digit count is taken in
  double arithmetic, not through Int64 — this routine exists precisely because
  values past 2^63 must work.
- **Call sites:** `EmitFloatCallWriter386` / `...Arm32` / `...A64` and the
  riscv32 inline sequence all take and forward the width. (riscv32 names its
  width `j` and its decimals `i`, which is worth knowing before editing there.)
- **x86-64:** `EmitWriteFloatFixed` is now a shim, so
  `bug-a-x86-64-writeln-fixed-saturates-at-int64`'s remaining `width > 0` case
  is closed too. `EmitWriteFloatFixedNative` stays only as the RTL-less fallback
  for the esoteric probe frontends, same as the scientific one.

### Verified

All four runnable targets byte-identical to FPC on ten width cases: plain and
negative padding, the rounding carry, `:5:0` on 0.5 and -0.5, width SMALLER than
the content (no truncation), zero, `1e20`/`-1e20` at `:30:2` (past 2^63), and no
width at all. Also identical on the pre-existing float suites.

`testmgr --tier native` **1158/1158 pass**, including the self-host fixedpoint.
Locked in as `test/test_writeln_float_width.pas`.

### The thread this closes

Four tickets tonight were one root cause — a formatter written N times whose
copies drifted: `writeln` and `Str` disagreeing, aarch64 printing a wrong NUMBER
for Inf, x86-64 saturating at Int64, and this missing width. Four copies at the
start, one now.

## Log
- 2026-08-05 — resolved, commit 37f880f46.
