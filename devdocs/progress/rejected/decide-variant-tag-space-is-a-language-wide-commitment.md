---
summary: "WITHDRAWN — the premise was false. Escalated on a defs.inc comment claiming variant tags can never be renumbered because Pascal compares VarType() and variants are serialized. Neither binds us: variants.pas explicitly disclaims FPC compatibility, our numbers never matched FPC's varXxx anyway, and no tag reaches any durable format. Renumbering is a mechanical refactor, so this is Track A's design call, not a language decision."
type: decide
track: U
prio: 55
found-by: claude-AN
status: rejected
---

> **WITHDRAWN 2026-08-11, before anyone spent time on it — the premise does not
> hold.** Raised by the user: *"there are no user programs depending on our
> serialization, unless you intended FPC compatibility for binary serialization
> — and I don't think you did."* Correct, and checkable:
>
> - **FPC compatibility was explicitly disclaimed.** `lib/rtl/variants.pas`'s
>   header: *"That is our model, not FPC's TVarData, and it is deliberately a
>   closed scalar set."* The numbers never matched either — `VT_INT` = 1 where
>   FPC has `varNull` = 1, `VT_DOUBLE` = 3 where FPC has `varInteger` = 3. Only
>   `VT_EMPTY` = 0 coincides, and that header calls the coincidence out.
> - **No tag reaches a durable format.** `lib/rtl/json.pas` reads `VT_INT` /
>   `VT_INT64` to pick a rendering but emits JSON *text*; `promocore.pas`'s
>   "binary serialization" is a bignum's own encoding, not a variant tag.
>   Nothing writes a tag number to disk or wire.
>
> So the worst case of a bad number is a refactor across the ~7 files that
> mention `VT_` — not a permanent public commitment. Every fork below then
> collapses: reserved-blocks-vs-singly stops mattering when renumbering is
> cheap, what `VarType()` reports is a design call `variants.pas` already has a
> stated convention for, and *who allocates* is answered by CLAUDE.md (shared
> internals are Track A's).
>
> **Nothing here needs human judgment.** The one durable output is worth
> keeping: `defs.inc`'s justification is overstated and misled this analysis, so
> it has been corrected in place. The callable-tag work is unblocked as a plain
> Track A ticket.
>
> Recorded rather than deleted because the reasoning error is the useful part: a
> source comment was quoted as fact and inflated into a language-wide decision
> without being checked against the code it describes — the ticket equivalent of
> the wrong-root-cause pattern `root-cause-over-microfix.md` warns about.

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
