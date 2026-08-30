---
prio: 40
track: A
status: working
owner: frank-optimize
---

# Static literal blocks should never be written to at all

- **Type:** feature (Track O — optimization; file-owned by Track A per O's rule)
- **Split out of**
  [[bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu]]
  on 2026-08-30, deliberately, at the coordinator's call and mine. That ticket's
  fix 1 (page-align the data section) is the general answer and is being taken
  separately. This is fix 2, and it is the better answer *for the pass* — but
  it is not a tail-end addition to another ticket's session, for the reason in
  the last section.

## What

`feature-opt-o3-static-string-literals` builds a managed-string block in the
data section in front of every pooled literal, with a saturated refcount
(`MSTR_STATIC_RC` = 2^30). The emitters then hand that address out **and take a
reference**, because every call site they replaced used to receive a fresh
block at `rc=1` and take ownership of it. Without the increment, each
store/overwrite cycle nets −1 on the static block, and 2^30 is reachable: this
ticket's own subject runs for ~400 seconds and 2.5M literal stores a second is
an ordinary rate.

So the block is written on every literal evaluation. Make it never written
instead: guard the refcount operations on a saturated floor.

```
if rc >= MSTR_STATIC_FLOOR then Exit;     { a compiler-built block: never counted }
```

## Why it is worth doing even though fix 1 removes the reported symptom

- **It deletes the write from the hot path.** x86-64 loses `inc qword [rax-16]`
  at every literal site (4 bytes each, 8 sites); **aarch64 loses an entire
  `PXXStrIncRef` CALL**, which is the one place the aarch64 port is measurably
  worse than the x86-64 one and is called out as such in its own commit.
- **It makes the blocks genuinely read-only**, which is a precondition for ever
  putting them in a non-writable segment — the thing that would make the page
  hazard structurally impossible rather than merely avoided.
- **The failure mode is unusually forgiving.** A *missed* guard at some
  refcount site drifts a 2^30 refcount. That is a performance miss, not a
  correctness one: the count never reaches 0 (no free) and never reaches 1
  (`PXXStrUnique` and the inlined SetLength fast path both still copy). So the
  guard can be added incrementally and a site overlooked is not a wrong value —
  which is rare enough in this runtime to be worth saying out loud.

## Sites

`PXXStrIncRef` and `PXXStrDecRef` in `builtinheap.pas` cover **five backends at
once** — i386, arm32, aarch64, riscv32 and xtensa all call them. x86-64 is the
exception and hand-emits, at five places in `ir_codegen.inc`: the two inline
retain sequences (~139, ~159), the two inline release sequences (~179, ~199),
and the `AnsiStrRetainAddr` / `AnsiStrReleaseAddr` blobs (~2571, ~2590).

## The reason this is its own session

Adding a compare-and-branch to five hand-emitted x86-64 sequences **grows
them**, and growing an emitter is exactly what arms
[[bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows]]: `Code[p] :=
Byte(CodeLen - (p + 1))` truncates silently past 127 bytes of span, turning a
forward jump into a backward one into the middle of an instruction. Several of
these sites sit inside branchy sequences with exactly that patch idiom around
them.

**Check the span first, not last.** The tell if it is missed is `rip` faulting
at a mid-instruction address — which cannot arise from linear execution, so it
is a proof rather than a clue, and it converts an open search into an
enumeration of rel8 jumps targeting that address.

This ticket exists because that check deserves to be the first thing done in a
session rather than the last thing remembered in someone else's.

## Gate

Track A's: `make compiler/pascal26` (byte-identical self-host) plus the
existing `test_static_string_literals` at -O0/-O3 on x86-64 and aarch64 — and,
because the point is that a write disappears, a direct check that it has:
`-dPXX_ALLOC_CENSUS` is the wrong instrument here (it counts allocations, and
none of these are), so verify by disassembly or by measuring the same qemu
subject that made fix 1 necessary.

---

## 2026-08-30 frank-optimize — LANDED for five backends, MEASURED AND DROPPED for x86-64

**Landed:** `PXXStrIncRef`/`PXXStrDecRef` skip the refcount write on a saturated
block (i386, arm32, aarch64, riscv32, xtensa in one edit), and
`EmitStaticLitHandleA64` no longer takes a reference at all — on aarch64 that
deletes a whole `call PXXStrIncRef` per literal evaluation.

| | before | after | |
| --- | ---: | ---: | ---: |
| aarch64/qemu, literal-heavy loop | 605.1 ms | 399.7 ms | **−33.9%, 9/9 pairs** |
| same loop, NO literals (control) | 66.6 ms | 68.5 ms | +2.9%, 4/9 |
| x86-64, literal-heavy loop | 9.82 ms | 10.05 ms | **+2.3% SLOWER, 1/11** |
| x86-64, no-literal control | 3.96 ms | 3.97 ms | +0.4%, 6/11 |

**The "What" section above is wrong about x86-64 and that is why the x86-64 half
did not land.** It says the change "deletes the write from the hot path — x86-64
loses `inc qword [rax-16]` (4 bytes each, 8 sites)". You cannot delete it: a
**generic** retain cannot know its argument is static. The only available form is
a runtime floor test on the five hand-emitted sequences plus deletion at the
literal site. Built, correct (`cmpq $0x40000000,-0x10(%rax)` verified by
disassembly), self-hosting, **−36,864 bytes of `code`** — and 2.3% slower,
because a load+cmp+branch on every managed retain and release costs more than the
one store it saves on the literal subset. Parked as a patch. A delivered *size*
result is not a speed result.

**The rel8 precondition this ticket was split out for is GONE:** `PatchRel8` now
calls `CheckRel8`, which errors loudly (`bug-a-a-rel8-jump-patch-truncates-...`,
resolved). The five-site version built without incident. The ticket's own
prescription was a hypothesis about a world that moved.

## What is still open, and it is now a DESIGN question, not an implementation

**x86-64 `-O2` — the configuration that ships, and where `EmitStaticLitHandle`
went live in `440c822e6a80` — still writes its static literal blocks.** It incs at
the literal site and decs on an inlined release; balanced, so nothing is freed and
nothing is wrong. But the block is *written*, so it still dirties a page shared
with code and still cannot move to a non-writable segment. **Five backends are
clean and the shipping one is not.** Raised by frankwasm from the RSS table before
anyone had said so — an unmoved number is the shape that most needs a second look.

The fork, for whoever takes it: making x86-64 `-O2` stop writing needs something
other than a per-release test, because that test is measured at −2.3%. Candidates
nobody has priced — a static-block bit checked only on the *free* path rather than
every release; keeping the retain but making the block's page private; or accepting
the write and pursuing the non-writable segment by a different route. If the
answer is "not worth it", that is a legitimate close, but it should be a decision
rather than a silence.

**Not claiming this further.** Released.
