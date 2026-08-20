---
track: A
prio: 30
type: feature
blocked-by: []
summary: "Initialize/Finalize work for records and AnsiStrings. A BARE dynamic-array or variant lvalue currently gets a clear compile error instead, because the dyn-array release helper needs a per-symbol element descriptor that has no IR-level dataref sentinel (SYM_RTTI_DATAREF_BASE is declared but has no fixup branch). A record CONTAINING either is fully handled, and `a := nil` is the one-line workaround, so the gap is narrow."
status: backlog
owner: ""
---

# `Finalize` on a bare dynamic array or variant

Split out of [[feature-a-implement-initialize-and-finalize-over-the-arc-helpers]]
while landing it, 2026-08-21.

## What works and what does not

| lvalue | Initialize | Finalize |
| --- | --- | --- |
| record with managed members | `PXXRecordInitialize` | `PXXRecordFinalize` |
| record with none | no-op (FPC parity) | no-op |
| AnsiString | raw zero store | desugared to `x := ''` |
| unmanaged | no-op | no-op |
| **bare dynamic array** | **compile error** | **compile error** |
| **bare variant** | **compile error** | **compile error** |

An error, deliberately, not a no-op — a silent no-op on a managed type is the
exact defect the parent ticket was filed for, so the gap says so out loud.

## Why it stopped there

`PXXDynArrayRelease(data, desc)` needs the array's ELEMENT layout descriptor.
Records reach theirs through `IR_CONST_DATA` with
`-(RECORD_RTTI_DATAREF_BASE + ci)`, resolved by the pre-link fixup pass in
`compiler.pas`. A per-SYMBOL element descriptor is `GetOrAllocSymRTTI(symIdx)`,
which is **codegen-level** — and `SYM_RTTI_DATAREF_BASE` (300000) is declared in
`defs.inc` but **has no fixup branch**, so there is no IR-level route to it.

So the work is one of:

1. Give `SYM_RTTI_DATAREF_BASE` a real fixup branch, making per-symbol
   descriptors reachable from IR the way record ones are. Probably the right fix
   — the constant already exists and reads as if it worked.
2. Or route the bare cases through the record path by other means.

Variants are cheaper and separable: `Finalize(v)` is `PXXVarClear(@v)` (already
idempotent — it clears in place), and `Initialize(v)` is zeroing 16 bytes, since
`varEmpty` is 0. That half could land on its own.

## Why it is low prio

The gap is genuinely narrow: a record *containing* a dynamic array or variant is
fully handled (`PXXRecordFinalize` walks to `PXXDynArrayRelease` with the
sub-descriptor), and a bare one has a one-line workaround that does exactly what
Finalize must — `a := nil` releases the old reference and nils, and `VarClear(v)`
exists. Neither is on the parent ticket's motivating path (a `GetMem`'d record).

## Gate

Track A: repro proving a bare dyn array's elements are released and a copy taken
beforehand survives; `test_initialize_finalize` extended; self-host
byte-identical.
