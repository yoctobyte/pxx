---
slug: bug-a-a-comment-claims-a-cow-check-for-dynamic-arrays-that-was-deleted
title: "ir_codegen.inc:5358 says 'COW check for managed strings and dynamic arrays'; the block only ever handles strings"
track: A
type: bug
prio: 25
status: backlog
found: 2026-08-28
found-by: frank-coordinator (while verifying the managed-string audit)
---

## The fact

`compiler/ir_codegen.inc:5358`, inside `IR_INDEX`:

```pascal
{ COW check for managed strings and dynamic arrays. }
isAnsiStr := False;
```

Everything under that comment computes and branches on **`isAnsiStr`** and nothing else.
There is no dynamic-array arm, and there is not supposed to be one: the dyn-array clone was
**deliberately deleted** when `decide-dynamic-array-value-vs-reference-semantics` settled on
FPC reference semantics (landed as
`bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing`).

`IR_DYNUNIQUE`'s own comment 30 lines above is scrupulous about this — *"The name is now
historical"*, with the reasoning and both ticket references. **This comment was not updated in
the same pass.** Exactly one copy exists; no other backend repeats it.

## Why it is worth a ticket at p25

**It misleads the specific reader who is doing the right thing.** Someone auditing whether a
dynamic array's refcount has a non-release observer — which is precisely the question
`chore-a-audit-the-managed-string-slices-for-the-premature-free-direction` turned on — greps
for the COW check and finds a comment saying dynamic arrays have one. The answer to that
question decides whether a reuse-forcing control is *required* or *redundant*, so a stale
comment here converts into a missing test elsewhere.

The correct code is not in question. **The stale comment is the whole defect**, which is why
it is p25 and not higher.

## Fix

Say what the block does — strings — and, since the absence is load-bearing, say why dynamic
arrays are *not* here, pointing at the decide ticket the way the `IR_DYNUNIQUE` comment does.

## Related

`feature-a-a-refusal-is-a-claim-with-a-date-on-it` — **face nine**: the false claim lives in a
comment, so no test can fail on it and no build can catch it. Third instance today, after the
`a.ir:*` comment and the `abi.inc` greppable-invariant clause. Same lesson as
CLAUDE.md's correct-across-copies rule, one step further: **a deletion has copies too — the
comments that described the deleted thing.**
