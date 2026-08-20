---
track: U
prio: 65
---

# Decide: how `TObject.Equals` / `GetHashCode` dispatch — intercept, real parent, or reserved slots

- **Type:** decision (Track U) — blocks [[feature-pascal-builtin-tobject-class]],
  which blocks [[feature-pascal-corpus-generics]] (rung 3 of
  [[feature-pascal-corpus-oop]]).
- **Raised:** 2026-08-20 (frank1-ACP). The fork was written into
  [[feature-pascal-builtin-tobject-class]] on the same day with the note *"it is a
  decision, not a task, and the ticket should not be picked up until it is
  settled"* — but recorded as prose inside a feature ticket, so the ranker kept
  offering it as work. This is that decision, filed where it can be answered.

## The fork

`rtl-generics` needs `TObject.Equals` (generics.defaults.pas:1569) and
`TObject.GetHashCode` (:1780). **Every default comparer in that unit `override`s
both**, so how they dispatch is the whole question — not whether they exist.

The constraint that makes this non-obvious: **pxx's TObject is an IMPLICIT
parent.** `RegisterBuiltinTObject` (parser.inc:35458) mints a real row, but
`class(TObject)` resolves the parent to `-1`, not to that row, on purpose — an
early version that made it a real parent RED'd test-core and cross ARC, because
every existing class's VMT indices moved.

## Options

**A — parser intercept**, the shape `IsClassRefOpName` uses for
ClassName/ClassType/InheritsFrom. Cheap, no VMT change, unblocks the corpus in a
session.
*Cost:* the methods are then **not virtual**. A descendant's `override Equals`
would not be dispatched through, which is exactly what generics.defaults does.
It unblocks compilation and can silently produce wrong ANSWERS — the failure mode
this repo keeps paying for (see the interface-overload IMT bug, same week).

**B — TObject becomes a real parent.** Correct, and what FPC has.
*Cost:* the relocation that already RED'd test-core + cross ARC once. The
implicit-root guard exists specifically to avoid it.

**C — reserved leading VMT slots (not considered in the original write-up).**
Keep TObject implicit, but have **every** class reserve the same N leading VMT
slots for the root methods, its own virtuals starting at index N. `o.Equals(x)`
on a static `TObject` dispatches through slot 0; a class overriding `Equals`
writes its proc into slot 0. The root-method names get fixed slot numbers in the
override resolver.
*Cost:* every virtual slot index shifts by N — but **uniformly and at declaration
time**, which is a different operation from B's mid-parse relocation of classes
that already exist. Whether that distinction actually holds is the thing to check
before committing to C; it is the reason C is worth putting on the table rather
than a claim that it is safe.
*Unmeasured:* N (how many root methods must be virtual — FPC has 4:
Destroy/Equals/GetHashCode/ToString), and whether anything outside
`UClsVirtCount`/`ResolveVMTSlotProc`/the IMT builder hardcodes a slot index.

## Recommendation

**C, with B as the fallback if the uniform-base assumption does not survive
contact.** Not A: it is not a cheaper version of the other two, it is a weaker
guarantee, and the corpus that motivates the work is precisely the caller that
would notice. The original write-up recommended B; C is offered because it may
buy B's correctness without B's known-RED relocation.

If the answer is "not now", say so and this parks — the rtl-generics rung stays
blocked and the corpus ladder stops at rung 2, which is a legitimate call given
the risk.

## What unblocks on an answer

[[feature-pascal-builtin-tobject-class]] (slice 2: the RTTI-free root methods) →
[[feature-pascal-corpus-generics]] walls 1569 and 1780 → walls 28-33, which so far
have only been measured against a throwaway tree with the two methods stubbed out.
