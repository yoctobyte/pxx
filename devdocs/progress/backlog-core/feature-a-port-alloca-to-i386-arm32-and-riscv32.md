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

### From frankC, 2026-08-31, on the two argument blocks being written now

frankC holds the C-ABI stack-argument group and reports that the i386 cdecl and
arm32 AAPCS32 argument blocks address their arguments as fixed offsets from a
stack pointer that is stable only because nothing moves sp during argument
evaluation. They read that as the same defect, latent for want of an alloca arm
to reach it.

**Half right, and the half that differs is the useful half.** A fixed offset
FROM sp is exactly what relocation preserves — the block and sp move together,
so those two argument blocks are safe under this model as written, on any
target. What relocation cannot save is an absolute stack pointer stored and used
later, because its bytes move while its value does not. So the audit question
for each block is not "does it use fixed offsets" (fine) but **"does it park an
sp anywhere"** — a saved caller-esp in the call sequence, a pointer to a temp
handed to a helper, an sp published to a global.

x86-64 had exactly one such value and needed the delta pair; aarch64 had none
and needed only the relocation. i386's call sequence is x86-64-shaped, so expect
one there too.

Recorded here rather than as its own ticket, at frankC's request via the
coordinator, so it is waiting for whoever takes the port rather than expiring
in a message.

**Then frankC went and found the real one, and it is i386.** Verified in the
source rather than taken on report — `ir_codegen386.inc:3328-3331` and `:3388`,
in the `ProcExternal or CProcUsesCAbi` arm:

```
mov ecx, esp                  ; the caller's esp, ABSOLUTE
and esp, -16                  ; SysV i386 alignment
sub esp, base
mov [esp+argBytes], ecx       ; parked in the outgoing frame
... args, call ...
mov esp, [esp+argBytes]       ; restored from the parked ABSOLUTE value
```

That is the exact i386 twin of the x86-64 rsp this fix converted to a
`base + delta` pair, so **the i386 port needs the delta treatment, and needs it
by construction rather than by choice**: the `and esp, -16` means the amount
subtracted is not a compile-time constant, so the restore cannot be rewritten as
a relative `add`. Latent today only because i386 has no IR_ALLOCA arm to reach
it.

frankC's arm32 AAPCS32 block is all relative on purpose (`sub sp,#blk` /
`add sp,#16` / `add sp,#blk-16`, no saved pointer), so it is safe as written —
the aarch64 situation. riscv32 is the one still unaudited.

## Verification

`test/c_vla.c` and `test/c_alloca_in_call_argument.c` against a glibc-built
binary of the same file under `tools/run_target.sh`. Both are byte-identical on
x86-64 and aarch64 today, so a passing cross run is a real differential rather
than a self-comparison.
