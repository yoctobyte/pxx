---
slug: bug-a-string-release-has-two-implementations-that-already-disagree
track: A
prio: 45
type: bug
status: backlog
owner: unassigned
blocked-by: []
summary: "Releasing an AnsiString has TWO implementations and they are not equivalent. x86-64 emits a hand-written blob (`AnsiStrReleaseAddr`, `test rax,rax` / `dec qword [rax-16]`) and never calls the runtime routine; every cross backend calls the Pascal `PXXStrDecRef`. They already DISAGREE: the routine exits without writing when the refcount is at or above `PXX_STATIC_RC_FLOOR`, so a static literal block is never written, and the blob's fast path has no such test and decrements unconditionally. Harmless today only because `MSTR_STATIC_RC` is $40000000 and cannot reach zero -- but the routine's own comment says the guard exists to avoid DIRTYING a shared page, which the blob does on every release of a literal, and which was measured at 1600x under qemu on the path that motivated the guard. Two consequences beyond the page: any future change to release semantics has to be made twice or it is made once and is wrong on five targets, and every x86-64 refcount measurement must now say which of the two paths it went through. Found while instrumenting bug-a-no-cross-target-can-build-the-compiler-itself, where a heap-debug check added to PXXStrDecRef was structurally invisible on x86-64 for exactly this reason."
---

# A string release has two implementations, and they already disagree

## Measured

`grep -c` over the backends, at `4f6b70995c3a`:

| backend | calls `PXXStrDecRef` | hand-emitted release blob |
| --- | --- | --- |
| x86-64 | 5 | **4** |
| arm32 | 1 | 0 |
| aarch64 | 1 | 0 |
| riscv32 | 10 | 0 |

x86-64 is the outlier. `ir_codegen.inc`, at `AnsiStrReleaseAddr`:

```
  EmitAcquireHeapLock
  test rax, rax        ; jz done
  dec qword [rax-16]   ; (lock dec under --threadsafe)
  jnz done
  ...free...
```

and `PXXStrDecRef` in `builtinheap.pas`:

```pascal
  if PWord(rcAddr)^ >= PXX_STATIC_RC_FLOOR then Exit;   { static literal }
  rc := PWord(rcAddr)^ - 1;
  PWord(rcAddr)^ := rc;
  if rc = 0 then PXXFree(...);
```

**The guard is the difference.** `PXXStrIncRef`'s comment states why it exists:
a static literal block *"must never be WRITTEN, not merely never freed"*, because
a store dirties a page shared with code — measured at **1600x under qemu** — and
defeats ever placing those blocks in a non-writable segment. The blob writes.

## Why this is a bug and not a style note

The two paths are not interchangeable, so "one concept, two implementations" is
not the whole complaint: they have already drifted, and the drift is silent. It
is invisible today because `MSTR_STATIC_RC` is `$40000000` and a decrement
cannot drive it to zero, so nothing is freed wrongly — the cost is the dirtied
page and the fact that **the next change to release semantics will be made once
and be wrong on five targets, or made twice and drift again.**

## How it was found, which is the part worth keeping

A `PXX_HEAP_DEBUG` check added to `PXXStrDecRef` (a stale-handle detector) was
**structurally unable to fire on x86-64** — the target it was developed on —
because releases there never enter that routine. It was caught only by a
positive control aimed at the exact mechanism; the generic data-write control
passed happily while the thing it stood in for could not be observed at all.

## Fix, and the reason to be careful

Deleting the blob in favour of the call is the obvious shape and is a
**performance** decision as much as a correctness one: the blob exists because
the call cost showed up in a profile (`~11%` of a one-line NilPy compile was on
the pushes and pops it removes, per the comment above it). So the honest options
are (a) delete the blob and measure what it costs, or (b) keep it and add the
`PXX_STATIC_RC_FLOOR` test to it, which removes the disagreement without
removing the mechanism. **(b) is smaller and does not close the question**, and
the question — why release is emitted twice — is what root-cause-over-microfix
would have you answer.

## Gate

`make compiler/pascal26` plus a literal-heavy repro; if (a), a benchmark.
