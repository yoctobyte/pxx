---
track: A
prio: 25
type: bug
status: done
found: 2026-08-29
found-by: frankD
summary: "--threadsafe has accepted x86-64/i386/aarch64/arm32 since 07fee0844 (2026-07-06), but five comments across four files still say it is x86-64-only. One of them sits ONE LINE above the four-target condition the same commit edited. No live defect; the code is right everywhere. A new audit sub-shape: a SCOPE WIDENING invalidates every comment that stated the old scope, and there is no sibling arm to grep."
---

# "threadsafe is x86-64-only" is asserted in five places, and has been false since July

Found by the sweep for
[[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]],
working the `builtinheap.pas` seam
([[audit-a-builtinheap-invariants-x86-64-inlines-past]]) from its `PXXStrIncRef`
entry. Read-only; measured at `e7385984b` against the pinned tree.

## The shipped scope, which is what a reader should be able to trust

`compiler/compiler.pas:1586` — the CLI gate, and the authority:

```pascal
if ThreadSafeMode and (TargetArch <> TARGET_X86_64) and (TargetArch <> TARGET_I386)
   and (TargetArch <> TARGET_AARCH64) and (TargetArch <> TARGET_ARM32) then
begin writeln(StdErr, '--threadsafe is x86-64/i386/aarch64/arm32 only: ...
```

**Four targets.** x86-64 uses hand-emitted lock blobs; i386, aarch64 and arm32
get `PXX_TS_SOFTLOCK` (`lexer.inc:1012-1023`) and take their locks in Pascal
inside `builtinheap.pas`. `{$threadsafe on}` enforces the same four
(`lexer.inc:1844`). It became four on **2026-07-06**, `07fee0844`
*"feat(arm32): libc-free threading — atomics, clone, futex mutex, IO lock"*.

Everything below is a comment that still states the pre-July scope. **The code is
correct at every one of these sites** — this is not a live defect and I could not
construct a program that misbehaves. It is a false statement in five places about
a safety property, which is the class of thing this repo has already paid for
twice.

## The five, with the distance measured

**Locate them by grep, not by line number** — see the note below on why this
table changed shape:

```
grep -n 'threadsafe atomics are x86-64-only' compiler/ir.inc
grep -n 'threadsafe mode is x86-64 only'     compiler/builtin/builtinheap.pas
grep -n 'x86-64 + ThreadSafeMode only'       compiler/defs.inc
grep -n 'threadsafe is x86-64-only'          compiler/ir_codegen386.inc
grep -n 'Threadsafe locking is x86-64-only'  compiler/ir_codegen386.inc
```

| # | site | asserts | refuted by | distance |
| --- | --- | --- | --- | --- |
| 1 | `ir.inc` | *"x86-64 only — --threadsafe atomics are x86-64-only today."* | the condition on the very next line, which tests all four | **ONE LINE** |
| 2 | `builtinheap.pas` | `PXXStrIncRef` is *"NON-atomic — threadsafe mode is x86-64 only"* | its own `{$ifdef PXX_TS_SOFTLOCK}` atomic arm, a few lines below | **~8 lines** |
| 3 | `defs.inc` | `IR_IO_LOCK` is *"x86-64 + ThreadSafeMode only"* | real lock calls in `ir_codegen386.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc` | **cross-file, 3 backends** |
| 4 | `ir_codegen386.inc` | *"no shim/lock; threadsafe is x86-64-only"* | the CLI gate in `compiler.pas`, `lexer.inc`'s softlock define | **cross-file** |
| 5 | `ir_codegen386.inc` | *"Threadsafe locking is x86-64-only; **i386 runs single-threaded**"* | same | **cross-file** |

> **Re-cited 2026-08-30 (frankD), measured at `de8cd038b`.** This table used to
> give line numbers, measured at `e7385984b`. **Four of the six had drifted**
> within a day or two — `builtinheap.pas:2039` → 2066, `ir.inc:12730` → 12521,
> `ir_codegen_xtensa.inc:322` → 359 — and line 2039 today is the middle of
> `PXXStrLoadFile`, which has nothing to do with refcounts.
>
> That is not a tidy-up. **A ticket that cites line numbers rots exactly the way
> the comments it is reporting rot**, and this one reports comment rot, so
> leaving it would have been the same defect one level up. Worse, the drift is
> silent and lands on *plausible* code: a reader who opens `builtinheap.pas:2039`
> finds real Pascal that simply is not the subject, and has no signal that
> anything is wrong.
>
> Found by the same sweep that found `threading-model.md` propping up a false
> limit with `builtinheap.pas:1555` — a line that today discusses string append
> capacity. **A limit backed by a line number is harder to doubt and no more
> likely to be true**, and the line number is the part of any citation most
> certain to be wrong first.

