---
summary: "Copy() on a NESTED dynamic array (`array of array of T`) is refused. It used to segfault: the raw byte copy moved sub-array handles using the DEEPEST element's size. FPC supports it."
type: feature
track: A
prio: 45
---

# `Copy` on a nested dynamic array

- **Type:** feature — Track A (IR lowering). Files: `compiler/ir.inc` (`AN_DYN_COPY`),
  `compiler/parser.inc` (the two guards).
- **Opened:** 2026-08-06, after the crash below was turned into a diagnostic.

## What it did before, and how it was found

```pascal
type TG = array of array of Integer;
var g, h: TG;
...
h := Copy(g, 0, 2);
writeln('h00=', h[0][0], ' h11=', h[1][1]);   { SIGSEGV on h[1][1] }
```

`AN_DYN_COPY` takes its element size from the source symbol's **base** element
type — `TypeSize(tyInteger)` = 4 — but a nested array's elements are sub-array
HANDLES, 8 bytes on x86-64. So the copy strided by 4: `h[0][0]` was right by
luck (offset 0) and `h[1]` read a bogus handle. Reproduced on
`stable_linux_amd64/default/pinned`, so it was never a regression, just a crash
nobody had asked for.

Now refused with a diagnostic, exactly as dynamic-array `Delete` and `Insert`
already refuse the same shape:

```
Copy: nested element type not yet supported for dynamic-array Copy
```

FPC accepts it and prints `lenh=2 h00=1 h11=4`.

## What implementing it needs

Two things, and the second is the one that bites:

1. **The handle stride.** `dcElemSz` must be `TypeSize(tyPointer)` when the
   source's `SymDynDepth > 1` (target-correct: a handle is 4 bytes on i386 /
   arm32 / riscv32), and the fresh temp must be allocated at the source's depth —
   `AllocDynArray('', dcElemTk, dcDepth)` instead of the hardcoded `1` — so its
   scope-exit release recurses through the levels.
2. **The element-aware retain.** The copied sub-array handles need a refcount,
   or the temp's recursive release frees blocks the source still owns. The
   machinery is already there and already used one line away: `AN_DYN_COPY` now
   calls `PXXDynArrayRetainImmediate` for `tyAnsiString` / managed-record
   elements after the byte copy (see the note in that arm). A nested element is
   the same problem with `depth` > 1, which `PXXDynArrayRetainImmediate` already
   takes as a parameter — so this is very likely just widening that call's
   condition and passing the real depth.

Note the semantics `Copy` must land on, verified against FPC and asserted by
`test/test_nested_alias.pas`: `Copy` detaches **one level**. The result gets a
fresh outer block whose elements are the SAME sub-array handles, so writing
`h[0][0]` still reaches `g[0][0]`. A deep copy is per level, which is also why
[[bug-p-copy-rejects-a-dynamic-array-expression-that-is-not-a-bare-name]] matters
— `local[0] := Copy(shared[0])` is how you spell the second level.

## Why only 45

The crash is gone, which was the urgent part, and the diagnostic names the
limitation. Nothing in the tree needs nested `Copy` today. Do it when something
does, or alongside the sibling ticket above since both live in `AN_DYN_COPY`.

## Gate
The repro above matching FPC on every target, `Copy` on a 3-level array,
managed leaf elements at depth (`array of array of AnsiString`), and the whole
thing under `-dPXX_HEAP_DEBUG` — which is what caught the missing retain on the
depth-1 path and is the only way the retain question gets answered honestly.
Plus `test/test_dynarray_copy*.pas` and `test_nested_alias.pas` staying green.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `h := Copy(g, 0, 2)` on
`array of array of Integer` still stops at
`Copy: nested element type not yet supported for dynamic-array Copy`, so
nothing landed incidentally. FPC accepts it, so this is **compat** surface —
but the refusal is loud and replaced a segfault, which is the opposite of the
silent-wrong class that gets promoted to a bug. Stays a feature.
