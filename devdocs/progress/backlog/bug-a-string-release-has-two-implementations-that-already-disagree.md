---
slug: bug-a-string-release-has-two-implementations-that-already-disagree
track: A
prio: 45
type: bug
status: backlog
owner: unassigned
blocked-by: []
summary: "Releasing an AnsiString has TWO implementations and they are not equivalent. x86-64 emits a hand-written blob (`AnsiStrReleaseAddr`, `test rax,rax` / `dec qword [rax-16]`) and never calls the runtime routine; every cross backend calls the Pascal `PXXStrDecRef`. They already DISAGREE: the routine exits without writing when the refcount is at or above `PXX_STATIC_RC_FLOOR`, so a static literal block is never written, and the blob's fast path has no such test and decrements unconditionally. Bounded today, but NOT for the reason it looks: `builtinheap.pas` explicitly refutes "$40000000 cannot be reached" (2.5M literal stores a second for 400 seconds reaches it). It is bounded because the mismatch un-arms itself -- an unguarded decrement takes rc to FLOOR-1, at which point guarded increments stop being skipped -- so rc oscillates just under the floor, bounded by live references and never by elapsed time. The real cost is the dirtied page: the routine's own comment says the guard exists to avoid DIRTYING a shared page, which the blob does on every release of a literal, and which was measured at 1600x under qemu on the path that motivated the guard. Two consequences beyond the page: any future change to release semantics has to be made twice or it is made once and is wrong on five targets, and every x86-64 refcount measurement must now say which of the two paths it went through. Found while instrumenting bug-a-no-cross-target-can-build-the-compiler-itself, where a heap-debug check added to PXXStrDecRef was structurally invisible on x86-64 for exactly this reason."
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
is bounded today, and the reason matters because the obvious one is wrong.
`builtinheap.pas`'s own `PXX_STATIC_RC_FLOOR` comment refutes "`$40000000` is
out of reach" in terms — *"2.5M literal stores a second for 400 seconds"*. What
actually bounds it is that **the mismatch un-arms itself**: an unguarded
decrement takes rc to `FLOOR-1`, at which point every *guarded* increment stops
being skipped and behaves normally, so rc oscillates just under the floor,
bounded by the number of simultaneously live references and never by elapsed
time. (On x86-64 the pair happens to be balanced outright — `EmitStaticLitHandle`
emits an unguarded `inc qword [rax-16]` to match the blob's unguarded `dec`.)
Nothing is freed wrongly either way — the cost is the dirtied
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

## 2026-08-31 — the static-literal convention exists on TWO of seven backends

Measured while running an IR differential for
[[bug-a-no-cross-target-can-build-the-compiler-itself]]: compile one program,
dump the shared IR, then compare where each backend emits retains and releases
against that same IR.

`EmitStaticLitHandle` (`ir_codegen.inc`) and `EmitStaticLitHandleA64`
(`ir_codegen_aarch64.inc`) are the only two. `grep -c EmitStaticLitHandle`:

| backend | static-literal path |
| --- | --- |
| x86-64 | yes |
| aarch64 | yes |
| **i386, arm32, riscv32, wasm32, xtensa** | **none** |

So for an `IR_CONST_STR` node, x86-64 and aarch64 at `-O2` hand back the pooled
literal's address as a ready-made managed handle, and the other five call
`PXXStrFromLit` — a runtime call, a `PXXAlloc`, a byte copy of data already in
the image, and a `PXXFree` when the reference dies, **per literal evaluation**.
Confirmed by disassembly, resolving BL/BL-imm26 targets inside one procedure
through the `--map` file: for `a := 'hello'`, arm32 emits a `PXXStrFromLit` call
and aarch64 emits none, with retain/release counts otherwise identical (5
`PXXStrDecRef` + 1 `PXXStrIncRef` on both).

**Two things follow, and they pull in opposite directions:**

1. It sharpens this ticket. The disagreement is not only *how* release is
   emitted, it is *what release is being asked to release* — an owned `rc=1`
   heap block on five targets, a saturated static block on two. Any change to
   release semantics now has to be correct under both conventions.
2. It is also a **Track O** item on its own (~a heap round-trip per literal on
   five backends, including both 32-bit targets and both ESP ISAs). Not filed
   separately yet: the O charter wants delivered value measured, not opportunity
   inferred from an instruction census, and nobody has benchmarked it.

**What it does NOT explain:** the arm32 write-after-free that prompted the
differential. riscv32 and i386 also lack the static path and are clean (0
reports), so heap-resident literals are not sufficient to produce the symptom.

