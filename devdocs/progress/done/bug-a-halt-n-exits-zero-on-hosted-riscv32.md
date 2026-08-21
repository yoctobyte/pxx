---
slug: bug-a-halt-n-exits-zero-on-hosted-riscv32
track: A
prio: 45
type: bug
blocked-by: []
summary: "`Halt(7)` exits 0 on hosted riscv32 and 7 on every other target and on FPC. The IR_TERMINATE arm emitted an unconditional exit(0) and never evaluated its argument, under a comment claiming bare-metal — an ESP assumption applied to the hosted profile of the same arch. A program's failure signal vanished with no diagnostic."
status: done
owner: claude-A
commit: PENDING-COMMIT
---

# `Halt(n)` exits 0 on hosted riscv32

Found 2026-08-21 while building the verification path for
[[feature-a-riscv64-as-a-hosted-first-class-target]] — `Halt(n)` was going to be
how the first riscv64 increment proved itself end to end, so it got checked
first.

## Measured

```pascal
program min; begin Halt(7); end.
```

| target | exit |
| --- | --- |
| x86-64 | 7 |
| i386 | 7 |
| arm32 | 7 |
| aarch64 | 7 |
| **riscv32 (hosted)** | **0** |
| FPC (oracle) | 7 |

Same answer with a computed code (`code := 5; Halt(code)`), and the `WriteLn`
before it printed normally — so the program ran to completion and then reported
success.

## Cause

`ir_codegen_riscv32.inc`, the `IR_TERMINATE` arm:

```pascal
if IRIVal[node] = AN_HALT then
  EmitExit(0)                            { bare-metal: park in a self-loop }
```

`IRA[node]` — the halt code — is never read. The comment is the tell: it
describes ESP bare metal, and it was applied to **the whole arch**, hosted
profile included. riscv32 is dual-role, and this is the same mis-keying as
[[bug-a-real-is-single-on-hosted-riscv32]] and the `emit.inc` /
`exception_emit.inc` arms tabulated in the riscv64 ticket: `TARGET_RISCV32`
used as a proxy for "small, bare, no OS", which stopped being true when the
target became dual-role.

`EmitExit` itself was already correct for hosted riscv32 (`a7 = 94`, `a0 =
code`, `ecall`) — but its encodings only take a CONSTANT, and nothing ever
passed it one but zero.

## Fix

Mirror the aarch64 arm, which does it right: evaluate the code expression into
the first argument register, **then** load the syscall number, so computing the
code cannot clobber `a0`.

```pascal
if (IRA[node] <> -1) and (not EspBareBoot) then
begin
  IREmitNodeRISCV32(IRA[node]);        { a0 = the exit code }
  EmitI32($05E00893);                  { addi a7, x0, 94  (exit_group) }
  EmitI32($00000073);                  { ecall }
end
else
  EmitExit(0);                         { no argument, or ESP bare: park }
```

ESP bare keeps the self-loop, which is what the old comment actually described —
now it is guarded by `EspBareBoot` rather than by the arch.

## Why it is worth a prio-45 and not a footnote

A lost exit code is the shape of wrong answer this repo pays most for: nothing
crashes, nothing prints, and every caller that branches on `$?` — a shell
script, a CI job, a Makefile `test "$(...)" = ...` assertion — silently takes
the wrong branch. It also means any riscv32 test that signalled failure by
exiting nonzero has been passing vacuously.

## Test

`test/test_halt_exit_code.pas`, on all five hosted targets (Makefile rows next
to each `test_signal_sp_rewrite` row). It halts with a **computed** code after
writing two lines: a constant could be satisfied by a smarter `EmitExit`, but a
variable only passes if the expression really reaches the argument register, and
the writes catch an exit taken too early. Verified against FPC, which prints the
same two lines and exits 5. All five targets and the oracle now agree.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the five-target
differential against FPC + `tools/gate.sh quick`. Cross-target breadth is
Track T's, against this sha.
