---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`for n := 1 to n do` runs ONE iteration where FPC runs five, and `for n := 1 to n - 1` runs ZERO where FPC runs four; downto is wrong the same way (9 vs 3). Pascal evaluates the initial AND final expressions BEFORE assigning the control variable; ir.inc:12130 stores the control variable first and lowers the limit after, so a limit that reads the control variable sees the new value. Silent wrong iteration count -- no diagnostic, no crash. ROOT CAUSE LOCATED: three statements in the wrong order, plus one ordering subtlety noted below."
---

# A `for` limit that reads the control variable sees the wrong value

- **Type:** bug — **Track A** (AST→IR lowering, `compiler/ir.inc`). A's gate.
- **Found:** 2026-08-29 by `frank-optimize`, while writing an ordinary
  correctness test for
  [[feature-opt-bulk-copy-is-byte-at-a-time]]. The test **segfaulted**, and the
  crash was this: `for n := 1 to n do` read `s[1]` of an empty string because
  the loop ran once instead of zero times. The test was correct Pascal; the
  compiler miscompiled it.

## Measured against FPC 3.2.2

Same source, both compilers, x86-64:

| shape | pxx | FPC | |
| --- | ---: | ---: | --- |
| `n := 5; for n := 1 to n do` | **1** | 5 | **wrong** |
| `n := 5; for n := 1 to n - 1 do` | **0** | 4 | **wrong** |
| `n := 9; for n := 3 downto n - 8 do` | **9** | 3 | **wrong** |
| `n := 5; for n := n to 7 do` | 3 | 3 | correct |
| `for n := 1 to Bump do` (limit is a call) | 3, **1 call** | 3, 1 call | correct |

So the limit **is** correctly hoisted and evaluated exactly once — that half was
fixed already and the comment in the source says so. What is wrong is **when**.

> **The `downto` row is the one to keep.** An earlier probe here used
> `n := 5; for n := 5 downto n - 4`, which gives 5 either way — the start value
> happened to equal the old `n`, so the probe could not discriminate and briefly
> read as "downto is fine". A probe whose two hypotheses predict the same number
> is not evidence. The row above separates them.

## Root cause — three statements in the wrong order

`compiler/ir.inc`, the `AN_FOR` arm (~12130):

```pascal
  initValNode := IRLowerAST(initNode);
  storeNode := IRAppend(IR_STORE_SYM, varIdx, initValNode, ...);   { n := start  <-- FIRST }

  limitValNode := IRLowerAST(limitNode);                            { limit       <-- AFTER }
  ...
  if IRKind[limitValNode] <> IR_CONST_INT then
  begin
    forLimTmp := AllocVar(...);
    IRAppend(IR_STORE_SYM, forLimTmp, limitValNode, ...);
    limitValNode := IRAppend(IR_LOAD_SYM, forLimTmp, ...);
  end;
```

The control variable is assigned **before** the limit expression is lowered, so a
limit mentioning the control variable reads the value just stored. ISO Pascal,
Delphi and FPC all require both the initial and the final expression to be
evaluated **before** the control variable is assigned.

The routine already carries a long, correct comment about evaluating the limit
exactly once — *"`for i := 1 to n do begin ...; n := 0; end` ran ONE iteration
where FPC runs three"*. That is the same family of defect, caught one step
earlier in the loop's life and fixed there; this is the other end of the same
window, and the fix for the first did not close it.

## The obvious fix, and the subtlety that makes it not a two-line move

Reordering to *lower the limit, materialise it, then store the control variable*
fixes every row above. **But `initValNode` is a value NODE, not a register** —
the backend re-emits that subtree where it is used, which is the store. Moving
the store after the limit therefore moves the initial expression's **side
effects** after the limit's, and Pascal's order is initial-then-final.

For `for i := 1 to n`, where the initial expression is a constant or a plain
read, nothing observes this. For `for i := Next to Limit`, where both are calls,
the call order would silently swap.

So the honest fix materialises **both** into temps, in source order:

1. lower init → store into a temp
2. lower limit → store into `forLimTmp`
3. store the init temp into the control variable

with the same `IR_CONST_INT` exemption already used for the limit, so the
ordinary `for i := 1 to 10` stays byte-identical and no `-O` level regresses.

## Why it has survived

`for n := 1 to n` looks like a mistake, so nobody writes it deliberately — but it
arrives naturally from a **computed bound reusing a scratch variable**, which is
exactly how it arrived here:

```pascal
  n := i; if j < n then n := j;   { n = min(i, j) }
  for n := 1 to n do ...          { intended: iterate min(i,j) times }
```

That is ordinary code. It compiled, ran, produced a wrong count, and the only
reason it was noticed is that the wrong count happened to index out of bounds
and segfault. **A version that merely looped the wrong number of times would
have produced a plausible wrong answer and been believed** — which is what the
debugging playbook says the expensive bugs here look like.

## Gate

A's gate (`make compiler/pascal26` + self-host fixedpoint). Plus: the table above
reproduced against FPC, and — because this touches the shape of every `for` in
the compiler — a check that `for i := 1 to <constant>` and `for i := 1 to <plain
variable>` emit **byte-identical** code before and after, at every `-O` level, on
x86-64 and one cross target. The `IR_CONST_INT` exemption exists to make that
true; if it stops being true, the change is bigger than it should be.

## Not this ticket

pxx accepts `n := n` inside the body of a `for` over `n`; FPC rejects it
(*"Illegal assignment to for-loop variable"*). Per CLAUDE.md's compat table that
is *we accept a form FPC rejects* — **not a defect**. Noted so the next person
does not file it.
