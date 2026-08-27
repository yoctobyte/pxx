---
slug: bug-a-xtensa-cannot-lower-an-int64-to-float-conversion
track: A+S
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "`var q: Int64; d: Double; d := q;` is refused outright on xtensa: `target xtensa: Int64-to-float conversion not yet supported`. riscv32 lowers the same source through __pxx_l2d / __pxx_ul2d and every hosted target handles it natively, so xtensa is the one target where a widening conversion between two types it fully supports has no path at all."
---

# xtensa cannot lower an Int64-to-float conversion

## Repro

```pascal
program q;
var q: Int64; d: Double;
begin q := 1000000; d := q; end.
```

```
$ ./compiler/pascal26 --esp-profile=bare --target=xtensa q.pas /tmp/o
pascal26:3: error: target xtensa: Int64-to-float conversion not yet supported
```

`--target=riscv32 --esp-profile=bare` compiles it. So does every hosted target.

## Why it is a real gap, not an MCU nicety

Both types are fully supported on xtensa on their own — an `Int64` variable, a
`Double` variable, and arithmetic on each work. It is only the conversion
between them that has no arm, so ordinary portable code compiles everywhere and
stops here. A tick counter widened into a float for a rate, a millisecond
timestamp divided down, `Trunc`'s inverse — all reach it.

Loud, not silent: the compiler refuses, so nothing wrong can be produced. That
is what keeps this at moderate rather than high priority.

## Where it lives

`ir_codegen_xtensa.inc`. riscv32's arm is the pattern —
`EmitFloatOperandRISCV32` (`ir_codegen_riscv32.inc`) emits the 64-bit int into
the register pair, calls `__pxx_l2d` (or `__pxx_ul2d` for the unsigned kind),
then repacks to the wanted float kind through `EmitFloatConvRISCV32`. Both
kernels are already in the `softfloat` unit and are already reachable on xtensa:
as of this fix, ESP-class targets pull that unit on demand
([[bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper]]), so the
callee exists and only the call site is missing.

Note the unsigned half is its own case and was a real bug once on riscv32:
`__pxx_l2d` reads the pair as SIGNED, so a `Cardinal` >= 2^31 converts negative
unless it is zero-extended into the pair and sent through `__pxx_ul2d`
(bug-c-int64-to-double-cast-truncates-on-32bit). Do not land the signed arm
alone.

## Found by

Writing `test/test_esp_bare_float.pas` for
[[bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper]]. The test
originally carried an `Int64 -> Double` arm; it was removed rather than routed
around with a target ifdef, and this ticket is where it went. Restore that arm
when this lands — it is written out in that file's comment.

## Gate

Track A's, plus the repro above compiling for `--target=xtensa
--esp-profile=bare`, plus the removed arm restored in
`test/test_esp_bare_float.pas` and its expectation row in the Makefile updated.
Values verified against the x86-64 oracle, on hardware or the Espressif
qemu-system-xtensa fork (not installed on plexus — see the parent ticket).
