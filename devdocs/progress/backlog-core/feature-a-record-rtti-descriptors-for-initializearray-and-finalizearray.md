---
slug: feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray
title: "`System.InitializeArray` / `FinalizeArray` — the RTTI-driven form of a management operator"
track: A
prio: 40
type: feature
status: backlog
owner: ""
found: 2026-09-06
found-by: frankS
blocked-by: []
summary: "MEASURED 2026-09-06 at 88a0b3d93835. `InitializeArray(P, TypeInfo(TFoo), N)` and its Finalize twin do not exist -- `undefined variable (InitializeArray)`, and nothing in compiler/ or lib/rtl mentions either name. They are the RTTI-DRIVEN form of a management operator: given a raw pointer, a TypeInfo and a count, run the record's Initialize/Finalize over N elements. FPC's own RTL uses them wherever the element count is not known at compile time, which is why the SYNTACTIC form ([[feature-pascal-management-operators-nested-and-array]]) cannot subsume them -- that one desugars an lvalue it can see, this one is handed a pointer and a descriptor. THREE CORPUS ROWS ASK FOR IT, one cause: fpc testsuite tmoperator2 (line 100), tmoperator3 (line 82), tmoperator9 (line 48), all three stopping on the same undefined name. PREDICTED BY THE TICKET IT IS NOT PART OF: nested-and-array's Sketch says the dynamic-array and class-field cases are 'genuinely the RTTI shape FPC uses ... the point at which a Track A ticket for record RTTI descriptors is the right answer'. This is that ticket, filed with the demand attached rather than as a shape. TWO HALVES AND ONLY THE SECOND IS THE HARD ONE: the System helpers are a loop over a descriptor, but TypeInfo(TRec) must first CARRY the management-operator entry points for a record, which is a Track A RTTI-emission question, not a parser one. NOTHING PAST THE FAILING LINE IS VERIFIED in any of the three rows -- each stops at its first InitializeArray, so what those files assert afterwards is unmeasured and must not be quoted as passing or failing."
---

# `System.InitializeArray` / `FinalizeArray`

- **Type:** feature — Track A (RTTI emission), with a small Track P/B surface
- **Found:** 2026-09-06, walking the fpc-testsuite `tmoperator` cluster

## The shape the corpus asks for

```pascal
GetMem(PF, SizeOf(TFoo));
InitializeArray(PF, TypeInfo(TFoo), 1);   { runs TFoo.Initialize on PF^ }
...
FinalizeArray(PF, TypeInfo(TFoo), 1);     { runs TFoo.Finalize }
FreeMem(PF);
```

`tmoperator2.pp:100`, `tmoperator3.pp:82`, `tmoperator9.pp:48` — three rows,
one `undefined variable (InitializeArray)`. `grep` finds neither name anywhere
in `compiler/` or `lib/rtl`.

## Why the syntactic ticket cannot absorb this

[[feature-pascal-management-operators-nested-and-array]] generalises
`WrapManagementOpsRange` from a symbol to an **lvalue node it can see**. These
helpers are handed a **pointer and a descriptor**: the element type is a runtime
value. No amount of desugaring reaches it. That ticket's own Sketch says so and
names this one as the answer.

## The two halves, and the second is the work

1. **The helpers** — `InitializeArray(P, Info, N)` / `FinalizeArray` walking N
   elements and calling through the descriptor. A loop; small.
2. **The descriptor** — `TypeInfo(TRec)` must carry a record's management-operator
   entry points. That is RTTI emission (`rtti_emit.inc`), and it is the half
   that decides what shape 1 can even have. **Do not start with the helpers**:
   a helper written against a descriptor that does not exist yet is a guess
   about a layout somebody else will choose.

## What is NOT established

Each of the three rows stops at its FIRST `InitializeArray`. **Everything those
files assert afterwards is unverified** — a compile that stops at line 100 says
nothing about line 101. When the helpers land, re-measure all three rather than
assuming they go green; two of them also exercise `New`/`Dispose` and class
fields above the failing line, which pass today, and one exercises shapes below
it that nobody has run.

## Gate

`make compiler/pascal26` (self-host fixedpoint), the three corpus rows diffed
against fpc 3.2.2 **including exit codes** (they `Halt(n)` with distinct n per
assertion, so an exit code names the row that failed), and `tools/gate.sh quick`.
