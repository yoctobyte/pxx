---
slug: bug-a-continue-in-a-for-in-loop-never-advances
track: A
prio: 55
status: done
resolved: PENDING-COMMIT
---

# `Continue` inside a `for-in` loop hangs the program

```pascal
SetLength(dy, 5);
for i := 0 to 4 do dy[i] := i;
for n in dy do
begin
  if Odd(n) then Continue;
  Write(n);
end;
```

Prints `0`, then spins forever. fpc 3.2.2 prints `024`.

**Every container kind**, and it is not a diagnostic-quality problem — the
program hangs:

| loop | before |
| --- | --- |
| `for n in <dynamic array>` + Continue | **hang** |
| `for n in <fixed array>` + Continue | **hang** |
| `for c in <string>` + Continue | **hang** |
| `for e in <enum type>` + Continue | **hang** |
| the same loops with `Break` | fine |
| plain `for` + Continue | fine |
| `while` + Continue | fine |

## Cause

`for-in` is desugared in the parser into an indexed `while`, so every target
gets it from shared lowering. The increment sat at the **end of the body**:

```pascal
innerSeq := GenMakeSeq(assignX, GenMakeSeq(bodyNode, GenMakeSeq(incNode, -1)));
```

i.e.

```
__i := lo;
while __i <= hi do
begin  __x := C[__i];  BODY;  __i := __i + 1;  end
```

`AN_WHILE`'s continue target is `startLabel`, the **condition test**
(`ir.inc`: `IRLoopStackContinue[IRLoopStackDepth] := startLabel`). A `Continue`
therefore jumps over `__i := __i + 1` and re-runs the same element forever.
`AN_FOR` and `AN_REPEAT` both allocate a separate `continueLabel` placed *after*
the body and *before* the step, which is exactly why the built-in loops are
fine — the desugar borrowed `AN_WHILE`, which has no such slot.

The C frontend hit the identical problem with `for (init; cond; post)` and says
so in its own comment:

> a `continue` must still run `post`, but the loop machinery's continue target
> is the while condition. So we desugar to a constant-true loop that runs `post`
> at the TOP (guarded by a first-iteration flag)…

Two frontends, one AN_WHILE limitation, and only one of them had noticed.

## Fix

Advance at the **top**, which needs no flag here because the counter is ours:

```
__i := lo - 1;
while __i < hi do
begin  __i := __i + 1;  __x := C[__i];  BODY;  end
```

`Continue` now lands on the condition, falls into the increment, and proceeds.
Applied to all **three** desugars that had the shape:

1. `BuildForInArrayLoop` — arrays (dynamic, fixed, non-zero-based static, N-D
   by row) and strings.
2. `ParseForInEnumTypeAST` — `for e in TEnum`. This one additionally gains a
   **hidden Integer counter** instead of driving the user's enum variable
   directly, so the variable never momentarily holds `-1`, which is out of range
   for its type and a trap waiting for `{$R+}`. It is assigned from the counter
   at the top of each iteration, exactly as the array loop assigns its element.
   A side benefit: the variable is left at the **last enum value** after a normal
   exit rather than one past the end.

3. `BuildForInSetLoop` — `for e in <set>`, both a set variable and a bare set
   constructor. **This one was missed on the first pass** and found by re-reading
   the sibling builders rather than by any test: the sweep's set rows happened
   not to use `Continue`, and the two rows that would have were refused at
   compile time for an unrelated reason (see below). Same counter shape, already
   using a hidden Integer ordinal for its own reasons.

The other four `for-in` desugars (the enumerator/`GetEnumerator` forms and the
generator form) already advance inside the condition via `MoveNext`, which *is*
the continue target, so they were never affected and are unchanged.

Three copies of one loop shape, two of them broken, is the
`normalise-dont-special-case` pattern again — but here the duplication is
defensible (an index scan, an ordinal scan and a membership scan really are
different loops), so what would actually have prevented this is a **test that
puts `Continue` in every for-in form**, which is what the regression test now
is.

## Verification

`test/test_continue_in_a_for_in_loop.pas`, wired into `test-core` **behind a
`timeout 30`** so a regression fails the suite instead of wedging it.
Byte-identical to fpc 3.2.2. Rows chosen for what they would catch:

- `all` — `Continue` on *every* iteration, the shape that spins if the advance
  is reachable only by falling off the body's end.
- `static` — an `array[5..8]`, so the rewritten `lo - 1` and `< hi` bounds are
  exercised with a non-zero index base (`AN_INDEX` subtracts the low bound
  itself, so an off-by-one here reads shifted garbage rather than crashing —
  the failure mode of `bug-pascal-forin-variants-wrong-output`).
- `empty` / `one` / `estr` — the rewritten bounds must neither gain nor lose an
  iteration at zero and one element, for both an array and a string.
- `break` — still exits early and still leaves the rest unvisited.

`make compiler/pascal26` fixedpoint converged in 1 round; `tools/gate.sh quick`
green.

## Found by

A 30-program iteration/open-array/`array of const` differential. The run simply
never finished — `ps` showed one program at 99.9% CPU for six minutes. A hang
does not show up as a diff, so nothing in the sweep's own reporting would have
flagged it; it was visible only because the harness stopped making progress.
Worth remembering for future sweeps: **a differential harness reports wrong
answers, not missing ones.** 27 of the other 29 rows matched FPC.

And the sweep did not find the set variant at all — it had set rows and it had
`Continue` rows, but no row with both. Coverage of a cross-product needs the
cross-product.

## Left open, from the same sweep

`for n in st` where `st: set of 0..7`, and `for c in cs` where `cs: set of Char`,
are both refused:

```
for-in: set iteration supports `set of <enum>`, `set of Char` or an ordinal set
constructor
```

The message names `set of Char` as supported and then refuses it, so at minimum
the diagnostic is wrong. Filed separately as
`bug-a-for-in-over-a-set-variable-refuses-the-kinds-its-error-message-claims`.
