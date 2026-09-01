---
type: bug
track: A
prio: 7
summary: a managed function result discarded at statement level was never released — 979 of 1000 string handles and 1968 dyn-array handles leaked where FPC leaks none; two defects, and the helper for it already existed behind a false premise
owner: frankB
---

## What

Extended syntax lets a function be called as a statement. The result is a fresh
handle with a +1 count that nobody stores, and nothing ever released it.

```pascal
for i := 1 to 1000 do MkS(i);      { live=979  }
for i := 1 to 1000 do MkArr(i);    { live=1968 }
```

FPC compiles the identical program and `-gh` reports **0 unfreed memory blocks**.

A managed **record** result was already clean — it goes back through an sret
buffer the caller allocates and finalizes. Only the register-returned kinds
(string, dyn array) had no owner.

## Three findings, and only the first is the one the title names

**1. The helper already existed and was switched off.** `IRDropManagedStrResult`
did exactly this job, gated `if not PyProgramMode then Exit`, on the stated
premise that *"Pascal has no value-discarding expression statement"*. The NilPy
arm of this bug was found and fixed (`bug-nilpy-discarded-string-result-leaks`);
the Pascal sibling was left standing behind a mode gate. The premise is simply
false. This is the `normalise-dont-special-case` failure mode in its purest
form — the second path is the one that stays broken — and the guard against it
("fixed one arm of a double case? grep for the sibling") is what the mode gate
defeated, because the sibling *was* grepped and *did* look handled.

**2. Ungating it changed nothing, because the type tag was not the thing.** A
function called as a statement is lowered as a **void** call:

```
#8206 kind=8 tk=0            { AST: AN_CALL, tyUnknown }
23: call a=735 b=22 ival=1 tk=0
```

The return type is erased before the discard site, so every type-tag test reads
`tyUnknown` and no managed check can fire. The **proc table** still knows
(`Procs[pi].RetType`), and the AST node still carries the proc index. Asking the
tag was correct about something else: it was correct about the *lowered* node,
and the question was about the *callee*.

**3. That still left the bare-statement bodies leaking.** After (2),
`for .. do begin MkS(i); end;` was clean at live=4 while
`for .. do MkS(i);` was still at 979 — a loop body that is a bare statement
reaches neither `AN_BLOCK` nor the `AN_SEQ` spine, which are the only two places
the discard ran. This is the **same coverage hole, one construct over**, as the
`AN_IF`-arm flush and the loop-body flush before it: the fix covered the arms it
was written for, and reads as complete. The park now runs at all eight
statement-body positions, the same set the flush was added to.

## Measured

`-dPXX_ALLOC_CENSUS`, 1000 trips, last threshold. Pre-fix column is a rebuild
with the change stashed (`converged after 1 round(s)`), not a recollection.

| context | pre | post |
| --- | --- | --- |
| `for .. do MkS(i);` (bare body) | 979 | 4 |
| `for .. do MkArr(i);` (dyn array) | 1968 | 4 |
| `begin MkS(i); end` | 979 | 4 |
| `if b then` / `else` arm | 979 | 4 |
| `case` value arm / `else` arm | 979 | 5 |
| `while` / `repeat` body | 979 | 4 |
| `try` body / `finally` body | 979 | 4 |
| `except` arm | 924 | 6 |
| `with` body | 979 | 4 |

Twelve contexts, every one leaking before and bounded after. Program values are
byte-identical pre and post on every row — the park must not consume the value
it parks, and the test asserts a *used* result and a stored `guard` for exactly
that direction.

Clean under `-dPXX_HEAP_DEBUG`, identical at `-O0`/`-O2`/`-O3`, and identical
output **and identical leak counts** (`allocs=8671 frees=8652 live=19`) on
x86-64, i386 and aarch64. FPC oracle agrees on the value line and reports 0
unfreed.

## Tests

`test/test_discarded_managed_result_leaks.pas`, wired into `test-core`,
`test-i386` and `test-aarch64`. Each cross row builds its **own** x86-64
comparison binary rather than borrowing `test-core`'s, so no comparison can run
against a file the target never built.

The dyn-array arm is not decoration: its temp comes from a layout descriptor, so
a wrong element width there is a target-specific double free rather than a leak.

## Fix

`IRDropManagedStrResult` → `IRDropManagedResult(astNode, irNode)`: mode gate
removed, return type read from the proc table when the node's tag is erased,
dyn-array arm added, and called at all eight statement-body positions. The name
lost its `Str` in the same edit — it parks arrays now, and an 80%-accurate name
is the worse kind.

Fixed in commit PENDING-COMMIT.
