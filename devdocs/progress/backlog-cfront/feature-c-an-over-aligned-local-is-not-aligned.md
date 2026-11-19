---
slug: feature-c-an-over-aligned-local-is-not-aligned
track: C
prio: 40
type: feature
status: backlog
created: 2026-11-15
found-by: measured while fixing bug-c-an-aligned-typedef-member-does-not-align-the-member
tags: [cfront, layout, silent, stack]
blocked-by: []
summary: "A local declared `int l __attribute__((aligned(32)))`, or with an aligned typedef (`al_t l;`, aligned 16), is placed at its plain type's alignment: `&l % 32` is nonzero under pxx, 0 under gcc. Globals and struct members honour both. Up to 16 needs only slot alignment within the 16-aligned frame; above 16 needs gcc-style frame realignment (and rbp addressing that survives it). Matters for SIMD/FXSAVE buffers and DMA descriptors on the stack."
---

## Step 1 done 2026-11-19 (pxx2): aligned(N) up to the frame pointer's alignment

ParseCLocalDeclAST now computes each declarator's aligned(N) with
CDeclAttrAlign over the declaration's type token through the declarator's end.
That covers an attribute on the specifiers, an aligned typedef, and an
attribute after the name or after an array's brackets. The result goes in
AllocMinAlign, which AllocVar's and AllocArray's LOCAL branches now honour (the
BSS branch already did). The three callers reset it afterwards.

On x86-64, where rbp is 16-aligned under SysV, that is every N <= 16:
test/c_aligned_local.c (row c_alocal26) prints 31 like gcc. Before, it printed
5. A differential sweep of 62 standalone typedef/ptr/struct/align/local C tests
is all SAME.

### Still open
- **N > 16 on x86-64** (aligned(32) and aligned(64) locals, and a local of an
  aligned(32) struct type). The slot offset is right but the frame is only
  16-aligned. Options measured against the code:
  (a) gcc's realignment: `and rsp,-N`, plus a separate register to reach the
      stack parameters, because rbp no longer can.
  (b) A hidden pointer into an oversized slot, set at the declaration, with the
      symbol accessed through it. IsRef is honoured only for skParam today
      (36 sites in ir_codegen.inc), so this means teaching the local paths too.
  (c) A front-end rewrite of each use to `(*$al$name)`, the way VLAs get a
      pointer.
- **i386**: ebp is not 16-aligned, so N > 8 has the same problem there. No
  i386 row for that reason.
- aarch64, riscv and the others: not measured.

## Demand measured 2026-11-19 (claude-dupwt): none in the trees we build

Before taking the N > 16 step (frame realignment is a prologue/epilogue
change that touches unwinding and frame walking), a grep of Rainyday's C for
aligned(32/64/128/4096/...) found only struct MEMBERS (ahci.c, virtio_blk.c,
nvme.c: aligned(128..4096) inside per-device structs) and one global
(tsc.c kvmclock, aligned(64)). Both are already honoured. No over-aligned
LOCAL exists there. Left unclaimed until a program needs one; the open
options above stand.
