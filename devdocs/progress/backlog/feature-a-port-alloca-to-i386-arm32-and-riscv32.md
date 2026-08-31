---
track: A
prio: 45
type: feature
status: backlog
blocked-by: []
summary: "IR_ALLOCA now exists on x86-64 and aarch64. i386, arm32 and riscv32 still refuse it at codegen ('target <arch>: IR op not yet supported: alloca'), which means C alloca() AND every VLA is unbuildable for those three targets -- test/c_vla.c does not compile for any of them."
---

# Port IR_ALLOCA to i386, arm32 and riscv32

`IR_ALLOCA` landed for x86-64 with `feature-c-alloca-dynamic-stack` and for
aarch64 on 2026-08-31. The other three backends `Error` at codegen, so
`test/c_vla.c` — an ordinary C99 variable-length array, not an exotic feature —
does not build for i386, arm32 or riscv32 at all.

## What the aarch64 port needed, which is the template

Five instructions and one property:

```
add x0, x0, #15 ; lsr x0, x0, #4 ; lsl x0, x0, #4   ; round up to 16
sub sp, sp, x0                                       ; grow the dynamic area
mov x0, sp                                           ; the hole
```

The property is that **the epilogue restores the stack pointer from the frame
pointer and locals are addressed off it**, so a lowered sp needs no unwinding
and disturbs no local. aarch64 already had it: `mov x29, sp` before the frame
reserve, `mov sp, x29` in the epilogue. i386 has it too (`leave`), and arm32's
epilogue is `mov sp, fp` (`symtab.inc:11851`). **riscv32 is the one to check
first** — if its epilogue adds the frame size back rather than restoring from
s0, that has to change before the op is safe.

Rounding is not decoration on the targets that fault on unaligned sp-relative
access: every expression temp in these backends is sp-relative, so an odd
`alloca(1)` takes the body down at the next spill rather than at the alloca.

## The invariant that comes with the op

`IR_ALLOCA` must not be reachable from inside a call's argument evaluation, or
from an expression with a value already spilled to the stack. The C frontend
upholds the first (`cparser.inc`, `CHoistAllocaArgs`); the second is still open
as [[bug-a-alloca-inside-a-call-argument-list-corrupts-the-restored-stack-pointer]],
measured but not reachable by any realistic shape. A port must not assume the
arrangement is safe just because the epilogue unwinds.

## Verification

`test/c_vla.c` and `test/c_alloca_in_call_argument.c` against a glibc-built
binary of the same file under `tools/run_target.sh`. Both are byte-identical on
x86-64 and aarch64 today, so a passing cross run is a real differential rather
than a self-comparison.
