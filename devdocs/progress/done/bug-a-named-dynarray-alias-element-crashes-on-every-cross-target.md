---
track: A
prio: 45
type: bug
blocked-by: []
summary: "test_dynarray_named_alias_element passes 26/26 natively and CRASHES on arm32 and aarch64 (SIGSEGV) and produces no output on riscv32. The Track P fix that made `array of <named dyn-array alias>` compile at all (907f18d9e) landed the frontend half; the four cross backends never handled the shape. Pre-existing — riscv32 fails with zero cross-target changes applied."
status: done
owner: claude-A
---

# `array of <named dyn-array alias>` crashes on every cross target

- **Track A** (cross-target codegen: `ir_codegen386.inc`,
  `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_riscv32.inc`).
- Found 2026-08-21 during a cross-target sweep of the dyn-array tests.

## Measured

`test/test_dynarray_named_alias_element.pas`, current HEAD:

| target | result |
| --- | --- |
| x86-64 | **total ok 26 / 26** |
| arm32 | SIGSEGV |
| aarch64 | SIGSEGV |
| riscv32 | no output at all |

The test did not exist as a *compilable* program before
`907f18d9e fix(P): array of <named dyn-array alias> in a TYPE decl kept its
dimension` — a compiler older than that rejects it with an overload-resolution
error (`argument types: (ShortString, Integer, ShortString)`), because the
element type came out wrong. So the frontend half landed and the cross backends
were never taught the shape.

## Not a regression from the interface-container work

Checked deliberately rather than assumed, because that work was in flight when
this surfaced: **riscv32 fails with zero of those changes applied to it.** Its
epilogue, its store path and its element-kind handling are all untouched in the
tree that produces the failure above. The same reasoning clears arm32, whose
only change was *removing* a call (an accidental `PXXStrDecRef` on an array's
data pointer) — dropping a release cannot produce a segfault.

## Where to start

`Syms[].ElemType` / `SymElemDynDepth` for the aliased element is what 907f18d9e
corrected; the cross backends compute element stride and slot width from those
same fields in several places each. Dump the IR natively and on aarch64 for the
failing case and compare the stride the two backends derive — the native answer
is known-correct here, which makes this a differential rather than an
investigation.

## Gate

26/26 under `tools/run_target.sh` for i386 / arm32 / aarch64 / riscv32; native
unchanged; self-host fixedpoint + `tools/gate.sh quick`.

## Resolution (2026-08-21)

**26/26 on all five targets.** The alias turned out to be irrelevant — it was
never about `Syms[].ElemType` for an aliased element, which is where the "where
to start" section above pointed. Two independent causes, both about NESTED
dynamic arrays in general:

### 1. A nested `SetLength` was given the ROOT symbol's descriptor

`GetOrAllocNodeDynDesc` saw a symbol-rooted target and returned
`GetOrAllocSymRTTI(symIdx)` — the descriptor of the WHOLE symbol. For
`SetLength(m[0], n)` on `array of array of Integer` that descriptor says depth 2,
stride 8 (a row of sub-array handles), but the target is one row: depth 1,
stride 4. `PXXDynSetLen` therefore allocated 5x8 instead of 5x4, and — worse —
released the OLD row at depth 2, walking its plain Integers as sub-array
pointers. `PXXDynArrayReleaseDepth(Pointer(7))` dereferences address 7. That is
the SIGSEGV.

The fix takes the symbol's descriptor only when the target IS the whole symbol
(`IRC[node] = SymTR[symIdx].DynDepth`); otherwise it mints a descriptor at the
node's own depth from the symbol's ULTIMATE element type.

**x86-64 was immune for a reason worth recording:** its `IR_SETLEN_DYN` is
emitted inline and derives depth and stride from the node itself, so it never
consulted the symbol descriptor at all. The one target that could not see the
bug is the one every fix is checked against.

### 2. `IR_STORE_DYN` existed only on x86-64

The ARC-correct whole-dyn-array store into a slot ADDRESS (field / nested
target) was x86-64-only; the other four fell back to the non-retaining
`IR_STORE_MEM` share path. Implemented on i386, arm32, aarch64 and riscv32;
`ir.inc` now emits it for every target except xtensa, and `defs.inc` says so.
This is also the retain half that `bug-a-no-dyn-array-scope-exit-release-on-four-backends`
is blocked on — a scope-exit release is only safe once EVERY store that can put
a handle into the local retains it.

Plus one truncation fix found on the way: `EmitLoadVarA64` sized a dyn-array
symbol's load by its ELEMENT type, so a handle loaded through a 4-byte
`ldr w0` lost its high half.

### 3. i386 also could not BUILD multidim `SetLength` at all

Split out as `bug-a-i386-multidim-setlength-mints-an-untyped-temporary` (fixed
in the same commit): the multidim desugar minted an untyped `AN_BINOP` limit,
the AN_FOR lowering copied that 0 into the hidden limit temp, and i386 refused
the tyUnknown symbol. Pre-existing on `pinned`.

### Measured

| target | before | after |
| --- | --- | --- |
| x86-64 | 26 / 26 | 26 / 26 |
| i386 | BUILDFAIL | **26 / 26** |
| arm32 | SIGSEGV | **26 / 26** |
| aarch64 | SIGSEGV | **26 / 26** |
| riscv32 | no output | **26 / 26** |

## Log
- 2026-08-21 — resolved, commit ba398c9b1.
