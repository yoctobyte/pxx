---
track: A
prio: 80
type: bug
status: resolved
found: 2026-09-14
found-by: frank-user
owner: ""
resolved: 2026-09-14
blocked-by: []
summary: "FIXED 2026-09-14. In a program that declares ANY threadvar, an ordinary parameter, array, dynamic array or constant could be lowered into a read through the thread block at gs:+0 -- silently, as a WRONG VALUE. RewriteThreadVarRefs (ir_codegen.inc) rewrites every AN_IDENT whose SymTlsOffset is >= 0, and -1 is the not-a-threadvar sentinel; of the five Alloc* paths only AllocVar wrote it, so AllocParam / AllocArray / AllocDynArray / AddConst left EnsureSymCapacity's SetLength ZERO, which that test accepts as a valid offset. Whether a symbol tripped was pure index arithmetic -- capacity never shrinks across the per-frontend SymCount reset, so a slot is -1 only if an earlier pass's AllocVar left it that way -- which is why it hid. All five paths now write the sentinel and the capacity fill seeds -1 for a slot no allocator has reached. Reproducer: test/test_a_threadvar_program_does_not_lower_ordinary_symbols_through_gs.pas answers 39363342 where 78 is the sum, on pin v408."
---

# A symbol a threadvar program never declared is lowered as a threadvar

## How it was found

Not by looking for it. Adding **one unused integer constant** to
`lib/rtl/palthread.pas` flipped `test/test_a_threadvar_is_per_thread.pas` from
10/10 clean to 10/10 SIGSEGV — same compiler, one line apart, and the pinned
compiler reproduced it identically, so it was never the branch under edit.

A crash that moves when you add an unrelated declaration is about symbol
**numbering**, not about the declaration. `PXXDBG=a.ir:Body` said it outright:

```
passing:   0: load_sym a=331 ... [sym=arg]
+1 const:  0: tlsbase ... / 1: load_mem a=0
```

The procedure's own **parameter** had become a read of the thread block's first
word. `idx := Integer(PtrUInt(arg))` then indexed an array with a garbage value,
which is the only reason this ever crashed.

## The defect

`ir_codegen.inc`, `RewriteThreadVarRefs` — the whole test:

```pascal
if (sym >= 0) and (sym < SymCount) and (SymTlsOffset[sym] >= 0) then
```

`-1` means *not a threadvar*. `EnsureSymCapacity` grows the parallel arrays with
`SetLength`, which zero-fills — and `0` is a perfectly valid TLS offset to that
comparison. Only `AllocVar` wrote the sentinel; `AllocParam`, `AllocArray`,
`AllocDynArray` and `AddConst` did not.

It stayed invisible for two compounding reasons:

- The pass early-exits on `TlsUserUsed = 0`, so only a program that declares a
  threadvar is affected at all, and there are few.
- Capacity never shrinks across the per-frontend `SymCount` reset, so indices are
  **reused**. A slot carries `-1` if some earlier pass's `AllocVar` happened to
  sit there. Whether a given parameter lands on a virgin slot is arithmetic, so
  the same source compiles correctly until something upstream shifts by one.

## The fix

`compiler/symtab.inc`: the sentinel in all five `Alloc*`/`AddConst` paths, plus
`for i := SymCapacity to n - 1 do SymTlsOffset[i] := -1;` beside the existing
`SymHashBkt` fill. The per-allocator write is the load-bearing half — it is what
clears a **reused** slot; the capacity fill only covers slots nobody reached yet.

## Measurements

| | pin v408 (unfixed) | fixed |
| --- | --- | --- |
| `test_a_threadvar_program_does_not_lower_ordinary_symbols_through_gs` | `params=39363342` — GS LEAK | `params=78 78` — NO GS LEAK |
| `test_a_threadvar_is_per_thread`, palthread + 1 unused const | 10/10 SIGSEGV | 10/10 `THREADVAR OK` |
| same, padding sweep 0..8 unused consts | pass, then 8 x SIGSEGV | 9 x pass |

The new fixture needs `uses palthread` and a little padding to witness the bug,
because the trigger is index arithmetic. Swept against the unfixed compiler over
padding 0..24: **0 and 1 pass, 2..24 all leak** — a broad plateau, so it keeps
witnessing across RTL drift. It is a witness; the guarantee is the sentinel.

## Sibling check

`SymAllocSize` is written in four of the five paths and its zero-fill is inert.
Every other field initialised only in `AllocVar` (`SymCLongRank`,
`SymObjDataExternOnly`, `SymCStaticLink`, `SymObjDataScope`, `SymObjRuntimeCopy`)
wants `False`/`0`, which is what the zero-fill gives. **`SymCModule` wants `-1`
and gets `0`, a valid module index** — same shape, not reached by any measurement
here, and worth its own look by whoever owns the C frontend's linkage.