Two near misses, recorded so the next reader does not re-check them:

- `compiler.pas` — the comment **two lines above** the four-target
  check names only x86-64 and i386. Same commit family, same omission, but it is
  an incomplete list rather than a false exclusion.
- `ir_codegen_xtensa.inc` (`grep -n 'No threadsafe lock'`) — *"No threadsafe lock (x86-64-only)"* is
  **correct in effect**: xtensa is genuinely not one of the four, and
  `--threadsafe` is refused there. Only the parenthetical is stale. Leave it or
  fix it with the others; it misleads nobody.

### Site 1 is the one worth looking at

```pascal
{ --threadsafe: one write/writeln statement = one atomic emission.
  ...  x86-64 only — --threadsafe atomics are x86-64-only today. }        <- 2026-07-02
if ThreadSafeMode and ((TargetArch = TARGET_X86_64) or (TargetArch = TARGET_I386)
   or (TargetArch = TARGET_AARCH64) or (TargetArch = TARGET_ARM32)) then  <- 2026-07-06
```

`git blame` dates those two lines four days apart. **The commit that widened the
scope edited the line directly below the comment asserting the opposite and did
not touch it.** It has read that way for 54 days. Nothing is wrong with the
generated code; the sentence is simply a lie told at the point of maximum
authority — inside the lowering that decides the thing.

Site 5 is the one that could *cause* a defect rather than merely record one.
"i386 runs single-threaded" is the premise a reader would carry into writing a
new hand-emitted i386 arm — and a hand-emitted arm is exactly where the softlock
does not reach, because the softlock lives in the Pascal helpers that arm would
be replacing. The correct sentence is `EmitAcquireHeapLock386`'s
(`ir_codegen386.inc:106-111`), which says it precisely and is worth copying:

> *"i386 threadsafe heap locking lives in Pascal (builtinheap's PXXHeapSpin
> under PXX_TS_SOFTLOCK), taken inside PXXAlloc/PXXFree — so the codegen-side
> acquire is a no-op on this target."*

## Why this is a NEW shape for the audit, and the only one so far that argues for tooling

The audit's shape is *two arms, one commented, the sibling unchecked*. This is
not that. There is **one** concept, **one** correct implementation, and a
**scope that widened once** — and the widening silently invalidated every
sentence in the tree that had stated the old scope. There is no sibling arm to
grep for, and no amount of reading the code you are editing helps, because four
of the five sites are nowhere near the change.

The other three shapes wanted a habit, an oracle and a sweep. This one wants
something cheaper and more mechanical than any of them: **when you widen a
target gate, grep the tree for the old scope string before you commit.**
`grep -rn "x86-64.only" compiler/` finds all five in under a second — and would
have on 2026-07-06.

## The fix

Prose only, and it should be one commit so the five stay consistent:

1. `ir.inc:12732` — drop the "x86-64 only" tail; the condition below is the spec.
2. `builtinheap.pas:2039-2040` — "NON-atomic **unless PXX_TS_SOFTLOCK**, which
   --threadsafe defines on i386/aarch64/arm32; x86-64 keeps its lock-prefixed
   inline version."
3. `defs.inc:809` — IR_IO_LOCK is emitted for all four threadsafe targets.
4. `ir_codegen386.inc:4099, 4242` — say what `EmitAcquireHeapLock386:106` says:
   the helpers lock, so the call site does not, and that is not the same as
   single-threaded.
5. Optionally `compiler.pas:1582` and `ir_codegen_xtensa.inc:322`.

## Gate

Comment-only, so `make compiler/pascal26` (self-host byte-identical) is the whole
gate — and it should stay byte-identical, since no code changes. If it does not,
something in the list was not a comment.


## The doc arm, found 2026-08-30 and fixed separately

The same false claim had spread into two **live reference docs**, which is where
a reader is most likely to meet it:

- `devdocs/dev/threading.md` — the heap-contract table said `--threadsafe` was
  *"rejected at compile time"* on i386/arm32/aarch64. Fixed in `ea5d7c6e7`.
- `devdocs/dev/threading-model.md` — said it three more times, including an
  **Open** item asking *"Hard limit or unfinished work? Nobody has asked"* about
  a question answered seven weeks earlier. Fixed in the follow-up.

Both are prose and neither is this ticket's scope; the five `compiler/**`
comments above are still open and still Track A's. Recorded here so whoever takes
them knows the doc arm is already done and does not re-fix it — and because the
spread is the argument for the ticket's own prio: **a stale comment that only a
compiler engineer reads is a nuisance; the same claim in a doc is what a lane
plans around.**

## 2026-08-30 — six of eight fixed (frank-optimize-b4). There were SIX false sites, not five.

