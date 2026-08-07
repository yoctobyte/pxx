---
track: U
prio: 40
type: decision
summary: "class D(B, C) is refused with a clear diagnostic (option 3 landed 2026-08-04). The FEATURE is still open and the remaining choice is a design fork: full C3 linearisation, or second-base-as-delegate. Needs a call before anyone builds it."
---

# Decide: multiple inheritance — C3, delegate, or leave refused?

Escalated 2026-08-07 from
[[bug-nilpy-multiple-inheritance-does-not-parse]], whose cheap half (a
diagnostic naming the constraint instead of "unexpected token") already landed.
What is left is not a bug fix, it is a design choice, so it should not be made
by whoever happens to pick the ticket up.

## The fork

The underlying Pascal object model is **single-inheritance**, so a second base
cannot be a real parent. Three options, from that ticket:

1. **Full C3 linearisation.** Flatten the MRO at compile time and resolve each
   attribute to the winning definition. Correct for the diamond
   (`D(B, C)` with both deriving from `A` must resolve D, B, C, A), and the most
   work.
2. **Second base as a delegate.** Real inheritance from the first base;
   attributes not found there forward to an embedded instance of the second.
   Handles the mixin idiom, which is what most real code uses it for. Gets the
   diamond wrong exactly where C3 would pick C over an inherited-from-A member
   of B.
3. **Stay refused.** Today's behaviour: a clear diagnostic telling the reader to
   use single inheritance or compose.

## What is NOT in question

Silently accepting the comma and ignoring the second base is ruled out by the
ticket already — it turns a compile error into a wrong method being called at
run time.

## Why it needs you

The trade is between **coverage of real Python** (mixins are common; option 2
buys most of it cheaply) and **not shipping a subtly wrong MRO** (option 2 is
observably wrong in the diamond, which is exactly where someone would trust it).
Option 3 is honest and free but keeps blocking corpus work.

This is a *how much Python do we mean to be* question, which is the sort
`devdocs/dev/nilpy-semantics-divergences.md` says belongs to you, not a lane
agent picking the reachable option.

## Recommendation

**Option 2 (delegate) with the diamond REFUSED.** Take the mixin case, which is
the one real code needs, and keep the compile error for the shape where the
delegate model would be wrong (two bases sharing an ancestor). That yields no
silently wrong answers, unblocks the common idiom, and leaves a clean upgrade
path to C3 later — the refusal becomes dead code rather than something to undo.

Unblocks: [[bug-nilpy-multiple-inheritance-does-not-parse]].
