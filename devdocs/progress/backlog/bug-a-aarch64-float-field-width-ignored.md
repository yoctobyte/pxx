---
track: A
prio: 45
type: bug
summary: "aarch64 ignores the field WIDTH in writeln(d:w:n) — `writeln(x:10:4)` prints `3.1416` where FPC and x86-64 print `    3.1416`. Pre-existing; the aarch64 emitter never took a width parameter at all"
---

# aarch64: `writeln(d:width:decimals)` drops the width

- **Type:** bug — Track A (aarch64 float output)
- **Status:** backlog
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
