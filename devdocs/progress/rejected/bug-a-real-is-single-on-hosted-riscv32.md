---
slug: bug-a-real-is-single-on-hosted-riscv32
track: A
prio: 35
type: bug
blocked-by: []
summary: "`Real` is Single (4 bytes) on hosted riscv32 Linux and Double (8) on every other target and on FPC. The type is keyed on the ARCH, not on the ESP profile, so a target with no ESP in it inherits an ESP decision — silently halving the precision of every `Real` in a ported program."
status: rejected
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

---

## Rejected by the owner (2026-08-27) — the premise is wrong

Ruling, verbatim:

> real being native (4-byte/single) float on esp32 is _intended_ behaviour.
> this was discussed long ago. ticket didnt read the docs - or we never
> documented this properly. obviously sizeof(real) should be reported properly.

`Real` is **not** a portable alias for `Double` in this dialect. It names the
target's native float depth, and on xtensa and riscv32 that is Single. So the
table in "Measured" above is not a bug report — it is the design, correctly
implemented. Every recommendation this ticket makes ("Recommend `Real = Double`
on hosted riscv32 for parity") would have broken it.

Two things this ticket got wrong, both worth naming because they are repeatable
mistakes rather than bad luck:

1. **It ranked FPC parity above the dialect decision.** CLAUDE.md's ceiling says
   we compile correct Pascal correctly; we do not mimic FPC. "FPC says 8" is
   evidence about FPC, not about us. A deliberate divergence looks exactly like
   a defect from inside a differential probe, which is why the probe's output is
   a question and never a verdict.
2. **It read the target test as a mis-keyed condition.** The `xtensa or riscv32`
   spelling was real and load-bearing; `TargetIsEspClass`'s own header had
   already listed **"Real is Single"** among the concepts that share that
   spelling without being the same concept. The ticket cited that header and
   still concluded the site had forgotten a profile.

The second one nearly landed. Acting on this ticket, `Real` on hosted riscv32
was changed to Double and the change was built and measured before the owner
stopped it — a self-inflicted dialect change with a green gate behind it.

### What was real, and where it went

One line of this ticket was pointing at something: `SizeOf` disagreeing across
targets. Not because `Real` was the wrong width, but because `SizeOf(Real)`
**reported** 8 on a target where the variable occupied 4 — two tables in the
compiler carried the rule and only one of them was target-aware. That is a
genuine silent-wrong-value bug, and it is the one the owner named. Split out,
fixed, and closed as
[[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]].

### The documentation half

`docs/language/types.md` said `Real` was an "alias of `Double`", flatly, with no
target qualification — so the ticket's author read the docs and the docs agreed
with them. The owner allowed for exactly this ("or we never documented this
properly"). Rewritten as part of the split-out fix: `types.md` now carries the
per-target table and the rationale, `docs/targets/esp32.md` states it where an
ESP user will actually hit it, and `fpc-compatibility.md` lists it among the
deliberate divergences.

Not moved to `float/`: the charter question this ticket raised for itself is
moot once the premise is gone.
