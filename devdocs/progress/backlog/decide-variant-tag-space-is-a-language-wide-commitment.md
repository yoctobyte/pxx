---
summary: "Adding a VT_* variant tag is permanent, serialized and visible to user Pascal via VarType() — it is a language-wide commitment, not a frontend implementation detail. Who may add one, do they come one at a time or as reserved blocks, and what does VarType() report for the NilPy-motivated tags? Tag 11 (classref) already shipped without this being asked."
type: decide
track: U
prio: 55
found-by: claude-AN
---

# Is a new variant tag a frontend detail or a language commitment?

## Why this is a decision and not a task

`compiler/defs.inc`, in the promotable-int block, states the constraint itself:

> Variant tags can never be renumbered — Pascal code compares `VarType()`
> against documented constants and variants are serialized

and `lib/rtl/variants.pas` exports `VarType(const V: Variant): TVarType` to user
Pascal. So every tag added for one frontend's benefit is:

- **permanent** — it can never be renumbered;
- **serialized** — it travels in persisted data;
- **observable from a different language** — a Pascal program can branch on it.

That makes the tag space a cross-language surface, on the same footing as the
IR: [[ir-as-substrate]]'s "push generality down into the core" cuts both ways —
what goes into the core is everyone's, forever.

The tags currently in NilPy's name are 8 (boundmethod), 9 (pyclosure),
10 (boundfn) and 11 (classref). A Pascal program that asks `VarType(v)` on a
variant that has passed through NilPy sees those numbers today, and nothing
documents what they mean to a Pascal reader.

## How this surfaced

While fixing [[bug-nilpy-calling-a-non-callable-segfaults]], the honest fix for
the remaining hole was measured to require a distinct CALLABLE tag —
[[feature-nilpy-a-callable-value-needs-its-own-variant-tag]], since re-tracked
to A and blocked on this. Writing that up made the pattern visible.

**Disclosure:** `VT_CLASSREF_TAG = 11` shipped earlier in the same session under
`feature-nilpy-class-as-a-value`, filed as Track N, with no Track A ticket and
without this question being asked. It is in `done/` and working; this ticket is
not a request to revert it, but it is the precedent that shows the gap was
procedural rather than hypothetical. Deciding here also settles whether 11 needs
documenting on the Pascal side.

## The forks

**1. Who owns adding a tag?**
- **A — Track A, always**, with a Track U sign-off for the number itself
  (recommended). Matches where the code lives: `defs.inc` defines it, and
  `ir_codegen.inc`'s clear/retain emitters, `builtinheap.pas` and `parser.inc`
  consume it. A frontend proposes; A allocates.
- **B — the owning frontend may allocate**, as happens today de facto. Cheap,
  and how 8/9/10/11 arrived. Risks two frontends racing for the same number in
  parallel branches — the exact collision the track letters exist to prevent —
  and there is no registry to check.

**2. One at a time, or reserved blocks?**
The promo family answered this once already and its comment says why: it claimed
a **contiguous reserved block** (8192..8199) up front "while it is free, rather
than being scattered into whatever gaps exist when each class lands".
- **A — reserve a small CALLABLE block** (e.g. 12..15: plain code address,
  closure, bound method, bound-fn) and fold the existing 8/9/10 into it over
  time, or alias them. Follows the precedent; leaves room for the fourth
  representation that [[project_nilpy_callable_has_three_representations]]
  suggests is coming.
- **B — take the next free number per need.** Simplest now; this is how 9, 10
  and 11 landed, and it is why callable-ness is already spread over three
  non-adjacent tags with no way to test "is this callable?" in one comparison —
  which is the very thing the callable-tag ticket wants.

**3. What does `VarType()` report to Pascal for these?**
- **A — the raw tag**, and document 8..15 in the Pascal variant docs as
  "foreign-language callable/classref kinds, opaque to Pascal".
- **B — normalise to an existing varXxx** at the `VarType` boundary so Pascal
  never sees a number it has no name for. Hides them, at the cost of Pascal
  being unable to tell a callable variant from whatever it is mapped onto.

## Recommendation

**1A, 2A, 3A.** Track A allocates with a U sign-off; reserve a contiguous
callable block rather than taking the next gap; report the raw tag and document
the range as opaque-to-Pascal. That keeps one rule for a surface that can never
be renumbered, and 2A is the option that actually makes the callable-tag fix a
one-comparison test instead of a fourth scattered case.

Whatever is chosen, the outcome should land as a short **tag registry** section
in `defs.inc` beside the VT_ block — the thing whose absence let 11 ship without
anyone asking.
