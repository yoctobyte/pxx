---
track: U
prio: 70
type: decision
---

# Decide: how should NilPy dispatch dunders on a Variant-held instance?

- **Type:** decision (Track U) — escalated, not guessed
- **Opened:** 2026-08-01. Blocks
  [[feature-nilpy-runtime-dunder-dispatch-on-variants]] and, through it, three
  tickets that share its root.

## The fork

Dunder dispatch is compile-time only. Once an instance is inside a Variant — a
container element, a widened global, a Variant parameter — no dunder fires:
`[a, b]` prints `[, ]`, `sorted()` raises, `box[0] + box[1]` raises. Three
tickets are stalled on this and would otherwise each grow their own private
runtime path.

## Options

**A. Runtime dunder dispatcher over the RTTI method table.** Look up the dunder
on the object's actual class and call it.
- Covers every case, including ones not yet imagined.
- Needs an argument-passing convention and a Variant-returning shim per dunder.
- Puts a reflective lookup on arithmetic and repr — the hot paths.

**B. Compile-time guarded dispatch.** Emit a tag test plus a direct call where a
Variant might hold a class.
- No reflection, cheapest at run time.
- Needs the candidate class set, which the Variant erased; does not cover
  containers, the most visible symptom. Partial by construction.

**C. Per-class dunder table registered at construction.** pylib looks up a
function pointer by (class, dunder).
- No reflection on the hot path, no static candidate set needed.
- Costs a table plus registration, and a decision about which dunders are in it.

## Recommendation

**C**, with A as the fallback for dunders left out of the table. It is the only
one that covers containers without putting reflection on the arithmetic path,
and the table is a bounded, reviewable artifact.

If the cost of the table is unattractive, A is the honest alternative — B should
not be chosen believing it fixes these three tickets, because it does not fix
the container one at all.

## What is NOT being asked

Whether the compile-time static paths stay: they should. They are correct, fast,
and already landed. This is only about what happens when the static class is
genuinely unknown.
