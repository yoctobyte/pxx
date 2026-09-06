---
slug: bug-a-an-array-low-bound-is-answered-by-two-mechanisms-and-a-deref-uses-the-other
title: "An array's low bound is answered by two mechanisms, and which one you get depends on the SPELLING of the container"
track: A
prio: 40
type: bug
blocked-by: []
status: done
owner: frankH
created: 2026-09-04
summary: "`a[i]` and `p^[i]` over the same `array[1..4]` reach IR by different bound machinery: the parser folds the low bound into the SUBSCRIPT for a deref, while for an identifier it leaves the subscript raw and IR lowering subtracts `Syms[].ConstVal`. ir.inc's `lo` ladder has an AN_IDENT arm and an AN_FIELD arm and no AN_DEREF arm, correctly, because the parser already paid for that shape. Any THIRD producer of an AN_INDEX must now guess which convention its container follows — and the for-in builder guessed wrong and shifted every element, silently."
---

# The two mechanisms

Measured with `PXXDBG=a.ast`, `array[1..4]`, same program:

| source | AST built | who subtracted the bound |
| --- | --- | --- |
| `x := a1[1]` | `AN_INDEX(AN_IDENT, 1)` | **IR lowering**, from `Syms[].ConstVal` |
| `x := p1^[1]` | `AN_INDEX(AN_DEREF, 1 - 1)` | **the parser**, folded into the subscript |

Both are correct today and both produce the right value. Neither is a defect on
its own. The defect is that **the answer to "has the low bound been applied
yet?" is not a property of the node — it is a property of how the node was
spelled**, and nothing in the AST records which convention a given `AN_INDEX`
follows.

`ir.inc`'s `lo` ladder (~2774) reads:

```
AN_IDENT -> Syms[].ConstVal
AN_FIELD -> RecFieldArrLo
(no AN_DEREF arm)
```

That omission is not an oversight — it is the ladder correctly declining to
subtract a bound the parser has already subtracted. Which is exactly what makes
it a trap: **the ladder looks incomplete and is not, and the comment saying so
does not exist.**

# What it cost, already

`BuildForInArrayLoop` (`pasparser_stmt.inc`) synthesises its own `AN_INDEX`
without going through the parser, so it inherits neither convention. Over
`array[1..4]` holding `11 22 33 44`, `for x in p^` iterated as
**`22 33 44 4310536`**; over `array[5..7]`, as **`0 0 4`**. Shifted garbage, no
diagnostic. Fixed in [[bug-p-for-in-over-a-deref-ignores-a-non-zero-low-bound]]
by having the builder emit `__i - lo` for a deref container — i.e. by teaching a
**third** site the spelling-keyed rule, which is the wrong shape of fix and is
commented as such at the site.

This is the general form: any future producer of a subscript that does not come
straight out of `ParseFactorCore` has to know this, and there is nowhere it is
written down except in that one comment and this ticket.

# The repair, and the precedent is eight lines away

`FrozenStrElemCapOf` sits in `ir.inc` about eight lines above the `lo` ladder,
and it is the same problem already solved: the frozen-string **capacity** used
to be answered per-spelling across the identical three shapes, and it was made
**node-keyed** — one function, asked once, that answers for any node.

Do that for the low bound. `ArrayLoOf(node)` answering `AN_IDENT` /
`AN_FIELD` / `AN_DEREF` / a call result uniformly, then:

1. every consumer asks it instead of laddering, and
2. the **parser stops folding** the bound into the deref subscript, so there is
   one convention and an `AN_INDEX` means the same thing everywhere.

Step 2 is the load-bearing half and it is the risky half — it changes what an
existing AST shape means, so anything that reads `AN_INDEX(AN_DEREF, …)` and
compensates has to be found first.

# Gate

Track A's, plus: the low-bound rows in `test/test_forin_deref_ptr_array.pas`
(`lo1direct` / `lo1deref` / `lo5deref` / `negderef`, all generated from fpc
3.2.2) must stay green **with the compensation in `BuildForInArrayLoop`
DELETED** — that deletion is the positive control that step 2 actually
landed, and leaving the compensation in place would keep them green for the
old reason.

