# Normalise, don't special-case: give downstream ONE shape

_Design note. Sibling of `ir-as-substrate.md` and `type-identity-as-substrate.md`
— the *why* behind a class of bug that keeps recurring, not mechanics._

## The one idea

When the frontend can reach a construct through **two shapes** — a constant and
a variable, a literal receiver and a named one, a static type and a variant — it
is tempting to give each its own path. Resist it. **Normalise the special shape
into the general one** (bind the constant to a temp, box the literal into a
variable) and let a single path handle both.

The user's phrasing, which started this note:

> *"in python, it would be totally fair to move a const list or dict to a
> variable, to avoid all double cases (variable or const)"*

That is the whole idea. It is not primarily an optimisation — it is a way of
having **one** thing to get right instead of two that must stay in step.

## Why it earns its own note

Two paths do not drift because anyone is careless. They drift because a bug is
found and fixed on the path where it was observed, and the sibling is invisible
from there. The 2026-08-06 session hit this **five times in one day**, each time
as "the ticket fixed the path it could see":

| fixed once, sibling missed | how the sibling surfaced |
| --- | --- |
| `feature-nilpy-augmented-subscript-assign` — `d[k] += 1` on a STATIC base | the VARIANT base silently stored nothing (`bug-nilpy-augmented-assign-through-a-variant-subscript-is-dropped`) |
| `bug-nilpy-range-over-a-variant-bound-loops-forever` — a bound that doesn't fit | the same bound too WIDE (`bug-nilpy-for-range-loop-counter-is-32-bit-and-never-terminates`) |
| that one's own visible counter | the variant-loop-var path has its OWN counter, still 32-bit |
| `feature-nilpy-nested-comprehension` — the container-iterable path | the range path evaluated the inner comprehension once (`bug-nilpy-nested-comprehension-over-range-evaluates-the-inner-one-once`) |
| the promo guards, written against the STATIC type | a variant-held bignum walked into the Int64 helpers (`bug-nilpy-floordiv-mod-compare-and-float-narrow-a-variant-held-bignum`) |

Every one is the same failure: **two shapes, two paths, one of them fixed.** The
cost is not the second fix — it is the months in between, during which the
second path is silently wrong.

## The instance that prompted this: constants in a loop condition

`while` used to emit its condition's hoisted setup **outside** the loop. The
reasoning is in the code and is worth reading, because it is a good argument
that happens to be wrong:

> *"a literal in a while CONDITION is built once, before the loop — CPython
> rebuilds it per test; acceptable divergence, the pattern is
> `while x in ("a","b")` membership against constants."*

True for a constant, which is loop-invariant. False for everything else that
hoists through the same mechanism — a string method call is not invariant, so
`while s.startswith("a")` tested once and then spun
(`bug-nilpy-a-method-call-in-a-while-condition-is-evaluated-once`).

Note the shape of the mistake: the code reasoned about the *motivating* input
(a literal) and then applied the conclusion to the *mechanism* (anything that
hoists). That is the double case again, with the two shapes sharing one path
that is only correct for one of them.

The fix folds each sub-expression's setup into that sub-expression, so
everything is recomputed where it is used. Constants now pay an allocation per
test — correct, and needlessly so. Normalising them (bind once above the loop,
reference the variable inside) recovers that **and** keeps one path, which is
the point: the invariant case becomes a *variable*, so downstream stops having
to ask. Filed as
`feature-nilpy-hoist-constant-container-literals-out-of-a-loop-condition`, under
the umbrella `meta-constant-normalisation`.

## Live double-cases worth collapsing

Not a complete list — a starting one. Each is a place where a fix applied to one
arm will not reach the other.

- **Literal receiver vs named receiver on a subscript.** `PyMakeSuffixIndex`
  handles `"abc"[i]`; the default-indexed-property path in `pasparser_lval.inc` handles
  `xs[i]`. They have already diverged once — the `__index__` coercion had to be
  added to the named path with the comment *"A LITERAL receiver already went
  through PyMakeSuffixIndex"*, which is the tell.
- **Literal vs non-literal operand in the promo binop.** `IRPromoEmitBinop`
  picks `PromoMixedHelper` or the general helper based on `IsWideIntLit` /
  `IsWideNegLit` on the right operand. Two lowerings for one operator.
- **Static type vs variant** throughout NilPy — the largest of these, and the
  source of four of the five bugs in the table above. A guard written as
  `TypeIsPromoInt(ASTTk[node])` is a static-shape test that silently answers
  False for the variant shape.
- **`str` as a static type vs a variant** in the container/iteration paths, for
  the same reason.

## When a special case IS justified

