---
track: P
prio: 55
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
found-by: frankB
summary: "A local or parameter referenced with a DIFFERENT CASE from its declaration silently resolves to an outer symbol of the same name. `procedure Bump(Counter: Integer); begin counter := 55; end;` writes the GLOBAL `counter` and leaves the parameter alone, where fpc 3.2.2 writes the parameter. Reads, writes and by-ref intrinsics are all affected (`Inc(counter)` increments the global). Cause is visible in `FindSym` (symtab.inc ~4827) and its own comment states the intent it does not implement: the function makes TWO FULL PASSES over the hash chain, exact-case then case-insensitive, so case-exactness is ranked ABOVE scope depth. The nearer symbol is only reached in pass 2, by which time an exact-case match anywhere in any visible scope has already won. Boundary measured: with no exact-case match anywhere BOTH compilers pick the local, which is the control that identifies the two-pass order as the mechanism rather than case-folding in general."
---

# An exact-case match in an outer scope beats a case-insensitive one in a nearer scope

Measured 2026-09-06 at compiler `b50b1643e1a8` against fpc 3.2.2. Found while
probing an unrelated accessor ablation; **no ticket led here.**

```pascal
program shadow4;
var counter: LongInt; ok: LongInt;
procedure Bump(Counter: Integer);
begin
  counter := 55;      { the lower-case spelling of the PARAMETER Counter }
  ok := Counter;      { must read 55 }
end;
begin
  counter := -1; ok := 0;
  Bump(7);
  WriteLn('global counter=', counter, ' seen=', ok);
end.
```

| | global `counter` | `ok` (the parameter) |
| --- | --- | --- |
| **pxx** | **55** | **7** |
| fpc 3.2.2 | -1 | 55 |

Both halves are wrong and they are wrong in opposite directions: the global is
corrupted and the parameter keeps its old value. **Silent** — no diagnostic, and
`--strict-case` does not fire on it either (measured: the program above compiles
clean under the flag).

## The boundary, which is what names the mechanism

| shape | pxx | fpc |
| --- | --- | --- |
| same-case reference to a parameter | parameter | parameter |
| **different-case reference to a parameter** | **outer** | parameter |
| **different-case reference to a LOCAL** | **outer** | local |
| `Inc(counter)` on a parameter `Counter` | increments the outer | increments the parameter |
| different-case, **no exact-case match anywhere** (global `COUNTER`, local `Counter`, reference `counter`) | local | local |

The last row is the control. It is the case where the exact pass finds nothing,
so the case-insensitive pass runs and the ordinary innermost-first walk gives the
right answer — which is why this is not "pxx folds case wrong" but specifically
"pxx ranks case-exactness above scope depth".

A `for I := 1 to 3` over a local `i` also works, for the same reason: no outer
`i` exists to win the exact pass.

## Cause

`FindSym` (`compiler/symtab.inc`, ~4827) walks the hash chain twice:

1. `StrEqual` (exact) over the whole chain, and
2. `CaseEqual` over the whole chain, for `not SymCaseSensitive[i]` symbols.

**Its own comment says what it means to do and does not:**

> *Exact-case match first, innermost scope out (preserves shadowing). ... Hash
> chain is NEWEST-first, so walking it is the linear downto order.*

Innermost-first is true WITHIN a pass. Across the two passes it is false, and
shadowing is exactly what the structure gives up: an exact match in the outermost
scope beats a case-insensitive match in the innermost one. Per CLAUDE.md's
comment-vs-code rule, one of the two is wrong and here it is the code — the
comment states the Pascal rule correctly.

## Why the obvious one-pass fix is not the fix

Merging the passes into `exact or (CaseEqual and not SymCaseSensitive[i])` lets
chain order alone decide, and chain order is DECLARATION order, not scope depth.
That is right for Pascal and wrong for NilPy, where `SymCaseSensitive` exists
precisely because `Foo` and `foo` are two different symbols in one scope and the
exact one must win regardless of which was declared later.

The shape that satisfies both is to make the passes **per enclosing block,
innermost outward** — exact then case-insensitive within each block before
moving out — rather than exact-everywhere then insensitive-everywhere. That is a
restructure of the walk, which is why this is a ticket and not a microfix.

## Gate

The five boundary rows above as one fixture, byte-identical to fpc; plus
`tools/run_fgl_corpus.sh` and the conformance suite, because this changes name
resolution for every program and the failure mode is a silently different symbol
rather than an error.

## Neighbour

[[bug-p-strict-visibility-is-silent-on-records]] is the other case of a
resolution-time rule that is opt-in and covers less than its name suggests.