Note the shape of the assertion the rows use: they compare a deref spelling
against the DIRECT spelling of the same array, so a change that shifts both
identically cannot pass.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 4d718f119.

---

# Resolution (frankH, 2026-09-06)

Both steps landed together, because step 1 alone is a regression: adding an
AN_DEREF arm to the ladder while the parser still folds subtracts twice.

**Step 1.** `ArrayLoOf(node)` in `ir.inc`, beside `FrozenStrElemCapOf`, which is
the same repair for the frozen-string capacity and is the precedent the ticket
named. AN_IDENT / AN_FIELD / AN_DEREF, one question, one answer. The ladder's
old `isArr` guard on the AN_FIELD arm is gone: `RecFieldArrLo` already returns 0
unless the field is a static 1-D array, so the guard could not change an answer.
Checked in the source, not assumed.

**Step 2, the load-bearing half.** `FoldDerefArrayLowBound` and its three call
sites are DELETED, and so is `BuildForInArrayLoop`'s deref arm. An AN_INDEX
subscript is now RAW for every spelling. Confirmed with `PXXDBG=a.ast` on the
ticket's own probe: `p1^[1]` builds `AN_INDEX(AN_DEREF, 1)` where it used to
build `1 - 1`, the same node shape `a1[1]` has always had.

The fold's comment counted its own call sites wrong — "THREE for a day", then
four, actually three — and told the reader to re-derive rather than trust it.
Re-derived from the real predicate (who allocates an AN_INDEX over a deref):
three, all in `pasparser_lval.inc`.

## What I nearly shipped, and what caught it

The new deref arm answered for **every** rank. `BuildFlatNDIndex` already
subtracts every dimension's low bound including dim 0, so for a rank >= 2
pointee the bound was paid twice:

```
p^[1,1]    over array[1..3,1..3]   read 0        want 11
p3^[2,1,5] over array[2..3,1..2,5..6] read 4310984  want 215
p^[2,2] := 999                     stored to a different element
```

It survived `make compiler/pascal26` and would have survived the ticket's own
specified control, which is rank 1. What caught it was the DELETED code's
comment: the fold carried an explicit N-D exclusion, so I went looking for
where that exclusion had gone. **The guard was in the thing I removed.**

Root cause of the near-miss, and it is the same disease one level down: an N-D
array SYMBOL carries `ConstVal` 0 and keeps its bounds in the N-D dim table,
while `DerefPtrArrayInfo` hands back `NDInfoLo[0]` whatever the rank is. The two
carriers disagree about what "the low bound" means for an N-D array. Guarded on
`NDInfoNDims < 2`, read immediately after the call that fills it.

## The fixture does not go red at the pin, deliberately

`test/test_an_array_low_bound_is_one_answer_for_every_spelling.pas` — 27 rows,
wired into `test-core`, green under pxx and under fpc.

**The pinned compiler PASSES it**, and that is not a hole. The old
two-mechanism code was *correct* for every shape here; the defect was a latent
trap, not a wrong value. A pin control would pass and certify nothing, which is
exactly the "guard that cannot fail" shape. Guarded by ABLATION instead, both
directions the single convention can break:

| ablation | result |
| --- | --- |
| `ArrayLoOf`'s deref arm returns 0 | 10 rows fail — `deref lo1` reads 22 for 11, a store lands on the neighbour |
| deref arm answers for rank >= 2 | the N-D deref rows fail — `p^[1,1]` reads 0 |

The second is not hypothetical; it is what I shipped for one build.

The ticket's own specified control also holds: the `lo1deref` / `lo5deref` /
`negderef` rows of `test_forin_deref_ptr_array.pas` are green **with the
`BuildForInArrayLoop` compensation deleted**, which is the assertion that step 2
actually landed rather than being masked.

## Inert until the next pin

`$(PXX_STABLE)` consumers see none of this. Nothing in `lib/**` depends on it —
the old behaviour was correct — so this is a trap removed, not a bug shipped.
