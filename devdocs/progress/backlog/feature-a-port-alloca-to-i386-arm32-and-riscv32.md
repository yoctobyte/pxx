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

> **SUPERSEDED, 2026-08-31.** There is no frontend invariant to uphold any more.
> [[bug-a-alloca-inside-a-call-argument-list-corrupts-the-restored-stack-pointer]]
> is fixed in both backends, and the five-instruction template above is NOT what
> to copy — it is the arrangement that was wrong. Read the new model first.

The op's contract is now: **an alloca may be reached with anything already on
the expression stack, and must not disturb it.** Both backends meet it by
carving the hole at the bottom of the FIXED FRAME rather than at sp: a body
containing an `IR_ALLOCA` reserves one frame word, the ALLOCA BASE, holding
where its expression stack starts; an alloca lowers sp by the rounded size,
relocates everything between sp and the base down by that amount, and returns
the gap that opens under the base. The region moves as a unit, so every
sp-relative offset into it survives.

**The question a port must answer FIRST is not whether the epilogue unwinds.**
It is *where this backend's expression temps live, and whether it ever stores an
ABSOLUTE stack pointer* — because relocation moves such a value's bytes while
leaving the value itself stale.

- **i386** has the x86-64 shape on both counts: push/pop expression temps AND a
  saved absolute esp in its call sequence. It needs both halves, including the
  save-as-delta-from-base / restore-as-base-plus-delta pair
  (`EmitSaveCallerRspX64` and friends are the model).
- **arm32 and riscv32** need checking against the aarch64 question: aarch64
  needed only the relocation half, because its call sequence reads argument
  temps at fixed offsets from sp and drops them with a RELATIVE `add sp, sp,
  #imm`, so it never parks an absolute sp.

Relocation deliberately does not cover a statement-level scratch area addressed
through a saved absolute pointer (an exception frame, a shortstring concat
buffer). Unreachable with an alloca today because those are Pascal constructs
and `IR_ALLOCA` is C-only; a port that changes either half must revisit it.

The regression test to bring up on each target is
`test/c_alloca_expression_stack.c` — 17 rows, differential against gcc, with
row 9 (`a + (long)(alloca(32) != 0)`, no call in it at all) as the one that
fails on an unported model.

## Verification

`test/c_vla.c` and `test/c_alloca_in_call_argument.c` against a glibc-built
binary of the same file under `tools/run_target.sh`. Both are byte-identical on
x86-64 and aarch64 today, so a passing cross run is a real differential rather
than a self-comparison.
