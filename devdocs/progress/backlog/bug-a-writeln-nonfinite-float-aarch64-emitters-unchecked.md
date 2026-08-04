---
track: A
prio: 45
type: bug
summary: "aarch64 has its own EmitWriteFloatSciA64 / EmitWriteFloatNatA64 emitters, not touched by the non-finite fix — very likely the same never-terminating normalise loop, unverified because no emulator run was done"
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
