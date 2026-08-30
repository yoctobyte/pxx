---
track: A
prio: 30
type: bug
status: done
found: 2026-08-30
found-by: frankD
summary: "builtinheap.pas:2625-2631 is the sentence that produced instances 1, 2 and 3 of the builtinheap-twins ticket. All three were fixed on 2026-08-29. The comment was written 2026-08-14 and has not been touched since — it still says PXXStrUnique is 'the single choke point for byte mutation, which is what makes the cache sound' and that 'PXXStrSetLen needs no such call'. Refuted three times in one day, still standing, still load-bearing."
---

# The comment that caused three bugs survived all three fixes

Found working the twin seam for
[[audit-a-builtinheap-invariants-x86-64-inlines-past]]. Read-only, measured at
`084ee09ef`.

## The sentence

`compiler/builtin/builtinheap.pas:2625-2631`, inside `PXXStrUnique`:

> *"Whichever path runs, the caller is about to WRITE bytes through the handle we
> return, so any cached ASCII answer stops being true. … Both must forget it —
> **this is the single choke point for byte mutation, which is what makes the
> cache sound. PXXStrSetLen needs no such call: it always allocates a fresh block
> and PXXHdrInit zeroes its meta.**"*

## The chronology, which is the finding

| date | commit | event |
| --- | --- | --- |
| **2026-08-14** | `8a263f504` | the comment is written, with the ASCII cache it justifies |
| 2026-08-29 | `8be3c6d06` | instance 1 — x86-64 inlines `SetLength`, so the helper's NilPy arms are never reached |
| 2026-08-29 | `df19c72a7` | instance 2 — x86-64's **in-place** resize reuses the block, refuting *"it always allocates a fresh block"* by name |
| 2026-08-29 | `b71690c40` | instance 3 — indexed writes reach `AnsiStrUniqueAddr`, a hand-emitted blob, refuting *"the single choke point"* |
| 2026-08-30 | — | **the comment is unchanged.** `git blame` still says `8a263f504` for all seven lines |

Three separate agents found three separate bugs caused by believing this
sentence, fixed all three in one day, and **not one of them edited it.** Each fix
corrected the code it was in and moved on.

## Why it is still load-bearing, not merely stale

The two clauses do different damage:

- *"the single choke point for byte mutation"* — **false.** There are at least
  four sites that mutate bytes: `PXXStrUnique` (both arms), x86-64's
  `AnsiStrUniqueAddr` blob, the in-place `SetLength` resize at
  `ir_codegen.inc:7912`, and `PXXStrAppend`'s deliberate bit carry-over. All four
  handle the cache correctly *today*, so nothing is broken — and that is the
  problem: **the sentence tells the next author that a fifth site needs no
  invalidation as long as it routes through `PXXStrUnique`.** That is precisely
  the reasoning that produced sites 2 and 3.
- *"`PXXStrSetLen` needs no such call: it always allocates a fresh block"* —
  **true of the Pascal helper and false of the concept.** I checked the body:
  `PXXStrSetLen` really does `PXXAlloc` + `PXXHdrInit` on every non-collapsing
  path. But x86-64 does not *call* it — it inlines the symbol-target resize, and
  that inline has an in-place arm. The clause is a correct statement about a
  routine, doing the work of an incorrect statement about a language feature.

The second is the more interesting failure mode and it is not "the comment is
wrong". **It is right about what it names and wrong about what it is used for.**
A reader checking it against `PXXStrSetLen` confirms it and stops.

## Its sibling is already filed

[[bug-a-the-ascii-cache-consumer-still-says-byte-mutation-has-one-place]] —
`pylib.pas:3361`, the same claim one indirection away, in the *consumer* that
decides whether to trust the cache at all. **Two copies of one false sentence,
both surviving the fixes, in the producer and the consumer.** Fix them in one
commit or the next reader finds whichever one you left.

## Fix

Both clauses, in place:

1. Replace *"the single choke point"* with the truth and a way to check it:
   *"one of several sites that mutate bytes — every such site must forget the
   answer; `grep PXXStrForgetAscii` plus the two hand-emitted x86-64 paths in
   `ir_codegen.inc` is the current list."*
2. Replace the `PXXStrSetLen` clause with what it is actually asserting:
   *"the Pascal `PXXStrSetLen` always allocates fresh, so it needs no forget —
   but x86-64 does not call it, and its inline resize has an in-place arm that
   does (`ir_codegen.inc:7912`)."*

Neither sentence carries a count, which is the rule from
[[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]]:
a comment containing a count, a target list, or the words "only"/"every"/"always"
is asserting something a command can check.

## Gate

Comment-only. `make compiler/pascal26` must stay byte-identical; if it does not,
something in the change was not a comment.

## Log
- 2026-08-30 — resolved, commit 45a655ed4.