**This supersedes the "still open and still Track A's" line in the doc-arm
section directly above**, which was written before these landed; that section's
own content — the two doc fixes — stands.

Found independently while chasing face 113 through `compiler/**`, before this
ticket was read — which is why it is worth saying that the two searches
converged on the same seam from opposite ends, and that neither found the whole
set alone.

**A sixth false site, not in the table above:** `ir_codegen_aarch64.inc:77`,
`EmitHeapAllocLockedA64` — *"Threadsafe locking is x86-64-only."* It sits **212
lines above this same file's own port of `EmitIoLockStubs`**, and the file also
carries the `IR_ATOMIC` lowering that makes aarch64 one of the four. By the
distance metric in the table it is the second-worst after site 1, and it is in
the backend the claim denies.

The ticket says `grep -rn "x86-64.only" compiler/` "finds all five in under a
second". It does — it also finds **~70 hits**, of which the overwhelming
majority are *other* features that genuinely are x86-64-only (DWARF Tier 1, the
asm frontend, `__pxxTlsBase`, `--fpc-mem-errors`, `pypal`'s file ops). The grep's
recall was never the problem; the **classification** of its output was, and one
threadsafe site got read as one of the many legitimate ones. Same shape as this
campaign's standing rule 2: *a census is only as good as the granularity it
classifies at* — and it cost an enumeration that was presented as complete.

### Fixed (comment-only, byte-identical: `9a682089048c` with and without the edits)

| # | site | state |
| --- | --- | --- |
| 2 | `builtinheap.pas` `PXXStrIncRef` | **fixed** — both halves were false; the `{$ifdef PXX_TS_SOFTLOCK}` arm 12 lines down is atomic |
| 3 | `defs.inc` `IR_IO_LOCK` | **fixed** — named the three backend ports |
| 4 | `ir_codegen386.inc` managed-string assign | **fixed** — "the call site does not lock" ≠ "the target cannot be threadsafe" |
| 5 | `ir_codegen386.inc` `IR_COPY_REC_MANAGED` | **fixed** — kept the ticket's own warning about why "i386 runs single-threaded" is the dangerous half |
| 6 | `ir_codegen_aarch64.inc` `EmitHeapAllocLockedA64` | **fixed** — the site this ticket did not list |
| — | `compiler.pas` (near-miss) | **fixed** — and made the load-bearing change: that gate is now stated to be **the authority**, and the other sites point at it instead of repeating the list |

### NOT fixed — other lanes hold the files, so filed rather than touched

| # | site | holder |
| --- | --- | --- |
| 1 | `ir.inc:12540` — the worst one, one line above the four-target condition | **frankC** |
| — | `ir_codegen_xtensa.inc:359` (near-miss, correct in effect) | **frankS** |

### The structural fix, which matters more than the six edits

Every corrected site now **points at `compiler.pas`'s `ThreadSafeMode` gate as
the authority** rather than restating the target list. The list was duplicated
into six comments; a widening invalidated all six at once and there was no
sibling arm to grep, which is exactly what this ticket identified as the new
shape. A pointer cannot go stale on a widening — only the authority can, and it
is the code. The ticket's *"grep for the old scope string before you commit"* is
still the right habit; not writing the list down six times is what makes the
habit cheap.


### A SEVENTH site, found by `docaudit.py targets` — `lexer.inc`, distance TWO LINES

`compiler/lexer.inc` (grep: `the locked runtime` / `threadsafe` directive arm):

> *"Same target gate as the --threadsafe CLI check: the locked runtime exists on
> x86-64 (hand-emitted lock blobs) and i386 (Pascal softlock, see
> PXX_TS_SOFTLOCK); the directive must not silently produce an unlocked
> 'threadsafe' binary on other targets."*

Two lines below it, the condition tests **four** targets, its error message says
`x86-64/i386/aarch64/arm32`, and the *next* error message says
`i386/aarch64/arm32`. So the comment is contradicted three times inside its own
`if` block. By the table's distance metric it ties site 1 for worst.

This ticket already cited `lexer.inc:1844` as *enforcing* the four and
`lexer.inc:1012` for `PXX_TS_SOFTLOCK` — the file was read, and the stale comment
two lines above the cited line was not seen. **A file can be cited as evidence
for the correct answer and still contain the wrong one**, which is a sharper
version of this ticket's own lesson than the six sites are.

**NOT fixed — `lexer.inc` is shared between Track A and Track P and CLAUDE.md
forbids concurrent edits; frankA is in the Pascal frontend right now.** Filed
rather than touched, like `ir.inc`. It is comment-only, so whoever holds the
file can take it in seconds.

**Running total: seven false sites, six fixed, two open** (`ir.inc` — frankC;
`lexer.inc` — A/P shared), plus the xtensa near-miss which is correct in effect.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
