---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`for n := 1 to n do` runs ONE iteration where FPC runs five, and `for n := 1 to n - 1` runs ZERO where FPC runs four; downto is wrong the same way (9 vs 3). Pascal evaluates the initial AND final expressions BEFORE assigning the control variable; ir.inc:12130 stores the control variable first and lowers the limit after, so a limit that reads the control variable sees the new value. Silent wrong iteration count -- no diagnostic, no crash. ROOT CAUSE LOCATED: three statements in the wrong order, plus one ordering subtlety noted below."
status: done
owner: frankA
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

---

## Resolved 2026-08-29 — frankA

b4's diagnosis was correct end to end, including the part that made it not a
reorder. What it could not have known from `ir.inc` alone is that **three
lowerings implement this one rule**, and a second one had the same defect.

### The fix, in `ir.inc`'s `AN_FOR`

Both bounds are materialised in source order, then the control variable is
assigned:

1. lower init → store to `forInitTmp` (skipped for `IR_CONST_INT`)
2. lower limit → store to `forLimTmp` (the existing once-only temp)
3. `IR_STORE_SYM` the control variable from the init temp

The init temp is what b4 identified: `initValNode` is a value node the backend
re-emits at its use, so moving the store past the limit without materialising
would move the initial expression's **side effects** after the limit's, and
Pascal's order is initial-then-final. `for i := Start to Lim` proves it — the
test asserts `S` then `L`, and it passed before the change, so it is a control
that could have broken and did not.

### The sibling: `SLLowerFor`, and why shape was not enough

`pasparser_stmt.inc`'s stackless-generator transform lowers `AN_FOR` a **second
time**, and sequenced `setVar` before `setLim` — the identical defect. I found
the shape by grepping, then tested it, and the first test said the opposite:
a `generator` routine answered correctly. That was the STACKFUL generator,
which goes through `ir.inc` and had just been fixed. The stackless arm needs
`; generator; stackless;` and `uses slgen`, and on it:

```
sl up   1   (plain form = 5)
sl down 9   (plain form = 3)
```

— exactly the pre-fix numbers. Fixed the same way, with its own init slot for
the same side-effect reason. **Had I trusted the first measurement I would have
closed this with one of two arms still broken**, and had I trusted the shape
without measuring I would have patched a file on a guess. Both were needed.

### Measured

| shape | before | FPC | after |
| --- | ---: | ---: | ---: |
| `n := 5; for n := 1 to n` | 1 | 5 | 5 |
| `n := 5; for n := 1 to n - 1` | 0 | 4 | 4 |
| `n := 9; for n := 3 downto n - 8` | 9 | 3 | 3 |
| `n := 5; for n := n to 7` | 3 | 3 | 3 |
| `for i := 1 to Bump` (calls) | 3, 1 call | 3, 1 call | 3, 1 call |
| `for i := Start to Lim` (order) | S then L | S then L | S then L |
| the `min` scratch idiom | 1 | 4 | 4 |
| stackless generator, up / down | 1 / 9 | — | 5 / 3 |
| stackful generator, up / down | 1 / 9 | — | 5 / 3 |

Plain form byte-compared against FPC 3.2.2 on all nine rows: identical.

### The gate line about byte-identity — corrected, not quietly passed

The ticket asks that `for i := 1 to <constant>` and `for i := 1 to <plain
variable>` emit byte-identical code before and after. **The first holds; the
second cannot, and should not.** Measured per procedure, disassembled from the
map file with addresses masked (whole-binary `cmp` is useless here — the RTL is
full of `for` loops, so every address shifts and everything "differs"):

| loop | -O0 | -O1 | -O2 | -O3 |
| --- | --- | --- | --- | --- |
| `for i := 1 to 10` | identical | identical | identical | identical |
| `for i := 10 downto 1` | identical | identical | identical | identical |
| `for i := 1 to n` | 4 insns reordered, same count | same | same | 5 reordered, same count |
| `for i := n to n + 5` | +2 insns | — | +2 insns | +2 insns |

Row 3 is the fix itself: the two stores swap, no instruction added, so
`for i := 1 to n` costs exactly what it did. Byte-identity there would mean the
bug was still present.

Row 4 is the real cost and it is worth stating plainly: a **non-constant initial
bound** now materialises into a temp, +2 instructions at loop ENTRY (once, not
per iteration). `for i := lo to hi` is common, so this is not nothing — but it
is correctness, and the alternative is the side-effect swap above.

**Possible follow-up for Track O, deliberately not done here:** the init temp is
only needed when lowering the LIMIT can change the init's value, i.e. when the
limit contains a call or an assignment. A side-effect-free limit could keep the
old shape and make row 4 identical too. That is an IR subtree walk and a new
conditional — a real analysis that can be wrong — so it does not belong in the
correctness fix.

### Found on the way, filed separately

`bug-n-a-range-loop-whose-bound-reads-the-loop-variable-never-terminates` —
NilPy's `for n in range(3, n - 8, -1)` **hangs forever** where CPython yields 2.
Same family (a bound that reads the loop variable), different lowering, and
pre-existing: it hangs on `pinned` and on builds either side of this change.
Not fixed here; it is the NilPy range path, not `AN_FOR`.

Also confirmed the ticket's own "Not this ticket" note: pxx still accepts
`n := n` inside the body of a `for` over `n`. Unchanged, and correct per
CLAUDE.md's compat table.

Self-host fixedpoint `df3e10e20b14`, converged in 1 round.

## Log
- 2026-08-29 — resolved, commit 8b35e88fa.
