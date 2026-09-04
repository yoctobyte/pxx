---
slug: bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing
track: A
prio: 45
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (fixing regression-test-threads-test-loadfile-shortstring)
summary: "`SysOpen(sp, 0)` with `sp: ShortString` naming a file that EXISTS returns a negative fd on riscv32 and xtensa. Those two COMPILE the shape and answer wrong; i386, aarch64 and arm32 refuse it by name (`target <arch>: SysOpen expects a managed AnsiString path`), which is the honest behaviour. Measured in one run where the managed-path rows of the same program passed on all five, so the file exists and the harness can reach it. Two defects in one finding: the wrong answer on two targets, and the fact that three targets disagree with two about whether the shape is even accepted."
---

# riscv32 and xtensa accept a ShortString SysOpen path and open nothing

## Measured

One program, 2026-09-04. It creates `/tmp/pxx_sysopen_shortstring_path.tmp`
through a **managed** `AnsiString` path (so the setup does not depend on the
branch under test), then reopens it through a **ShortString** path.

| target | managed rows | `SysOpen(sp, 0)` on a file that exists |
| --- | --- | --- |
| x86-64 | pass | `TRUE`, reads back `PXX26` |
| i386 | pass | **compile error**: `target i386: SysOpen expects a managed AnsiString path` |
| aarch64 | pass | **compile error**, same wording |
| arm32 | pass | **compile error**, same wording |
| riscv32 | pass | **`short open FALSE`** — compiles, opens nothing |
| xtensa | pass | **`short open FALSE`** — compiles, opens nothing |

The managed rows passing on every target is what makes this a statement about
the ShortString branch rather than about /tmp, the runner, or the file.

## Two separate things, and the second is the one to decide first

1. **riscv32 and xtensa are wrong.** They accept the shape and return a
   negative fd for a file that opens fine one line earlier. No diagnostic.
2. **Three targets refuse and two accept.** Refusing is defensible — the arm is
   genuinely not written — but a shape that is a compile error on three targets
   and a silent wrong answer on two is the worst of both. Whoever takes this
   should settle which it is before writing code: either riscv32 and xtensa
   grow the refusal (cheap, honest, and matches the majority), or all five grow
   the arm.

x86-64 is the only target that implements it. Its emitter pair is
`EmitTerminateString` + `EmitLeaStrDataRdi` in `symtab.inc`, both of which
follow the frozen-string prefix width -- `EmitTerminateString` did not until
`regression-test-threads-test-loadfile-shortstring` was fixed, and reading it
now is the cheapest description of what the other targets would need.

## Guard

`test/test_sysopen_shortstring_path.pas` exists and is wired NATIVE ONLY, with
this slug in the Makefile comment beside it saying why. Wire the cross rows when
this closes; three of them will be refusal-assertions rather than value rows
unless the second question above is settled the other way.
