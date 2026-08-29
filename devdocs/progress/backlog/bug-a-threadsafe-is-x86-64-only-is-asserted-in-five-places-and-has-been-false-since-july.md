---
track: A
prio: 25
type: bug
status: open
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

| # | site | asserts | refuted by | distance |
| --- | --- | --- | --- | --- |
| 1 | `ir.inc:12730-12733` | *"x86-64 only — --threadsafe atomics are x86-64-only today."* | `ir.inc:12734`, the condition it introduces, which tests all four | **ONE LINE** |
| 2 | `builtinheap.pas:2039` | `PXXStrIncRef` is *"NON-atomic — threadsafe mode is x86-64 only"* | its own `{$ifdef PXX_TS_SOFTLOCK}` atomic arm, `builtinheap.pas:2050` | **8 lines** |
| 3 | `defs.inc:809` | `IR_IO_LOCK` is *"x86-64 + ThreadSafeMode only"* | real lock calls in `ir_codegen386.inc:3801`, `ir_codegen_aarch64.inc:4336`, `ir_codegen_arm32.inc:4497` | **cross-file, 3 backends** |
| 4 | `ir_codegen386.inc:4099` | *"no shim/lock; threadsafe is x86-64-only"* | `compiler.pas:1586`, `lexer.inc:1012` | **cross-file** |
| 5 | `ir_codegen386.inc:4242` | *"Threadsafe locking is x86-64-only; **i386 runs single-threaded**"* | same | **cross-file** |

Two near misses, recorded so the next reader does not re-check them:

- `compiler.pas:1581-1583` — the comment **two lines above** the four-target
  check names only x86-64 and i386. Same commit family, same omission, but it is
  an incomplete list rather than a false exclusion.
- `ir_codegen_xtensa.inc:322` — *"No threadsafe lock (x86-64-only)"* is
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
