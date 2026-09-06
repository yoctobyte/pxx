---
track: A
prio: 55
type: bug
blocked-by: [decide-should-an-open-array-parameter-become-a-two-word-descriptor]
found: 2026-09-02
found-by: frankB
summary: "TWO CONDITIONS BEFORE ANYONE TOUCHES 633 SITES, AND THEY ARE THE FIRST THING TO READ. (1) SEQUENCING: the decision says not to start this while the phase-4 flip is unreleased -- both serialise the backends. That hold names no event anybody can check and no ticket to point at; establish its state with whoever owns phase-4 before starting, and write the answer here. (2) MEASURE FIRST: the 633-site figure assumes arm A is a wire-format change because `[ptr-8]` is SHARED with dyn arrays and AnsiString handles -- but passing an open-array PARAMETER as two words AT THE CALL BOUNDARY may not require changing the storage convention those two rely on. Nobody has measured that, and it decides weeks vs days. UNBLOCKED 2026-09-03: `decide-should-an-open-array-parameter-become-a-two-word-descriptor` is DECIDED -- the owner chose ARM A, *\"if we need more meta info, use more data fields. hardly a decision.\"* Carry the metadata; do not spend correctness to keep one word. The ticket's own recommendation was arm C and was heard and overruled. THE DEFECT: `@a[0]` inside a callee does NOT equal the caller's `@arr[0]` for a `var` or `const` open-array parameter whose argument is a STATIC array -- every element type, and for a global, a local and a record field alike; FPC answers TRUE for all of them. Cause is representational: a pxx open-array param is a pointer with its length at `[ptr-8]`, so only an argument already carrying that header can be passed by reference, and FPC passes (ptr, high) as two words and therefore aliases everything. NOT a wrong value -- the temp is a faithful, writable, correctly-strided view whose writes are copied back -- it bites only when an address ESCAPES the call. CORRECTED 2026-09-03 by its own author: a DYNAMIC array argument already aliases correctly (1/1, matching FPC), and a VALUE parameter answers FALSE in FPC TOO, so neither row was ever a divergence."

status: backlog
---

# `@a[i]` on an open-array parameter addresses the marshalling temp, not the caller's array

## Measured, 2026-09-02, binary `a0fbf36e29f4`

```pascal
var gi: array[0..3] of LongInt;  b: PtrUInt;
procedure Pi(var a: array of LongInt);
begin WriteLn(PtrUInt(@a[0]) = b); a[2] := 99; end;
...
b := PtrUInt(@gi[0]); Pi(gi); WriteLn(gi[2]);
```

|  | pxx | fpc |
| --- | --- | --- |
| `@a[0] = @gi[0]` | **FALSE** | TRUE |
| `a[2]` read | 2 (correct) | 2 |
| `gi[2]` after `a[2] := 99` | 99 (correct) | 99 |

Same three rows for `array of TR` (a record) and `array of string[10]`, and the
same for `const` and value parameters. **It is not element-type-specific** —
that is what separates it from the capacity family, where LongInt and record
were correct and only the frozen string was wrong.

## Why the write still propagates

`ir.inc`'s var/out open-array arm copies the static array into a header'd temp
and registers a copy-OUT after the call. Its own comment states the limit:

> copy-in / copy-out aliasing — observably equal to true aliasing **unless the
> callee reaches the same array by another path during the call**

`@` is that other path, and it needs no second path *into* the array — taking
the element's address and comparing or storing it is enough. So this is a
DOCUMENTED exception that turns out to be reachable from a single operator,
rather than an unknown divergence. Recording it means the next person meets a
ticket instead of re-deriving it from the comment.

## What it does and does not break

**Does not:** indexing, `Length`/`High`, reading, writing, writeback. A callee
that treats the parameter as an array is correct throughout — which is why this
survived: the temp is a faithful, correctly-strided, writable copy.

**Does:** any address that OUTLIVES or ESCAPES the call — stored into a
structure that outlives the frame, compared against a caller-side address (the
row above), or handed to a routine that keeps it. Also anything relying on the
callee and caller observing each other's writes *during* the call.

## The fix is aliasing, not a patch to `@`

Making `@a[i]` return the caller's address while the callee still indexes a temp
would be worse than the current state: the two would disagree. For a `var` open
array the correct answer is to pass the caller's array directly. The reason a
temp exists at all is the `[len:8]` header that `High`/`Length` read — a static
array has none — so the real fix is a way to carry the length beside a borrowed
pointer rather than by prefixing a copy.

**Do not fix this inside the byte-prefix feature.** It is unrelated to the
prefix width and would confuse attribution there.

## Gate

`make test` + self-host + cross. Assert `@a[0] = @caller[0]` AND that indexing
still works — the second is what a naive fix breaks.


## CORRECTED BY ITS AUTHOR, 2026-09-03, binary c709788d39ad

