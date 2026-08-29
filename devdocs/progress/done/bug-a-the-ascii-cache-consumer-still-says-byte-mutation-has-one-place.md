---
track: A
prio: 20
type: bug
status: done
found: 2026-08-29
found-by: frankD
summary: "pylib.pas:3361 justifies trusting the ASCII cache with 'PXXStrUnique forgets it whenever bytes are about to change, which is the one place they can'. There are four such places. All four handle it correctly today, so no defect — but this is the same false-choke-point sentence that cost two months as instance #4, still asserted in the CONSUMER that depends on it, after the fix."
---

# The ASCII-cache consumer still says byte mutation has "one place"

Pass 4 of [[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]],
working the remaining phrase hits in the order face 71 implies: **claims a routine
makes about its own mechanism first**, since those are the ones that have failed.
Read-only.

## The claim

`compiler/builtin/pylib.pas:3355-3361`, inside the `isascii` predicate that
`PyStrCharLen` and `pystr_charat` both open with — i.e. the hot path the whole
cache exists for:

> *"The block header carries the answer; PXXStrUnique forgets it whenever bytes
> are about to change, **which is the one place they can**."*

That last clause is the entire justification for the consumer trusting a cached
answer instead of scanning. It is false.

## The four places bytes can change

| # | site | what it does |
| --- | --- | --- |
| 1 | `builtinheap.pas:2614`, `:2622` | `PXXStrUnique` forgets, on both the in-place and the clone arm — the one the sentence names |
| 2 | `ir_codegen.inc:2416` region | **x86-64's hand-emitted `AnsiStrUniqueAddr` blob**, which never calls `PXXStrUnique` at all. This is instance #4; it was fixed in `b71690c40` |
| 3 | `ir_codegen.inc:7912` | the **in-place `SetLength` resize**, which grows the block without going through either of the above and clears both bits itself |
| 4 | `builtinheap.pas:1486`, `:1523` | `PXXStrAppend` carries the bits forward deliberately, having reasoned about the appended bytes |

**All four are correct today.** There is no wrong answer to reproduce and this
ticket is not reporting one.

## Why it is still worth filing

This is instance #4's sentence, one indirection away and still standing. #4 was
`PXXStrUnique`'s own header calling itself *"the single choke point for byte
mutation, which is what makes the cache sound"* — true on five targets, false on
the sixth, and the fix in `b71690c40` corrected **that** comment. Nobody grepped
for who else had written the same thing down.

And the copy that survived is in the worse place. `PXXStrUnique`'s header is read
by someone editing `PXXStrUnique`. `pylib.pas:3361` is read by someone deciding
**whether the cache can be trusted at all** — it is the consumer's warrant, so a
reader who believes it concludes that adding a fifth mutation site is safe as
long as it goes through `PXXStrUnique`, which is exactly the reasoning that
produced sites 2 and 3.

Note site 3 postdates the fix: an in-place resize that mutates bytes without
touching `PXXStrUnique` was added, correctly invalidated by its author, and the
sentence claiming such a site cannot exist was not revisited. **The count was
wrong, then it was fixed in one place, then the world moved again and made it
wronger.**

## Fix

`pylib.pas:3361`: drop "which is the one place they can" and point at the
invariant instead of the mechanism — *"every site that mutates bytes in place
invalidates it; see PXXStrForgetAscii's callers and the two hand-emitted x86-64
paths"* — a sentence that stays true when a fifth site lands, and that names a
grep rather than a count.

Worth doing at the same time, since it is the same seam and the same shape:
`compiler/ir.inc:5051` says `FramePrevFpOffset`/`FrameRetAddrOffset` *"are the
only place the frame layout is encoded"*, while `defs.inc:816` encodes it too and
gets it wrong — see
[[bug-a-the-ir-frame-op-doc-asserts-a-frame-layout-riscv32-does-not-use]]. The
`ir.inc` sentence is defensible as written (it is about update sites, and its
own table documents riscv32's exception correctly); it is listed here only so
whoever fixes `defs.inc:816` knows a second "only place" claim points at the
same layout.

## Checked and HOLDING in the same seam — recorded so nobody re-checks

- `builtinheap.pas:127-129`: *"`PXX_FLAG_ASCII`'s ABSENCE means 'unknown', not
  'non-ASCII' — a consumer must scan."* **Holds.** There is exactly one external
  consumer, `pylib.pas:3362`, and it scans on `-1` before answering. The
  tri-state is respected.
- `ir_codegen.inc:7909-7926`: the in-place-resize invalidation. Correct, and its
  comment carries the measured failure it prevents (`"é" * 3` answering
  `isascii()=True` and `len()=6`). A model of what one of these should look like.

## Gate

Comment-only. `make compiler/pascal26` byte-identical.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
