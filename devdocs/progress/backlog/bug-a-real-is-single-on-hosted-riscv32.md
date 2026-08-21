---
slug: bug-a-real-is-single-on-hosted-riscv32
track: A
prio: 35
type: bug
blocked-by: []
summary: "`Real` is Single (4 bytes) on hosted riscv32 Linux and Double (8) on every other target and on FPC. The type is keyed on the ARCH, not on the ESP profile, so a target with no ESP in it inherits an ESP decision — silently halving the precision of every `Real` in a ported program."
status: backlog
---

# `Real` is Single on hosted riscv32, Double everywhere else

## Measured (2026-08-21)

```pascal
program realsz; var r: Real; begin WriteLn('SizeOf(Real)=', SizeOf(r)); end.
```

| target | SizeOf(Real) |
| --- | --- |
| x86-64 | 8 |
| i386 | 8 |
| arm32 | 8 |
| aarch64 | 8 |
| **riscv32 (hosted Linux)** | **4** |
| FPC (oracle) | 8 |

## Cause

`pasparser_decl.inc:133` and `:271`, both spelled the same way:

```pascal
tkReal_T: if (TargetArch = TARGET_XTENSA) or (TargetArch = TARGET_RISCV32) then
            Result := tySingle   { Real = native float depth; ESP has no HW double }
          else
            Result := tyDouble;
```

The comment says **ESP**, and for xtensa the test is right — xtensa is always
ESP-class. For riscv32 it is not: riscv32 is dual-role (bare ESP32-C3 under
`--esp-profile=bare`, or hosted Linux otherwise), and the test omits the
profile. So `--target=riscv32` with no ESP flag anywhere gets the ESP answer.

Note the shape: this is the *unqualified* `xtensa or riscv32` spelling, the one
`TargetIsEspClass` (util.inc) deliberately does NOT cover, precisely because
these sites each need their own answer rather than a shared predicate.

## Why it is a bug and not a Track F item

Close call, and the charter says a close call is **not** F. F covers "precision
of a float TYPE", which this literally is — but F is for float accuracy work
(ulps, rounding, subnormals, fast-vs-exact tiers), and the defect here is that a
**declaration** resolves to the wrong type on one target because a condition
tests the wrong thing. The mechanism is a mis-keyed target test; the float
content is what it happens to be about. Rank the mechanism, never the datatype.

The consequence is also the silent-wrong-value kind rather than the last-digit
kind: a ported program's `Real` accumulators lose half their mantissa with no
diagnostic, and `SizeOf` disagrees with every other target, so a record laid out
with a `Real` field has a different size on riscv32 than on riscv64 will.

If the owner reads it the other way, it moves to `float/` unchanged.

## The fix is one decision, not one edit

Whether hosted riscv32 should get `Real = Double` is not obvious, which is why
this is filed rather than fixed:

- **For**: FPC parity, cross-target consistency, and hosted riscv32 already
  pulls the `softfloat` unit (`pasparser_prog.inc`), so double IS available —
  in software, correctly, just not fast.
- **Against**: it is *only* available in software. Making `Real` a Double
  silently routes every `Real` operation on this target through the soft-float
  kernels. That is the same trade the ESP decision made deliberately, recorded
  in [[decide-esp-single-depth-division-into-a-declared-double]].

The difference is that on ESP the trade is defensible (no OS, no FPU, tiny
part) and on hosted Linux it is a surprise. Recommend `Real = Double` on hosted
riscv32 for parity, with the soft-float cost accepted — and check whether
`decide-esp-single-depth-division-into-a-declared-double` already covers the
question, since these are the same call one target apart.

## Gate

`SizeOf(Real) = 8` on hosted riscv32 and unchanged (4) under
`--esp-profile=bare`, both under qemu; plus a `Real` arithmetic round-trip that
needs more than 24 bits of mantissa. Self-host byte-identical. Cross-target
breadth is Track T's.
