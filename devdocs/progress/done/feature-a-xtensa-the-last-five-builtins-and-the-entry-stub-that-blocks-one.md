---
track: A+S
type: feature
prio: 40
status: done
found: 2026-08-30
found-by: frankS
---

# Xtensa's last five non-compiling builtins — four are ports, one needs the entry stub

Follow-up to
[[feature-a-xtensa-implements-31-ir-ops-where-riscv32-implements-45]], which
took hosted xtensa from 69 to 96 of 129 cross programs matching the x86-64
oracle. Six of the remaining 25 are builtins, and they are only visible as
*distinct* because that ticket fixed the diagnostic — they used to arrive as one
undifferentiated *"builtin calls not supported in bare-metal stage 1"*.

| builtin | what | programs | where the arm exists to port from |
| --- | --- | --- | --- |
| `-100` | `LoadFile(path, dst)` | `test_cross_loadfile` | i386, arm32, aarch64 (**not** riscv32) |
| `-50` | (sysopen family) | `test_cross_sysopen_family` | — check which backends have it |
| `-55` | `ParamCount` | `test_arm32_arg_runtime` | riscv32 — **but see below** |
| `-999` | (unnamed) | `test_cross_in_operator`, `test_cross_string_cow` | **nowhere** — riscv32 has the same gap |

## `-55` is not a same-file port, and that is the finding

riscv32's `tkArgCount` arm reads the initial stack pointer out of
`BSS_INITIAL_RSP` — the kernel-provided sp, which points at `argc`. Every hosted
target's **entry stub** saves it there:

```pascal
{ Hosted: save the kernel-provided initial sp (points at argc) for
  ParamCount/ParamStr, like the other hosted targets. }
if not EspBareBoot then
begin
  rv32_auipc(reg_t1, 0); ... rv32_sw(reg_sp, reg_t1, 0);
end;
```

**The xtensa arm of `EmitProgramEntryForTarget` does not.** It zeroes a few
registers and jumps to the body. So `ParamCount` cannot be implemented in
`ir_codegen_xtensa.inc` at all: the value it needs is never stored. The fix is
two pieces — one in the entry stub (`ir_codegen.inc`, a different procedure from
the Track S grant) and one in the backend — and `ParamStr` will want the same
base, so do them together.

This is the co-location argument again from a third angle: five hosted targets
save the initial sp inside one procedure, xtensa's arm sits among them, and it
does not. Nothing failed, because nothing on xtensa had ever called
`ParamCount`.

## `-999` is not an xtensa gap

Verified rather than assumed — the same source compiled for riscv32:

```
$ ./compiler/pascal26 --target=riscv32 test/test_cross_in_operator.pas /tmp/x
error: target riscv32: standard builtin calls not supported in bare-metal stage 1 (builtin id 999)
```

Two backends, one gap. Whoever takes it should identify what `-999` is first —
no `ir_codegen*` file mentions it, so it may be a frontend-side id that never
acquired a lowering on any 32-bit target.

## Gate

Per builtin: `make compiler/pascal26` (the self-host fixedpoint) plus the newly
compiling programs run and match the x86-64 oracle, Call0 and windowed, and
`test-xtensa` extended from the measured set. No regression in the 129-source
differential.

## Bound

At `69403fede2e5`. The builtin ids are from the compiler's own diagnostic, one
compile per program. Which backends have a `-50` arm is UNCHECKED. The claim
that the xtensa entry stub does not save the initial sp is from reading
`EmitProgramEntryForTarget`, not from running a `ParamCount` program — it cannot
be run, which is the point.

## Log

- 2026-08-30 — **all four resolved.** `-100` LoadFile and the `-50` SysOpen
  family landed on xtensa and riscv32 together (the rv32 arms were missing too),
  with the three runtime wrappers in `builtinheap.pas`. `-55` landed last and
  whole, because it was not a same-file port as this ticket predicted: the entry
  stub's initial-`sp` save had to come with it, and `tkArgStr` had to come too —
  `ParamStr` is an expression that desugars to `ArgStr` with a hidden frozen
  temp, so `ParamCount` alone does not make `test_arm32_arg_runtime` pass.
  `-999` was NOT an xtensa gap, exactly as this ticket said: it is `SPECIAL_IN`,
  missing on riscv32 too, closed under
  [[bug-a-special-in-has-no-arm-in-the-two-32-bit-cross-backends]].
- 2026-08-30 — resolved, commit 42c8ded06.

### What the four cost, measured

Hosted xtensa 100 → 103 of 129 matching on Call0 and 50 → 53 on windowed;
riscv32 107 → 111, since three of the four were missing there as well. No
program regressed at any step.

### The one thing that did NOT come out clean

`test_arm32_arg_runtime` compiles and matches the oracle when given arguments,
and diverges when given none: `ArgStr(2)` out of range reads past `argv` into
`envp` on both 32-bit backends, byte-identically, and riscv32 did this before
any of tonight's work. x86-64 bounds-checks. Filed as
[[bug-a-argstr-reads-past-argv-into-the-environment-on-riscv32-and-xtensa]]
rather than folded into the `-55` commit — a grant for one defect does not cover
an adjacent different one.
- 2026-08-30 — resolved, commit 42c8ded06.
