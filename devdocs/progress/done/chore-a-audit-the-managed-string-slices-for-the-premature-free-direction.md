---
slug: chore-a-audit-the-managed-string-slices-for-the-premature-free-direction
title: The managed-string slices were verified for leaks only, never for premature frees
track: A
type: chore
prio: 40
status: done
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

---

# RESULT, 2026-08-28 — verified, no defect, and the REASON does not generalise

Run rather than reasoned: the retain in `WasmEmitOwnedStr`'s `tyAnsiString` arm
(`ir_codegen_wasm32.inc`) was deleted, the compiler rebuilt, and the three
string checks run against it.

| check | verdict |
| --- | --- |
| `check_managed.sh` | **caught it** — the diff, `sole owner` became `ten charac` |
| `check_index.sh` | **caught it** — the diff, `Xhared\|shared` became `Xhared\|Xhared` |
| `check_strop.sh` | did not catch it |

So the premature-free direction IS covered for managed strings, and the suite
did not need the reuse-forcing assertion the dynamic-array slice had to add.

**But it is covered for a reason that is a property of strings, not of the
suite, and that is the part worth recording.**

A managed string's refcount is **read by the code under test**. Copy-on-write
asks "am I the sole owner?" before every write, so a refcount that is too low
changes behaviour on the very next line — `s[1] := 'X'` mutates a buffer it
should have cloned, and both slices happen to contain that shape because
aliasing is what they were written to test.

A dynamic array's refcount is read **only by the release path**. Nothing in
normal operation consults it, so a refcount that is too low changes nothing at
all until something frees the block AND the allocator hands the same bytes to
someone else. That is why `check_dyn.sh` needed an assertion that allocates a
same-sized array between the free and the read, and why the first version of
that check passed a deliberately removed retain.

**The generalisation, which is the reusable output of this ticket:** a
one-directional instrument's blind half is only covered when the defect has a
*second* observable route into the output. For a type whose refcount steers
behaviour (strings, COW, anything with a sole-owner test) an ordinary
correctness diff finds it for free. For a type whose refcount is consulted only
on release (dynamic arrays, and by inspection interfaces and managed records),
the diff is silent and a reuse-forcing control is the only witness. **Ask which
kind you have before trusting a green suite**, rather than assuming the string
result transfers.

`check_strop.sh` not catching it is correct and not a gap: its subject is the
operators (concat, compare, the owned-temp arena), and it contains no aliasing
shape to be wrong about. Adding one there would duplicate `check_managed`'s
coverage rather than extend it.

## Consequence for the still-unwritten arms

Interfaces and managed records are the next two refcounted types this backend
will meet, and both are the second kind — refcount consulted on release only.
Their slices need the reuse-forcing control **designed in**, not discovered by
a break that passes.

Closing this ticket: **no defect found, control run, result recorded.** The
suite's coverage of this direction for strings is real but incidental, and the
note above is what stops that being read as "the suite covers it".

---

## Coordinator addendum, 2026-08-28 — the verdict stands; the CATEGORY is not a property of the type

Verified independently, not relayed. The audit's conclusion is right and its *reason* is
stronger and more fragile than stated, and the difference decides what to do with it.

**Verified:** interfaces and managed records have **zero** uniqueness/copy-on-write paths
(`IR_INTFUNIQUE`/`IR_RECUNIQUE`/`UniqueIntf`/`UniqueRec` → 0 hits; 35 interface refcount
sites, all retain/release). So "both are the second kind" holds today.

**But dynamic arrays used to be the FIRST kind.** `IR_DYNUNIQUE` still exists in four
backends and its own comment (`ir_codegen.inc:5328`) opens *"The name is now historical"*:

> This node used to implement NESTED copy-on-write: on a write it cloned the level when
> shared and published the unique handle back into the slot […] That invariant was the
> deliberate x86-64 design, and it is the opposite of FPC/Delphi […]
> `decide-dynamic-array-value-vs-reference-semantics` settled on matching FPC, so the clone
> is gone at every depth.

A **semantics decision** — `decide-dynamic-array-value-vs-reference-semantics` (decided),
landed as `bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing` (done) — moved
dynamic arrays from *refcount steers behaviour* to *refcount consulted only on release*.

**So the category is a property of the CURRENT SEMANTICS, not of the type.** And note which
direction the crossing went, because the two are not symmetric:

| crossing | effect on an existing suite |
| --- | --- |
| second kind → first kind (COW added) | the reuse-forcing control becomes redundant. **Harmless.** |
| **first kind → second kind (COW removed)** | the second observable route disappears, the diff stops witnessing a too-low refcount, and **every test keeps passing.** |

Dynamic arrays took the dangerous direction. **A suite written while COW existed silently
became an uncovered suite, and nothing in its output changed.** That is the audit's own
finding — *a green suite that cannot distinguish covered from uncovered* — arriving one level
up: not in a test, in the **semantics the test's coverage depended on**.

> **A COVERAGE ARGUMENT THAT RESTS ON "THE CODE UNDER TEST READS THIS VALUE" HAS A DEPENDENCY
> ON A DESIGN DECISION, AND DESIGN DECISIONS ARE NOT VERSIONED AGAINST THE TESTS THAT ASSUME
> THEM.**

Practical consequence, and it is cheap: the reuse-forcing control is the one that survives a
category change in either direction. **Where it is cheap, design it in even for a first-kind
type** — it costs an allocation and it is the only witness that does not depend on the
semantics staying put. Do not, however, weaken the audit's actual instruction: *ask which
kind you have before trusting a green suite* stays exactly right; this only adds that the
answer has a date on it.
