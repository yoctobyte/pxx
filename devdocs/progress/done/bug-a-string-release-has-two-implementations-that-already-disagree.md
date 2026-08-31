---
slug: bug-a-string-release-has-two-implementations-that-already-disagree
track: A
prio: 45
type: bug
status: done
owner: frankB
blocked-by: []
summary: "FIXED 2026-08-31 on x86-64 by option (b) PLUS deleting the compensation the disagreement required. The release blob and the retain blob now carry the MSTR_STATIC_RC guard PXXStrDecRef/PXXStrIncRef always had, so a saturated static block is never written on any backend; and EmitStaticLitHandle's `inc qword [rax-16]` — which existed ONLY to cancel the unguarded `dec` — is gone, which is the shape aarch64 has had since 2026-08-30. Verified: fixedpoint converged (4ae31c9e10cf), the emitted guard read back out of the disassembly, and a probe showing a static refcount at exactly $40000000 after 1M retain/release cycles, with and without --threadsafe. Self-compile code shrank 36,864 bytes (9,821,976 -> 9,785,112) as 9,307 literal sites lost their retain. Option (a) — delete the blob, call PXXStrDecRef — is REFUTED by measurement, not deferred: the blob is 7.72% of a self-compile with its samples on the call/ret rather than the body, so routing it through a Pascal routine would be strictly worse. What is NOT fixed and moved to bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower: under --threadsafe both blobs still ACQUIRE THE HEAP SPINLOCK before the guard, so a static release on 12 workers still serialises on one lock line."
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



---

## RESOLUTION 2026-08-31 (frankB) — guarded both blobs, deleted the compensation

Binary `4ae31c9e10cf607bad6debc43131f75f66944d93bafbaf8c6bab96b44cbdcbf5`,
`converged after 2 round(s)`.

### What changed, and why it is one change and not three

`compiler/ir_codegen.inc`, three edits that only make sense together:

1. **Release blob** (`AnsiStrReleaseAddr`) — added
   `cmp qword [rax-16], MSTR_STATIC_RC` / `jae done`, the guard `PXXStrDecRef`
   has always had and this blob bypassed.
2. **Retain blob** (`EmitAnsiStrRetainLocked`) — the same guard, because
   `builtinheap.pas` says in terms that the pair *"must move together, because
   suppressing one direction only is what would let a static block's count
   drift."*
3. **`EmitStaticLitHandle`** — **deleted** its `inc qword [rax-16]`. That
   increment was never wanted for itself; its own comment says it existed to
   restore the ownership convention that the release blob's *unguarded* `dec`
   broke. Guard the `dec` and the compensation has nothing left to compensate.

That is the root-cause shape rather than the microfix: the pair is now balanced
by **both sides doing nothing**, not by an increment cancelling a decrement.
It is also exactly what `EmitStaticLitHandleA64` has done since 2026-08-30 —
this brings the hand-written x86-64 path to the design the other six backends
already had, which is `normalise-dont-special-case` applied to the second path
that stayed broken.

### Verified

- **Fixedpoint** converged, twice, byte-identical.
- **The guard was read back out of the binary**, not assumed:
  `40017f: 48 81 78 f0 00 00 00 40  cmp QWORD PTR [rax-0x10],0x40000000`
  in the retain thunk and the same at `400197` in the release thunk.
- **Positive control on the value:** a probe reading `[Pointer(s)-16]` reports
  the static refcount at exactly `$40000000` before and after 1,000,000
  retain/release cycles — with and without `--threadsafe`. (Note it does *not*
  discriminate this change on its own: before it, the unguarded `inc`/`dec`
  balanced, so the value was right while the page was written 2M times. What
  the change removes is the WRITE, and the disassembly is what shows that.)
- **Code size:** 9,821,976 -> 9,785,112, **-36,864 bytes**, which is 9,307
  literal sites x 4 bytes minus the 20 the two guards cost.
- `testmgr --tier quick` PASS. `gate.sh quick` is RED, **pre-existing and not
  this change** — a clean tree at the same commit fails identically
  (`bug-a-two-different-binaries-both-pass-the-self-host-fixedpoint-for-one-source-tree`,
  whose named lead I confirmed: `compiler/builtin/builtinheap.pas` and
  `stable_linux_amd64/default/builtin/builtinheap.pas` differ by 26 KB right now).

### Measured

| workload | before | after | |
| --- | ---: | ---: | --- |
| self-compile of `compiler.pas` | 12.93 s | 12.65 s | **not a claim** — a null A/B of two identical binaries on this box moved 1.2%, so 2.2% is not resolved |
| shared-literal `parallel for`, 4M, 12 workers | 1.18 s | **0.95 s** | ~19% |
| same loop serial, `--threadsafe` | 0.14 s | **0.12 s** | ~14% |

The self-compile number is reported as unresolved on purpose. The parallel and
serial threadsafe numbers are far outside that noise floor and are the real
result: they are the locked `inc`/`dec` on a shared static block disappearing.

### Option (a) is refuted, not deferred

The ticket left open whether to delete the blob and call `PXXStrDecRef`. The
profile answers it: the release blob is **7.72%** of a self-compile (30,520
samples, `tools/pxxprof` through the `.map`), and its samples pile onto the
entry `test rax,rax` (3.35%) and the `ret` (2.60%) rather than the body — the
signature of call overhead, on **300,745 call sites**. Replacing a 4-instruction
leaf with a call into compiled Pascal would be strictly worse. The two
implementations stay, now agreeing.

### Residual, handed to the ticket that owns it

Under `--threadsafe` both blobs still call `EmitAcquireHeapLock` **before** the
nil test and the guard, so releasing a static literal on 12 workers still
serialises every worker on one spinlock line for a path that then does nothing.
That is why the parallel loop above is still ~8x its serial time after this fix.
Hoisting the nil test and the guard above the lock is safe — the lock protects
the free list, and a saturated block's count is immutable, which is the same
argument `PXXStrIncRef` already makes for its own lock-free read — but it needs
rel32 patching across the lock body and lands in threadsafe-only code, so it is
a separate change. Written up in
[[bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower]].

## Log
- 2026-08-31 — resolved, commit d782926ce.
