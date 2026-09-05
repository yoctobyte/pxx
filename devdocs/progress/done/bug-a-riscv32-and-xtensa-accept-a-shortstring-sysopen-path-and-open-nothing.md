---
slug: bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing
track: A
prio: 45
type: bug
status: done
blocked-by: []
owner: frankS
created: 2026-09-04
found-by: frankA (fixing regression-test-threads-test-loadfile-shortstring)
summary: "FIXED 2026-09-05 on both targets, verified by a LOCAL QEMU RUN: `SysOpen(sp, 0)` with `sp: ShortString` now opens the file on riscv32 and xtensa, byte-identical to the x86-64 run of the same source. Both backends took the path from the generic arg evaluation, which for a frozen string yields the address of `[len][chars]`, so the kernel read the length byte as the first path character. Both now take the buffer address from the SYMBOL, NUL-terminate at data+len and pass the data pointer -- the choice x86-64 already made. Shared discriminator `SysPathFrozenSym` in symtab.inc; six instructions per backend. The ticket's SECOND question -- three targets refusing a shape three implement -- is split out to bug-a-three-targets-refuse-a-shortstring-sysopen-path-four-implement-it, with the refusals now asserted in test-core."
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


## Resolved 2026-09-05 (frankS)

### The fix

`SysPathFrozenSym(argNode)` (`compiler/symtab.inc`, beside `TypeIsFrozenString`)
answers one question for both backends: is this argument a LOAD_SYM/LEA of a
scalar frozen-string symbol? It returns the symbol index or -1, and it refuses
`IsArray` deliberately -- declining a case it cannot lower rather than lowering
it to the wrong address.

`EmitSysBuiltinRISCV32` and `EmitSysBuiltinXtensa` each gained a
`pathIsArg0: Boolean` parameter, true at exactly one of their five call sites
(SysOpen). When it fires on arg 0 and the helper returns a symbol, the arg loop
emits slot-addr / load-len / lea-data / add / store-zero / move instead of the
generic node evaluation. Every other syscall through those routines is
byte-unchanged -- `pathIsArg0` is False at read, write, close and fchmod.

The buffer address comes from the SYMBOL rather than from the generic value
evaluation on purpose: what a generic load leaves in a register for a frozen
string is a per-backend convention, while the slot address is not. Both arms
share `FrozenStrPrefixSize` through `EmitLoadStrLen*`/`EmitLeaStrData*`, so the
change states no new layout fact on either target.

### Evidence — and what KIND of evidence it is

**A local qemu RUN on this machine, not a cross-compile-and-inspect.** Recorded
explicitly because cross-target claims in the fleet are otherwise stale, and a
built-and-eyeballed object is a different claim from an executed one.

Compiler `0d8884ee2e9a`, `converged after 1 round(s)` (a real recompute, not the
stamp path). One source, seven targets:

| target | before | after |
| --- | --- | --- |
| x86-64 | `short open TRUE / short read 5 PXX26 / short miss TRUE` | unchanged |
| riscv32 | `short open  FALSE` | identical to the x86-64 run, exit 0 |
| xtensa | `short open  FALSE` | identical to the x86-64 run, exit 0 |
| i386 / aarch64 / arm32 | refuse by name | unchanged, now ASSERTED |
| wasm32 | -- | cannot build the test at all (raw syscall in sysutils) |

**Positive control.** The pre-fix binaries printed `short open  FALSE` on both
targets while x86-64 printed TRUE; the wired rows compare the qemu output
against the x86-64 run of the same source, and `expect_same.sh` was checked to
reject exactly that string pair (`MISMATCH`, rc=1). The control is drawn from
the population the question is about -- the literal output the defect produced.
The rows assert RELATIONS (does the open succeed, do the bytes come back), carry
no per-target constant, and so would still be right if a target changed a width.

### Wired

`test-core` gains riscv32 and xtensa value rows and, for i386/aarch64/arm32,
refusal-assertions matching the diagnostic by message. The refusals are asserted
rather than omitted because "refuses" silently becoming "answers wrong" is
precisely the transition riscv32 and xtensa had already made while nothing was
watching them.

### The wasm32 claim in the original body was never run

This ticket said wasm32 "would implement it". Measured: wasm32 cannot compile
this test for an unrelated reason, so its position is UNMEASURED and that
sentence should not travel.

### Banked, not folded in

- `bug-a-an-indexed-shortstring-sysopen-path-segfaults-on-x86-64` -- the parser
  admits `SysOpen(arr[0], ...)` because its guard reads `TypeKind` and never
  `IsArray`, and the DEFAULT target segfaults on it. Pre-existing; found by this
  work, not caused by it.
- `bug-a-three-targets-refuse-a-shortstring-sysopen-path-four-implement-it`.

Both share one root cause seen from two sides: **every backend re-derives the
path address from the symbol index, discarding the lvalue the parser already
built.** That is the thing worth fixing once, and it is bigger than this ticket.
