---
track: U
prio: 85
type: decide
---

# Promotable int: what IS an rvalue once heap bignums exist?

Blocks stage 3 (promotion) of [[feature-a-promotable-int]]. Stage 2 shipped
(`a2b88243`) and is green; this fork decides whether stage 2's lowering
survives or is rewritten.

## The fork

Stage 2 represents a promo **rvalue as its inline payload — a plain native
int**. That is what made stage 2 small and fast: arithmetic, comparison and
Write needed no promo knowledge at all, only load/store box.

That model **cannot survive stage 3**. Once a value may be a heap bignum, an
rvalue cannot be a machine int: the payload is then a pointer, and any op that
treats it as an integer computes garbage. The tag has to travel with the value,
and an IR node carries one value.

So stage 3 forces a choice.

### Option A — slot-address rvalue (the tyVariant model)

A promo rvalue becomes the ADDRESS of a 2-word slot; every op is a runtime
helper taking slot addresses. This is exactly how `tyVariant` already works
here, so the machinery is proven and all six backends get it at once with no
backend changes.

- Correct and portable immediately.
- Every arithmetic op becomes a call — a large slowdown versus stage 2's inline
  checked op, including for values that never leave the inline tier.
- Stage 4 ("check elision") then re-adds inline fast paths, i.e. partly undoes
  this.
- Rewrites stage 2's lowering.

### Option B — inline payload + guarded fast path in IR

Keep the payload-int representation for the inline tier and emit the tag check
as an explicit IR branch, falling back to a slot path only when a heap value is
involved.

- Keeps the fast path fast, which is what the ticket's "the tag check is a
  predictable branch; on the native side the payload is a plain machine int"
  describes.
- Much more IR per op, and every consumer of a promo value (Write, compare,
  call argument, assignment) needs both paths.
- The "value" of a promo expression is genuinely two things depending on a
  runtime bit, which the current IR has no clean way to express.

### Option C — promo as a 16-byte by-value record

Model the slot as a record type and let the existing ≤8-byte-inline /
>8-byte-by-ref record ABI carry it. Two-word values in registers, no memory
traffic, no new value model.

- Reuses an existing, tested ABI path.
- Invasive in a different direction: promo would inherit record semantics
  (copy, param passing) that may not be wanted, and the arithmetic still needs
  helpers or guarded IR.

## Recommendation

**Option A**, and accept the slowdown for stage 3. Reasons: it is the model
already proven in this codebase, it lands all six backends at once, and the
project's stated order is correctness before optimization. Stage 4 is *already
scheduled* to restore speed via check elision and range analysis, so the
"partly undoes it" objection is really "stage 4 does what stage 4 was for".

The cost of guessing wrong here is high — B and C both mean throwing away a
large lowering — which is why this is a decision and not a default.

## Also needs deciding with it

**Lifetime.** The umbrella ticket says heap bignums need a policy and suggests
reusing the managed-string refcount path, but does not commit. Leaking is
explicitly not acceptable ("a factorial or crypto loop churns them"). Confirm
refcount-reuse before stage 3 builds on it.

## Note

`lib/rtl/bignum.pas` already exists with the narrow interface the ticket asks
for (BigFromInt/BigToStr/BigAdd/BigSub/BigMul/BigDivMod/BigCompare), so the
slow path is a binding job, not a from-scratch implementation. Its `TBigInt` is
a record holding a managed dynamic array, which is relevant to the lifetime
decision.

## DECIDED 2026-07-20 — Option A, slot-address rvalue

**User's call: A.** A promo rvalue is the ADDRESS of a 2-word slot; every op is
a runtime helper taking slot addresses — the `tyVariant` model already proven
in this codebase.

Accepted trade: every arithmetic op becomes a call, a real slowdown versus
stage 2's inline checked op, including for values that never leave the inline
tier. Taken deliberately, because:

- it is the model already working here, so all six backends land at once with
  no backend changes;
- correctness before optimization is the project's stated order;
- stage 4 (check elision + range analysis) is *already scheduled* to restore
  the fast path, so "stage 3 partly undoes stage 2" is really "stage 4 does
  what stage 4 was for".

B and C were rejected as new value models: guessing wrong there means throwing
away the work, and A cannot be wrong — only slow, and slow is scheduled to be
fixed. Implementation continues under [[feature-a-promotable-int]].

## Log
- 2026-07-20 — DECIDED by the user; see the DECISION section above. Implementation follows in its own tickets.
