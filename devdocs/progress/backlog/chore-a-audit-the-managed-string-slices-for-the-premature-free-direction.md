---
slug: chore-a-audit-the-managed-string-slices-for-the-premature-free-direction
title: The managed-string slices were verified for leaks only, never for premature frees
track: A
type: chore
prio: 40
status: backlog
found: 2026-08-28
found-by: frankwasm (disclosed unmeasured), filed by frank-coordinator
---

## Why this is filed as a MEASUREMENT task and not as a bug

**Nobody has measured it.** frankwasm disclosed the gap while reporting the dynamic-array
slice and explicitly declined to claim a defect: *"I would expect they do, and it is on my list
rather than filed, because I have not measured it."* That is the right call about the claim and
the wrong place for the finding — a finding in no ticket dies with the session — so it is filed
here with the uncertainty intact.

**Do not close this by reasoning. Close it by running the control.**

## The gap

The wasm32 managed-string slices (frozen strings, publish, concat/compare, index/SetLength)
were verified with an **arena-slope probe**: allocate in a loop, assert the heap advance does
not scale with iterations.

That instrument is **one-directional**. It detects refcounts that are too HIGH — a leak. It is
blind by construction to refcounts that are too LOW — a **premature free**, which corrupts
rather than wastes, and which is **invisible in the output until the freed block is reused**:
the stale bytes survive, and the wrong build prints the right answer.

The dynamic-array slice found this because a deliberate break (retain removed) **passed** the
first version of its check. The string slices shipped before that discovery.

## What to actually do

For each managed-string mechanism that takes a reference, break it in the **too-low** direction
— remove the retain, not the release — and confirm an assertion fires. The assertion that
catches it must **allocate a same-sized block between the free and the read**, because the
freed bytes survive until something reuses them.

Expected outcome is honestly unknown: the string paths may be correct and simply
under-verified, in which case this closes as *"verified, no defect"* and the checks gain their
missing half. That is a good outcome and not a wasted ticket — **the suite currently cannot
distinguish those two states, which is the whole point.**

## Related

`feature-a-a-refusal-is-a-claim-with-a-date-on-it` (face twelve) and
`feature-t-audit-tests-that-pass-with-the-implementation-removed` — same method, and the same
rule: **break it, and if the test still passes, ask what makes the broken state observable.**
