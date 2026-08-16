---
track: U
prio: 30
type: decide
blocked-by: [bug-p-set-literal-elements-are-not-type-checked]
summary: "RE-SCOPED 2026-08-16 after re-measurement: the original table was wrong (pxx is NOT order-independent — it flips on all four bracket shapes, FPC only on the genuinely ambiguous one). Most of the difference is bug-p-set-literal-elements-are-not-type-checked, filed separately; fix that and content disambiguates as it does in FPC. What is left to decide is the true tie only: `[dTue]`, `[dMon, dWed]`, `[]`."
---

# `[x]` where one overload takes a set and another takes `array of const`

- **Type:** decision — **Track U**. Escalated rather than guessed while closing
  [[bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set]].
- ~~**Nothing is broken today.**~~ **Struck 2026-08-16 — that was wrong.** Two
  of the four bracket shapes are defects: one rejects a program FPC compiles,
  and one silently returns a wrong answer. See the re-measurement at the bottom;
  read that first, the analysis below it was built on a table that does not
  reproduce.

## The shape

Two units, both exporting `k` with `overload`: one takes `TDays = set of TDay`,
the other takes `array of const`. Then:

```pascal
k([dTue]);     { a set literal? or a one-element TVarRec vector? }
```

Both readings are well-typed. The parser must choose BEFORE overload
resolution, because the choice determines how the brackets are parsed at all.

## Measured — and the reference implementation does not settle it

| uses order | FPC 3.2.2 | pxx |
| --- | --- | --- |
| set-unit first, array-of-const unit last | `k-aoc: n=1` | `k-aoc: n=1` |
| array-of-const unit first, set-unit last | **`k-set: dTue`** | `k-aoc: n=1` |

**FPC flips its answer with uses-clause order**, which means "be FPC-faithful"
has no single answer to be faithful to. pxx is at least consistent — it always
reads the brackets as `array of const` once a candidate offers one — but it
differs from FPC on the second row.

## The options

1. **Leave it** (today). pxx is order-INDEPENDENT and picks `array of const`.
   Defensible on its own terms: order-independence is a better property than
   matching an order-dependent reference, and the `--strict-fpc` umbrella exists
   for cases where bug-for-bug parity is actually wanted.
2. **Match FPC row for row**, order dependence included. Costs a rule nobody can
   explain and that a user cannot predict.
3. **Refuse it as ambiguous**, and require a cast or a distinct name. Loudest,
   and arguably the honest answer for a construct where the reference
   implementation contradicts itself — but it would reject programs FPC
   compiles, which the compat rule normally forbids.

My recommendation is **1**, with this ticket as the record and a row in the
dialect notes if it stays. Option 3 is tempting and is the only one that never
silently does the wrong thing, but "rejects a program FPC accepts" is a real
cost for a corner with no known user.

## What would change the answer

A real program that declares both at the same slot. None is known — this was
constructed to probe the boundary of the fix next door, and the regression test
there deliberately asserts only the unambiguous form.


## RE-MEASURED 2026-08-16 (Track U session) — the table above is WRONG

The owner asked to see the ambiguity directly before deciding, so both compilers
were re-run on identical sources. The result contradicts this ticket's central
claim, which was the entire basis of its recommendation.

**"pxx is at least consistent — it always reads the brackets as `array of const`
once a candidate offers one" is false.** pxx flips with `uses` order too, and in
the opposite direction from FPC.

Four bracket shapes x two `uses` orders, pxx vs FPC 3.2.2:

| call | pxx set-first | pxx aoc-first | FPC, both orders |
| --- | --- | --- | --- |
| `[dTue]` | `k-set` | `k-aoc` | **flips**: `k-aoc` / `k-set` |
| `[dMon..dWed]` (range: set-only) | `k-set` | **compile error** | `k-set` — consistent |
| `['a', 1]` (mixed: aoc-only) | **`k-set: dTue`** | `k-aoc: n=2` | error — consistent |
| `[]` | `k-set` | `k-aoc` | `k-aoc` — consistent |

**FPC is order-dependent in exactly ONE row** — the genuinely ambiguous
`[dTue]`. pxx flips on all four. So the framing "FPC contradicts itself, there
is no reference to copy" was too kind to pxx and too harsh on FPC.

Two rows are outright defects, not corners:

