---
prio: 40
track: A
status: unfinished
owner: 
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

## Parked 2026-08-30

five backends landed and clean; the x86-64 half was built, measured 2.3% slower at 1/11 pairs and dropped. What remains is a design fork, not implementation: x86-64 -O2 still writes its static blocks and a per-release floor test is the priced-and-rejected answer.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

---

## 2026-08-30, later — the x86-64 half RE-MEASURED: mechanism confirmed, net SLOWER, and it belongs behind `-Os` that does not exist yet

**Prompted by frankwasm, who was right to push**: my first report gave one
program's result and a mechanism story, and a story attached to a real number is
the most durable kind of wrong, because nobody re-measures a confirmed result.
Four shapes, then the real workload. HEAD `238a545c19f8` vs guarded
`af64bbba52cc` — the two differ **only** in the x86-64 guard.

| shape | what it isolates | delta | guard faster in |
| --- | --- | ---: | ---: |
| 4 managed copies, **zero literals** | the guard as PURE COST | +3.66% | 2/15 |
| 4 literal stores, nothing else | its SAVING at maximum | −3.96% | 12/15 |
| mixed | a realistic ratio | −3.04% | 10/15 |
| no strings at all | am I measuring the box? | +6.27% | 7/15 |
| **`compiler.pas`, the real workload** | **the population that ships** | **+6.95%** | **3/9** |

**The mechanism is confirmed by the two extremes**: cost tracks retain density,
saving tracks literal density, exactly as predicted. **The net on real code is
slower**, because compiler-shaped code is retain-heavy — that is the 3-of-9 row,
on a 16-second workload where noise matters least in relative terms.

**Two honesty notes that matter more than the table.**

**The mixed microbenchmark flipped SIGN between runs** — `+2.3%` at 1/11 earlier,
`−3.04%` at 10/15 here, same program, same isolated change. Not a contradiction:
its literal/retain ratio sits near break-even, so it is a bad net indicator and
neither run was wrong. **My earlier "+2.3% slower, direction solid at p≈0.006" is
withdrawn** — that p-value assumed independence and stationarity and this box is
neither.

**The no-strings control moved 6.27% while its sign test said 7/15**, i.e. a coin
flip. That is the noise floor made visible: at this load, min-of-15 on a 5 ms
program carries ~6% of noise, so **no magnitude below that is resolved here** and
only the sign counts mean anything. Quote the signs, not the percentages.

## Recommendation: `-Os`, and note what that actually costs

Per the O charter — *"a mature pass that is merely not universally beneficial is a
flag"*, and *"an author chooses WHICH trade, not HOW MUCH"* — a change that costs
single-digit percent on retain-heavy code and buys **36,864 bytes** of `code` is
the textbook named-flag case, not a `-O2` candidate and not a design fork.

**But `-Os` does not exist.** There is no `-Os`, no `-Ofast`, no
`-funroll-loops` — the charter names them as the shape a trade-off takes, and
none has been built. So this is the **first candidate for the first named
trade-off flag**, which makes the open question *"do we introduce that axis, and
what is the bar for putting something behind it"* rather than anything about this
pass. That is a bigger question than a p40 optimisation ticket and should not be
settled inside one.

## Regenerating the change

Five hand-emitted x86-64 sites take a floor test — the two `*RetainLocked`
sequences (restructured from an `EmitAsmX64` `.done` label to manual rel8
patches, so the guard's jump can share the target), the two `*ReleaseLocked`
sequences, and the `AnsiStrReleaseAddr` blob — plus deletion of the four-byte
`inc qword [rax-16]` in `EmitStaticLitHandle`. The only non-obvious part:

```pascal
procedure EmitStaticRCGuardX64(var patchPos: Integer);
begin
  EmitB($48); EmitB($81); EmitB($78); EmitB($F0);   { cmp qword [rax-16], imm32 }
  EmitB(MSTR_STATIC_RC and $FF);
  EmitB((MSTR_STATIC_RC shr 8) and $FF);
  EmitB((MSTR_STATIC_RC shr 16) and $FF);
  EmitB((MSTR_STATIC_RC shr 24) and $FF);
  EmitB($7D); patchPos := CodeLen; EmitB(0);        { jge done }
end;
```

Built from `MSTR_STATIC_RC` rather than spelled `00 00 00 40` so there is one
spelling of "is this static" per arch. Verified by disassembly to decode as
`cmpq $0x40000000,-0x10(%rax)`. `PatchRel8` calls `CheckRel8` and errors loudly,
so the rel8 hazard this ticket was split out for cannot bite silently.

**Provenance of every number above:** the compilers were rebuilt from a `pinned`
seed and converged to the same sha as builds seeded from their own output — the
**anti-Thompson agreement** property (`tools/selfhost_fixedpoint.sh:23`), which
`make compiler/pascal26` cannot give you and `gate.sh` can. Sources define ONE
fixedpoint, so the binaries these numbers came from are not carrying anything the
sources do not.
