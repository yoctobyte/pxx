---
track: A
prio: 45
type: bug
summary: "On i386 and arm32 ONLY, `WriteLn(anInt64:12)` prints the digits with NO padding, where x86-64, aarch64 and FPC all pad to 12. A 32-bit Integer with the same width pads correctly on the same targets, so it is the 64-bit write path specifically. Silent formatting corruption — columns simply do not line up, on two targets."
---

# i386 / arm32 ignore the field width when writing an Int64

- **Type:** bug (silent wrong output, two targets) — **Track A** (the per-backend
  integer writers in `compiler/emit.inc`).
- **Found** 2026-08-15 while fixing
  [[bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes]]: after that
  fix made aarch64 byte-identical to x86-64, the same sweep showed i386 and
  arm32 differing on a line the original repro never contained. Separate defect,
  separate targets, separate mechanism — filed rather than folded in.

## Measured

```pascal
var a: Int64; i: Integer;
begin
  a := 12345;  i := 12345;
  WriteLn('int64_w =[', a:12, ']');
  WriteLn('int32_w =[', i:12, ']');
end.
```

| target | `int64_w` | `int32_w` |
| --- | --- | --- |
| x86-64 | `[       12345]` | `[       12345]` |
| aarch64 | `[       12345]` | `[       12345]` |
| **i386** | **`[12345]`** | `[       12345]` |
| **arm32** | **`[12345]`** | `[       12345]` |
| FPC 3.2.2 | `[       12345]` | `[       12345]` |

Same for a negative value (`-12345:12`). The 32-bit `Integer` pads correctly on
the very same targets and in the very same statement, so this is not the width
plumbing in general — it is what the **64-bit** operand path does with it.

## Why it is worth more than it looks

Padding is what makes columnar output line up, so the failure is a table that
silently loses its shape on two targets and nowhere else — no crash, no
diagnostic, and a green gate, because nothing in the suite prints a
width-formatted Int64 and compares across targets.

## Where to look

`compiler/emit.inc`: `EmitwriteIntWArm32` / `EmitwriteUIntWArm32` and the i386
equivalents. The aarch64 pair (`EmitwriteIntWA64`) is a working reference for
the shape — it computes `padding = width - digits - sign`, writes the spaces,
then the sign, then the digits. Confirm what the 32-bit IR_WRITE arm actually
CALLS for a 64-bit operand before editing: it may be reaching a non-W writer
entirely (which would explain a width that vanishes rather than one computed
wrongly), and that is a one-line dispatch fix rather than an emitter rewrite.

## Gate

The table above reads padded on all four targets, matching FPC, for positive,
negative, `Low(Int64)` and `High(Int64)`, plus `gate.sh quick` + self-host
fixedpoint.