I re-measured before trying to fix it and the ticket was wrong in two ways that
between them halve the surface. One program, four argument shapes, three
parameter modes, pxx beside `fpc -Mobjfpc -O2`:

| argument | mode | pxx | fpc |
| --- | --- | --- | --- |
| static global | var / const | **0 / 0** | 1 / 1 |
| static local | var / const | **0 / 0** | 1 / 1 |
| static record field | var / const | **0 / 0** | 1 / 1 |
| **DYNAMIC** global | var / const | **1 / 1** | 1 / 1 |
| any of them | **value** | 0 | **0** |

**1. A DYNAMIC array argument already aliases.** The original ticket measured
only static arrays and generalised. A dyn array IS a header'd handle, so the
`var`/`const` path passes it straight through with no temp — which is also the
proof that the copy exists for the header and nothing else.

**2. THE `value` ROW WAS NEVER A DIVERGENCE.** The summary said FPC answers TRUE
for `var`, `const` and value alike. FPC answers **FALSE** for value, and it is
right to: a value open-array parameter is a copy by definition, so its elements
have their own addresses in both compilers. I asserted a row without an oracle
beside it and it read as three failures where there were two.

### What the shape of the fix actually is, now that the oracle has been asked

FPC passes an open array as **two words, (pointer, high)**. pxx passes **one**:
a pointer whose length lives at `[ptr-8]`, the same convention AnsiString
handles and dynamic arrays use. That single fact explains every row above —
an argument that already carries the header is passed by reference, and one that
does not must be copied into something that does, because the header has to be
*adjacent*.

So `@a[i]` cannot be made to answer the caller's address without either:

- **changing the parameter representation to a descriptor** (the FPC answer, and
  the correct one) — but the `[ptr-8]` convention is shared with dyn arrays and
  managed strings, and `IsArray` appears **633 times across 27 files**,
  6 of them backends. This is a representation change measured in weeks, not a
  fix; and
- **prefixing the ARGUMENT's own storage with 8 bytes** — possible for a local
  or a global, whose slot layout the compiler owns outright, and impossible for
  a record field or a 2-D row, whose offsets are observable. That would leave
  two behaviours for one construct, with the second one still broken and
  looking fixed. Rejected for that reason, not for difficulty.

**Parked deliberately, not abandoned.** The diagnosis is complete and the fix
direction is settled; what it needs is a session that can carry a
representation change across 6 backends, which is not the same as a session that
can carry a bug fix.

Re-measured shapes worth keeping: element access, write-through, `Length` and
`High` are correct throughout, on every row above, in both compilers.

# 2026-09-03 — escalated to Track U, and why it is not a queue item

Three sessions read this independently and all three stopped at the same
sentence. That is the tell for a mis-filed ticket rather than a hard one: the
work is not a bug fix, it is a decision about the parameter REPRESENTATION, and
a p55 slot in `ready --track A` guarantees a fourth reader repeats the pass.

The fork, both arms, their costs and a recommendation are in
`decide-should-an-open-array-parameter-become-a-two-word-descriptor`. Nothing
about the diagnosis below changed; it is complete and it was corrected against
FPC on 2026-09-03. `blocked-by` now names the decision, so this drops out of the
ranked queue until the fork is settled.

## MOVED OUT OF `blocked/` 2026-09-06 (frank-coordinator) — the edge was met and the ticket was invisible

`tools/progress.sh check` flagged this as STALE-EDGE-HIDDEN: the only ticket in its
`blocked-by` has been in `decided/` since 2026-09-03, and `ready`/`next` never scan
`blocked/`, so a decided p55 defect was invisible to the ranker for three days. **The
`blocked-by` edge is left in place deliberately** — it records the RELATIONSHIP, which is
real and worth keeping; only the blocker's FOLDER records whether the edge is still
unmet, and it says met.

**What the move does NOT do is make this ready to start**, which is why the summary was
rewritten in the same commit rather than left as it was. The old summary opened
*"ESCALATED TO TRACK U — do not attempt this from the queue"*, and that sentence stopped
being true the moment the decision landed; a summary is the only part everyone reads, so
a stale one misroutes whoever reads it. The two conditions that ARE still live now open
it instead.

**The sequencing hold has no retiring event and that is the thing to fix.** *"Not to be
started while the phase-4 flip is unreleased"* is a real constraint written by someone
who could see it, and there is no `phase-4` ticket to point a `blocked-by` at — the
phrase appears in exactly one open ticket, and there only to say the flip does NOT touch
that work. So it cannot be wired as an edge, nothing re-checks it, and it retires only
when a human remembers. **Whoever takes this should establish phase-4's state from its
owner first and write the answer into this ticket**, which converts a hold that ages
silently into a fact with a date on it. A stated blocker is a hypothesis with the same
standing as a stated cause; the difference is that a cause invites re-measurement and a
blocker invites deferral.

Not claimed, no owner set. This is board hygiene, not a claim.