Perf on a path measured to be hot, and then only with the **safe direction**
written down: the special case must be the one that is *provably* applicable,
and anything unproven must fall to the general path. Stated as a rule:

> Default to the general path. Take the special path only on a positive proof.
> Never the reverse.

Get that backwards and the special case silently captures inputs it is wrong
for — which is exactly how the `while` condition above came to spin. This is
also why the constant-hoist follow-up was **not** done inline with its fix: its
predicate ("is this hoisted chain provably constant?") has to fail toward
folding, and a predicate written the other way round reinstates the bug it was
meant to optimise around.

## Practical rule when you touch one of these

If you fix a bug on one arm of a double case, **grep for the sibling before you
close the ticket.** Concretely, on 2026-08-06 one `grep AllocVar(..., tyInteger)`
after fixing a 32-bit loop counter found a second live instance of the identical
bug in another file. That grep costs a minute and is the single highest-yield
habit in this whole note.

## The work list

`meta-constant-normalisation` (in `../progress/backlog/`) is the standing index
for collapsing these. Its framing is worth repeating here because it is the
reason this note exists at all, and it is **not** about speed or memory:

> When you are about to write "if this operand is a literal, do X, else do Y" —
> don't. Bind the literal to a variable and write only Y.

Each constant expression gets its own uniquely-named variable, bound once and
only read. The gain is that a future fix is single work instead of double.

## Four of these landed in two days (2026-08-25/26)

Not a coincidence worth writing down for its own sake — worth writing down
because all three had the **same tell**, and it is not the one you would
predict. In each case the second path was guarded by something that was TRUE
for the shape anyone had tested, and only for that shape.

1. **The callable bridge (Track N).** A second dispatch path ran before the
   signature preamble, skipping default-filling, arity checking and keyword
   matching. Its comment justified this: a collecting callee "has no omitted
   parameters to fill" — false the moment a defaulted parameter precedes the
   star. It survived because the only shape ever probed was `def star(a, *rest)`
   with no defaults, which is exactly the shape for which the false comment is
   true. **And the test in the tree carried that same sentence as its comment**,
   so the claim and its witness reinforced each other. Symptom when finally
   varied: silent wrong values, plus a SIGSEGV.

2. **`last_covering_sha()` (Track T).** The function already reasoned correctly
   about blame ranges and its docstring already stated the rule — but it was
   gated on the range being EMPTY, which was the symptom someone noticed first
   rather than the general case. Result: four regressions blamed on a
   23-commit window when the honest range was 179, and the 23 were precisely
   the commits that could not have caused them.

3. **The relocation tables (Track A).** Nine hand-written guard/store/store/Inc
   quartets did the same append. **Two of the nine had no cap check at all** —
   NilPy's VMT emitter wrote past the end of a fixed array into neighbouring
   BSS, silently. Note what this defeats: the campaign's mandated `MAX_*` grep
   could not find those sites, **because they never mentioned the constant.**
   A guard written nine times is a guard written eight times.

The generalisation, and the reason this section is here rather than in three
tickets: **a duplicated path is dangerous in proportion to how plausible its
justification is.** An obviously-wrong second path gets deleted early. One
carrying a reasonable-sounding comment survives for months, and the comment
then teaches the next reader — and the next test — to stop looking.

So when you find a second path, do not only check whether it is correct today.
Check what makes it *look* correct, and whether the tests were written from the
same sentence.

4. **The callable type-name table (Track N, the next day).** `PyCallableStr`
   already answered "is this bound?" from the **receiver** — tag 8 is both a
   bound method and a plain def, so the tag alone cannot tell you. The
   type-name table still answered from the tag, so `type(f).__name__` said
   `method` for a plain def. Same question, two mechanisms, one of them updated
   when the answer changed.

Four for four, all "same question, two mechanisms, one updated". That is no
longer anecdote; it is the failure mode this file exists for.

### What this says about the grep

Above, this note calls "grep for the sibling" the single highest-yield habit in
it. That still holds -- it costs a minute and it has paid out. But be honest
about tonight: **neither double case was found by the grep. Both were found by
measurement.** And the third could not have been found by it even in principle,
because the two unguarded append sites never mentioned `MAX_DATAPTRFIX`, so no
grep for the constant could reach them.

The grep finds siblings that are *spelled* alike. It cannot find one that was
open-coded under a different name, and it cannot find one whose comment
persuaded you it is not a sibling at all. So run it -- and do not let it stand
in for a differential probe. The oracles in `differential-probes.md` are what
made these visible; the grep is what makes the fix complete once you already
know what you are looking for.


See also: `differential-probes.md` (the oracles that make a silent sibling
visible at all) and `debugging-playbook.md` (measure, do not reason).
