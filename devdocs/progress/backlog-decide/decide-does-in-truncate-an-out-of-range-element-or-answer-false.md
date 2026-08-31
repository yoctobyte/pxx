---
slug: decide-does-in-truncate-an-out-of-range-element-or-answer-false
track: U
prio: 30
type: decide
blocked-by: []
status: backlog
found: 2026-08-31
found-by: frankA
owner: unassigned
summary: "`q in [1,2,3]` with q = 2^32+1: FPC 3.2.2 answers TRUE (it truncates the element), pxx answers FALSE (out of range is not a member). Both are now SELF-CONSISTENT -- the six-target disagreement is fixed and this is no longer a bug -- so this is purely which semantics we want. Recommendation: keep FALSE. Nothing is blocked on the answer."
---

# Does `in` truncate an out-of-range element, or answer FALSE?

**Nothing is blocked on this.** It is filed because a real divergence from FPC
should be a recorded decision rather than a side effect of whoever fixed the
inconsistency, which was me.

## The fact, measured

```pascal
var q: Int64; s: set of Byte;
begin s := [1,2,3]; q := 4294967297 {2^32+1};
  WriteLn(q in [1,2,3]);   { FPC 3.2.2: TRUE    pxx: FALSE }
  WriteLn(q in s);         { FPC 3.2.2: TRUE    pxx: FALSE }
end.
```

7 of the 21 rows in `test/test_set_in_64bit_element.pas` differ from FPC 3.2.2;
the other 14 agree. FPC truncates the element to the set's width and tests the
surviving low bits, so 2^32+1 is treated as 1. pxx treats "outside the set's
base type" as "not a member".

## Why this is a decision and not the bug I just fixed

The **bug** was that pxx did not agree with ITSELF
([[bug-a-set-membership-truncates-the-test-value-on-32-bit-backends]]): x86-64
and aarch64 answered FALSE because their compare is 64 bits wide, while the four
32-bit backends either answered TRUE or failed to compile. That is fixed, and no
ruling here changes it — **all six targets must answer alike** either way.

What is left is a straight choice of semantics, and I made it the conservative
way: I moved the four backends onto the answer the reference backend already
gave, rather than moving x86-64 onto FPC's. That is the smaller and more
reversible change, not an argument that FALSE is right.

## The options

1. **Keep FALSE (current, recommended).** Out of range is not a member. It is
   what x86-64 and aarch64 have always done, so it is also the status quo for
   every program anyone has run on the default target. An element that cannot
   be represented in the set's base type is far more likely a bug in the user's
   program than an intent to test its low 8 bits, and silently answering TRUE
   hides it.
2. **Match FPC: truncate.** Costs a change to x86-64 and aarch64 — the targets
   that are correct today by our own test — and to the shared `SPECIAL_IN`
   emitter. Buys parity on a construct where I could not find real code that
   depends on it.

## What the compat ceiling says

CLAUDE.md: *"we just care for correct compiling pascal code, not emulating every
behaviour"*, and a differing result on an input no sensible program produces is
not a defect. `2^32+1 in [1,2,3]` is that kind of input. So option 1 unless
someone has real source that wants the truncation — which is the evidence that
would settle this, and I have none either way.

**If you rule for option 2**, the expectations in
`test/test_set_in_64bit_element.pas` move WITH the x86-64 backend, never
separately; the Makefile row and the test header both say so.