- **row 2, aoc-first: a program FPC compiles, pxx rejects.** A range `a..b` is
  set-only syntax, and the parse has already committed to `array of const`.
- **row 3, set-first: a SILENT WRONG ANSWER.** `k(['a', 1])` binds the set
  overload and reports `dTue` — because `'a'` is ordinal 97, `1` is ordinal 1,
  and `dTue` is ordinal 1.

## Row 3 is not about overloading, and it is now its own ticket

Isolated with no overloads anywhere: `TakesSet(['a', 1])` against a plain
`set of TDay` parameter compiles and answers `dTue`.
[[bug-p-set-literal-elements-are-not-type-checked]] (P, prio 60) — pxx never
checks a set literal's elements against the element type, so `[cGreen]` (a
different enum), `[True]` and `[1]` are all accepted, and `[99]` silently yields
the empty set. FPC rejects every one.

**That bug is why this decision looked harder than it is.** pxx cannot use
bracket contents to disambiguate while *every* bracket list is a valid set
literal.

## Why FPC gets the other three rows right — the architecture, not a rule

FPC does not commit at parse time. `[...]` always becomes a neutral
`tarrayconstructornode` (`pexpr.pas:3375-3400`; ranges become
`carrayconstructorrangenode`), and it is converted to a set later, driven by the
TARGET type (`arrayconstructor_to_set`, `htypechk.pas:3000`). Content and target
both get a say, which is why ranges survive in either `uses` order.

And the one row FPC *does* flip on is not an oversight either. In `para_allowed`
(`htypechk.pas:2077-2084`):

```pascal
setdef :
  begin
    { set can also be a not yet converted array constructor }
    if (p.resultdef.typ=arraydef) and
       is_array_constructor(p.resultdef) and
       not is_variant_array(p.resultdef) then
      eq:=te_equal;
  end;
```

A `set of T` parameter rates an array-constructor argument `te_equal` — an
**exact** match. An `array of const` parameter rates it exactly as well. Two
exact matches is a genuine TIE, and the tie is broken by the order candidates
were collected, i.e. `uses` order. FPC is not being inconsistent; it has two
equally-good answers and no preference rule.

**Checked against FPC trunk** (the owner asked whether nightly fixes it): that
block is present **verbatim in trunk** — same code, same comment, fetched from
`gitlab.com/freepascal.org/fpc/source` `main`. So this is not a "current FPC
stable" footnote waiting to be dated; it is FPC's design, and there is nothing
pending to be compatible with later.

Scope of that check, stated honestly: it covers the `para_allowed` RATING site,
which is the one that creates the tie. The second site
(`arrayconstructor_to_set`, `htypechk.pas:3000`) could not be read from trunk —
the raw file truncates in fetch — and no search of the issue tracker turned up a
report. apt offers only 3.2.2, so **if certainty is wanted the answer is to
build trunk and re-run the eight cells**, roughly a 20-minute job. Absent that,
treat "trunk behaves the same" as strongly indicated rather than measured.

## What is actually left to decide

After [[bug-p-set-literal-elements-are-not-type-checked]] lands, the ambiguous
set is only where the elements genuinely ARE members of the set type:
`[dTue]`, `[dMon, dWed]`, `[]`. Everything else is decided by content.

For that residual, the owner's framing applies: *overloading with ambiguous
parameters is bad programming.* So the options re-rank:

1. **Refuse it as ambiguous**, requiring a cast or a distinct name. After the
   element fix this rejects almost nothing real, it never silently does the
   wrong thing, and it is honest about a case where FPC itself has no preference
   rule. **Now the leading option**, where it was third.
2. **Tie-break by binding candidate** (last-`uses`-wins, today's behaviour once
   the other rows are fixed). Explicable in one sentence and consistent with
   ordinary Pascal scope hiding — but it silently picks, which is what makes
   option 1 better for a true tie.
3. **Match FPC row for row.** Now clearly wrong: FPC's row-1 answer is a tie
   broken by candidate collection order, so "compatible" here means replicating
   an arbitrary internal ordering, not a rule.

`--strict-fpc` has a real target for rows 2, 3 and 4 — FPC is consistent there
and pxx currently misses two. Row 1 is the only one it cannot be faithful to,
because there is no fixed FPC behaviour to be faithful to.

**Parked behind the P bug**: deciding the residual before the element check
lands would be deciding it against the wrong ambiguity set.
