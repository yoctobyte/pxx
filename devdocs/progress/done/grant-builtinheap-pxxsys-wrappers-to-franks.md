---
slug: grant-builtinheap-pxxsys-wrappers-to-franks
track: A
prio: 45
type: grant
status: done
found: 2026-08-30
blocked-by: []
summary: "frankS gets compiler/builtin/builtinheap.pas bounded to riscv32/xtensa arms on PXXSysOpenRO, PXXSysLseek and PXXSysClose, for bug-a-loadfile-runtime-wrappers-have-no-riscv32-or-xtensa-arm. Cleared against BOTH other interests by asking each for a footprint rather than a permission: frankA does not touch the file at all, and b4's census edits are landed and ~300 lines away."
---

# GRANT: `compiler/builtin/builtinheap.pas` → frankS, bounded to three `PXXSys*` wrappers

For `bug-a-loadfile-runtime-wrappers-have-no-riscv32-or-xtensa-arm` [A p45]. Filed at the
moment it is given, because **an unfiled grant is invisible to the board in both directions**:
it reads as *covered* to anyone checking permission, and as *not yet done* to the ranker, which
then spends a dispatch re-offering finished work. Both halves were observed on 2026-08-30 —
see 193a.

## Scope

`PXXSysOpenRO` (~2192), `PXXSysLseek` (~2213), `PXXSysClose` (~2230) — **riscv32 and xtensa
arms only**. Nothing else in the file. Anything else the work needs is a fresh ask.

The banked `LoadFile` codegen arm (`scratchpad/rw/loadfile-xtensa.arm`, 25 lines) lands **in
the same change as the wrappers or not at all** — that constraint is frankS's own and it
survives this grant. Landing the arm alone replaces `error: this builtin has no arm in the
xtensa backend` with an **empty string**, which is indistinguishable from an empty file: the
block was the safety property, not the obstacle.

## How it was cleared — footprints, not permissions

Three lanes had an interest. Each was asked *what it touches*, not *whether it minds*.

**frankA — does not touch the file at all**, in either increment of
`feature-port-rtl-over-libc`. Structural, not incidental: the four `PXXSys*` wrappers reach
the kernel through the `__pxxrawsyscall` intrinsic, and the intrinsic funnels into **one IR
op**, so the libc route changes how their calls are *lowered* and never their *source*. Same
property means that ticket touches no `lib/rtl` file either. `--rtl-libc` is also x86-64-only
and opt-in while this work is riscv32/xtensa, so the two do not meet even at the lowering.
frankA's files: `defs.inc`, `compiler.pas`, `symtab.inc`, `ir_codegen.inc`, `emit.inc`.

**b4 — edited the file, but everything is landed** (`0f0a5619a` plus the amend after it), so
nothing is in flight. Footprint at HEAD: const block ~206; var block ~641-668 (census
counters, inside `{$ifdef PXX_ALLOC_CENSUS}`); `PXXAlloc` ~950-1095; `PXXFree` head ~1150; new
block **1780-1895** (`PXXCensusPut` / `PXXCensusNum` / `PXXCensusReport`). **Nearest approach
~300 lines, no textual overlap.**

## The one real constraint, and it is not about collisions

b4's new block sits immediately after `PXXSysWrite`'s body (1734-1779) **because it writes
through it**. So:

> **`PXXCensusReport` calls `PXXSysWrite` and runs from inside `PXXAlloc`.** It is documented
> as allocating nothing for that reason.

If a new `PXXSys*` arm ever allocates — a managed temp, a string buffer — it **re-enters the
allocator**, and on the threadsafe build the temp's finalize takes the heap lock the caller
already holds. That is `bug-a-threadsafe-plus-heap-debug-hangs-at-runtime` exactly.
`PXXSysWrite` is clean today; the constraint is on what gets added *beside* it. **The new
riscv32/xtensa arms must allocate nothing.**

This is the substantive risk in the whole grant, and note that no collision check would have
found it — it is a **semantic** adjacency, not a textual one. It surfaced only because b4 was
asked what it had done rather than whether it objected.

## Expiry

When the ticket resolves. Not a standing widening of Track S into `compiler/builtin/**`.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
