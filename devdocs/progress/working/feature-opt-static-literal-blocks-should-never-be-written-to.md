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
