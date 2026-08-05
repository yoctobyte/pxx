---
track: A
prio: 45
type: bug
summary: "aarch64 has its own EmitWriteFloatSciA64 / EmitWriteFloatNatA64 emitters, not touched by the non-finite fix — very likely the same never-terminating normalise loop, unverified because no emulator run was done"
status: done
owner: claude-A
---

# aarch64's float emitters were not covered by the non-finite fix

[[bug-a-writeln-of-a-non-finite-double-hangs]] guarded five formatters — the two
x86-64 native emitters, the two portable helpers, and the builtin `FloatToExpStr`
/ `StrFloat` pair — and verified x86-64 and i386 produce identical output.

**aarch64 has its own emitters** (`EmitWriteFloatSciA64`, `EmitWriteFloatNatA64`
in `ir_codegen_aarch64.inc`) which were NOT touched. They are ports of the x86-64
originals, so they almost certainly carry the same `while value >= 10 do value :=
value / 10` normalisation and therefore the same hang on `Inf`.

**This is unverified either way.** It was not measured, because running an
aarch64 binary needs the qemu path (`make test-aarch64`) rather than a native
run, and asserting "probably fine" about a cross target is exactly the mistake
recorded in [[feedback_control_must_actually_remove_the_variable]].

## Method

`./compiler/pascal26 --target=aarch64 test/test_writeln_nonfinite_float.pas` and
run it under the project's aarch64 emulator, **with a timeout** — the expected
failure is a hang, which without one stalls rather than fails. If it hangs, port
the guard: the shape is in `EmitWriteFloatSci` (`compiler/symtab.inc`), checked
before the sign is emitted so NaN prints unsigned, with **rel32 branches** —
byte displacements truncate silently because each character write expands to a
syscall sequence.

Check arm32, riscv32 and xtensa at the same time. They have no native float
emitter, so they should already be covered by the portable `PXXWriteFloatSci` /
`PXXWriteFloatFixed` fix that made i386 correct — but "should" is the word this
ticket exists to remove.

## Gate

`test/test_writeln_nonfinite_float.pas` cross-compiled and RUN for each target
under a timeout, output identical to the x86-64 expectation.

## Resolution (2026-08-05)

Measured under qemu with a timeout, as the ticket's method demanded. The
hypothesis was half right, and the half it got wrong is the more interesting
one.

**`EmitWriteFloatSciA64` — already fixed, incidentally.**
`bug-a-writeln-float-exponent-form-not-correctly-rounded` (landed earlier today)
replaced it with a shim onto `PXXWriteFloatSci`, which carries the guards. So
the Sci path prints ` Inf` / `-Inf` / ` Nan` and does not hang.

**`EmitWriteFloatNatA64` / `EmitWriteFloatFixedA64` — broken, but NOT a hang.**
This is where the ticket's "almost certainly the same never-terminating loop"
guess missed:

    aarch64, before:  writeln(Inf:0:2)  ->  92233720368547758.07
                      writeln(NaN:0:2)  ->  0.00

A **silent wrong number**, not a stall — the worse half of the same defect, and
exactly the variant the parent ticket recorded for the fixed-decimals branch on
x86-64. Had this been chased by looking for a hang it would have read as "not
affected".

**Fix:** both are now shims onto `PXXWriteFloatNat` / `PXXWriteFloatFixed` via a
new `EmitFloatCallWriterA64`, mirroring what arm32/i386/riscv32 already do —
~140 more lines of hand-written aarch64 deleted, and aarch64 now has no
hand-written float formatter left.

**Verified:** ` Inf` / `-Inf` / ` Nan` for Sci, Nat, Fixed and `Str`, identical
on x86-64, aarch64, i386 and arm32, all under a 15s timeout (nothing hangs).
`test/test_writeln_float_exact.pas` still byte-identical on aarch64.

### Three aarch64 rows silently IMPROVED, and two pre-existing bugs exposed

Diffing aarch64 against `pinned` on ordinary values showed the shim also fixed:
`writeln(-2.5:0:0)` (`-2` -> `-3`, FPC's away-from-zero rounding),
`writeln(1e20:0:2)` and `writeln(1.23456789012345678e17:0:2)` (both were
`92233720368547758.07`).

The same comparison exposed two defects that are **not** from this change —
`pinned` has both — and are filed rather than fixed here:

- `bug-a-aarch64-float-field-width-ignored` — `writeln(d:10:4)` drops the field
  width on aarch64, and on i386/arm32/riscv32 too, because the runtime helper
  has no width parameter. Only x86-64 pads.
- `bug-a-x86-64-writeln-fixed-saturates-at-int64` — `writeln(1e20:0:2)` prints
  `9223372036854775809.00` on x86-64, where every other target is now correct.
  Its fix is a shim like this one, but it is BLOCKED on the width bug above:
  shimming today would trade a wrong number for lost padding.

**Gate:** `testmgr --tier quick` 15/15; `selfhost_fixedpoint.sh` converges in 2
rounds from `pinned` and agrees with `compiler/pascal26`.

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.
