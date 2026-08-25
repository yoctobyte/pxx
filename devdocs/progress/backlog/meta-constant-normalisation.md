---
prio: 20
track: A
type: meta
summary: "Standing index: stop writing compiler code that branches on constant-vs-variable. Each constant expression becomes its own uniquely-named read-only variable, so downstream has ONE shape to handle. Goal is less double work on future fixes, not speed."
---

# Meta: constant normalisation — one shape, so future fixes are single work

- **Type:** meta (governance / index / epic) — **Track A** (spans `parser.inc`,
  `ir.inc` and the frontends; most concrete sites today are NilPy)
- **Status:** backlog (standing index — never "done"; new constant/literal work
  links here)
- **Owner:** — (Track A)
- **Opened:** 2026-08-06
- **Origin:** the user, reviewing
  [[bug-nilpy-a-method-call-in-a-while-condition-is-evaluated-once]]:
  *"in python, it would be totally fair to move a const list or dict to a
  variable, to avoid all double cases (variable or const)"* — and, when the
  first draft of this ticket turned into an escape-analysis design:
  *"you are overthinking. mutable is not an issue. we can just put each constant
  expression as a uniquely named variable, and since we only read it.. the issue
  is more — half our work so far already takes into account constants vs
  variables. we don't want double work for now — we just want to easify future
  fixes."*

## The point

**Not** speed. **Not** memory — a constant expression may have its own variable
living for the whole program; that cost is accepted and settled.

The point is that a large amount of existing compiler code branches on
*constant-or-variable*, and every one of those branches is **two paths that a
future fix has to be applied to twice** — which is exactly the failure mode this
repo keeps hitting, where a bug is fixed on the arm it was observed on and the
sibling stays broken for months (`devdocs/dev/normalise-dont-special-case.md`
has the tally: five in one day).

So: give each constant expression its own uniquely-named variable, bound once.
Downstream then only ever sees a variable. One shape, one path, one fix.

## The rule for new code

> When you are about to write "if this operand is a literal, do X, else do Y" —
> don't. Bind the literal to a variable and write only Y.

That is the whole contract. Everything below is the backlog of places where it
was already written the other way.

One caveat, stated once and not turned into a design exercise: the variable is
**read-only by construction** — a constant expression's temp is bound and then
only read. If a site would ever hand that temp to something that MUTATES it, it
needs its own fresh build instead; that is a per-site judgement, not a whole
analysis pass, and today's candidates below are all read-only positions.

## Known double-case sites

These are the cohesion — the reason this is one ticket and not four unrelated
ones. File a child ticket when you take one, and link it back here.

- **Literal vs named subscript receiver.** `PyMakeSuffixIndex` handles
  `"abc"[i]`; the default-indexed-property path in `parser.inc` handles `xs[i]`.
  They have already diverged once: the `__index__` coercion had to be added to
  the named arm, with the comment *"A LITERAL receiver already went through
  PyMakeSuffixIndex"* — which is the tell that this is the pattern.
- **Literal vs non-literal promo operand.** `IRPromoEmitBinop` chooses
  `PromoMixedHelper` or the general helper on `IsWideIntLit` / `IsWideNegLit`.
  Two lowerings for one operator.
- **A constant container in a loop condition** —
  [[feature-nilpy-hoist-constant-container-literals-out-of-a-loop-condition]].
  The instance that started this: `while x in ("a","b")` rebuilds the tuple on
  every test, because the fix that stopped a *method call* going stale had to
  stop treating everything in that position as loop-invariant.
- **The private "is this constant?" approximations.** `IsWideIntLit`,
  `InlineArgIsPure`, the container-literal scan — each site re-derives its own.
  **One shared, conservative predicate is most of this epic's value**, and
  writing it once is what stops these arms drifting apart again. Probably the
  first item to do.
- **Constant folding of pure literal arithmetic**, so more expressions qualify as
  constant before any of the above looks at them. Cheapest way to widen the
  epic's reach.

## What "done" looks like

It does not — standing index. The measurable goal: **no site branches on
"literal or variable" to decide semantics**, and the constant predicate lives in
one place.

## Gate

Per item, per the owning lane's normal gate. Nothing here should change observable
behaviour, so a CPython differential (`tools/pydiff.py`) over the affected shapes
is the check that it did not.
